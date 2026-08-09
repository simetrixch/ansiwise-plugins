import 'package:ansiwise_api/ansiwise_api.dart';
import 'detect_public_nic.dart';
import 'write_connmark_nft_table.dart';
import 'write_netplan_public_src_routing.dart';

/// Writes the script that loads the marking rules and installs the rule keyed on the mark.
///
/// **The rule has to be MASKED, and that is the reason this script exists at all.** The network
/// configuration cannot express a masked match, and an unmasked one never fires: the reply packet
/// carries the network agent's own mark as well, so the two marks together are not the one value an
/// unmasked rule is looking for. The rule reads correctly, matches nothing, and the steering
/// silently does not happen.
///
/// **The script removes any rule already at its own number before adding one, and does it in a
/// loop.** Adding without removing leaves a second identical rule on every run, and a single removal
/// leaves whatever a previous run added twice.
final class WritePublicSrcRoutingScript extends ReversibleStep {
  /// Writes the script at [path], installing the rule at [priority].
  const WritePublicSrcRoutingScript({
    required this.path,
    required this.rulesPath,
    required this.mark,
    required this.table,
    required this.priority,
  });

  /// Builds the step from what the program gave it.
  factory WritePublicSrcRoutingScript.fromArguments(Arguments arguments) =>
      WritePublicSrcRoutingScript(
        path: arguments.text('path'),
        rulesPath: arguments.text('rules_path'),
        mark: arguments.text('mark'),
        table: arguments.integer('table'),
        priority: arguments.integer('priority'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the script the unit runs',
      required: false,
      defaultValue: defaultPath,
    ),
    ArgumentSpec(
      name: 'rules_path',
      kind: ArgumentKind.text,
      describes: 'the marking rules the script loads',
      required: false,
      defaultValue: WriteConnmarkNftTable.defaultPath,
    ),
    ArgumentSpec(
      name: 'mark',
      kind: ArgumentKind.text,
      describes: 'the mark the rule is keyed on',
      required: false,
      defaultValue: WriteConnmarkNftTable.defaultMark,
    ),
    ArgumentSpec(
      name: 'table',
      kind: ArgumentKind.integer,
      describes: 'the routing table the marked replies are steered into',
      required: false,
      defaultValue: WriteNetplanPublicSrcRouting.publicTable,
    ),
    ArgumentSpec(
      name: 'priority',
      kind: ArgumentKind.integer,
      describes: 'the number the rule keyed on the mark is installed at',
      required: false,
      defaultValue: defaultPriority,
    ),
  ];

  /// Where the script goes.
  static const String defaultPath = '/usr/local/sbin/hostyour-public-src-routing.sh';

  /// The number the rule is installed at.
  static const int defaultPriority = 10100;

  /// `0755` — a script the unit runs.
  static const int mode = 0x1ed;

  /// The script's path.
  final String path;

  /// The marking rules it loads.
  final String rulesPath;

  /// The mark the rule is keyed on.
  final String mark;

  /// The table the marked replies go into.
  final int table;

  /// The number the rule sits at.
  final int priority;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (await DetectPublicNic.detect(context) == null) {
      return const CheckResult.satisfied(
        'nothing is steered on this machine, so there is no rule to install',
      );
    }
    if (!await context.files.exists(path)) {
      return const CheckResult.ready();
    }
    return await context.files.read(path) == script
        ? CheckResult.satisfied('$path already holds what this step writes')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.diff(
    path,
    before: await context.files.exists(path) ? await context.files.read(path) : '',
    after: script,
  );

  @override
  Future<void> apply(StepContext context) async {
    await context.files.write(path, script, mode: mode);
  }

  @override
  Future<void> undo(StepContext context) async {
    await context.shell.run(Command('ip', ruleArguments('del')));
    await context.files.delete(path);
  }

  /// The arguments that [verb] the rule keyed on the mark.
  List<String> ruleArguments(String verb) => <String>[
    '-4',
    'rule',
    verb,
    'from',
    'all',
    'fwmark',
    '$mark/$mark',
    'lookup',
    '$table',
    'priority',
    '$priority',
  ];

  /// The script itself.
  String get script =>
      '#!/bin/sh\n'
      '# Loads the marking rules and installs the rule the network configuration cannot express.\n'
      '#\n'
      '# The mask is required. A reply also carries the network agent\'s own mark, so a match on the\n'
      '# bare value would never fire — it would read correctly and steer nothing.\n'
      'set -e\n'
      '\n'
      'nft -f $rulesPath\n'
      '\n'
      '# Every rule already at this number goes first, in a loop: adding without removing leaves a\n'
      '# second identical rule on every run, and removing once leaves whatever ran twice before.\n'
      'while ip -4 rule del priority $priority 2>/dev/null; do :; done\n'
      'ip ${ruleArguments('add').join(' ')}\n';
}
