import 'package:ansiwise_api/ansiwise_api.dart';
import 'detect_public_nic.dart';
import 'write_connmark_nft_table.dart';
import 'write_netplan_public_src_routing.dart';
import 'write_public_src_routing_script.dart';

/// Writes the service that runs the steering script, and takes it away again when it is stopped.
///
/// **What the script installs is kernel state, and kernel state does not survive.** A restart, or
/// anything that empties the machine's rule set, takes both the marking rules and the rule keyed on
/// the mark away — and nothing about the files on disk says so. A service that runs the script after
/// the network is up is what puts them back.
///
/// **Stopping the service is what removes them, which is why it says how.** Deleting the files does
/// not: the rules are already in the kernel. So the service carries the two commands that take them
/// out, and stopping it is the first act of any teardown.
final class WritePublicSrcRoutingUnit extends ReversibleStep {
  /// Writes the service at [path], running the script at [scriptPath].
  const WritePublicSrcRoutingUnit({
    required this.path,
    required this.scriptPath,
    required this.rulesPath,
    required this.mark,
    required this.table,
    required this.priority,
  });

  /// Builds the step from what the program gave it.
  factory WritePublicSrcRoutingUnit.fromArguments(Arguments arguments) => WritePublicSrcRoutingUnit(
    path: arguments.text('path'),
    scriptPath: arguments.text('script_path'),
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
      describes: 'the service file',
      required: false,
      defaultValue: defaultPath,
    ),
    ArgumentSpec(
      name: 'script_path',
      kind: ArgumentKind.text,
      describes: 'the script the service runs',
      required: false,
      defaultValue: WritePublicSrcRoutingScript.defaultPath,
    ),
    ArgumentSpec(
      name: 'rules_path',
      kind: ArgumentKind.text,
      describes: 'the marking rules, named here because stopping the service removes them',
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
      defaultValue: WritePublicSrcRoutingScript.defaultPriority,
    ),
  ];

  /// Where the service file goes.
  static const String defaultPath = '/etc/systemd/system/$unitName';

  /// What the service is called.
  static const String unitName = 'hostyour-public-src-routing.service';

  /// `0644` — a service file the service manager reads.
  static const int mode = 0x1a4;

  /// The service file's path.
  final String path;

  /// The script it runs.
  final String scriptPath;

  /// The marking rules stopping it removes.
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
        'nothing is steered on this machine, so there is no service to install',
      );
    }
    if (!await context.files.exists(path)) {
      return const CheckResult.ready();
    }
    return await context.files.read(path) == unit
        ? CheckResult.satisfied('$path already holds what this step writes')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.diff(
    path,
    before: await context.files.exists(path) ? await context.files.read(path) : '',
    after: unit,
  );

  @override
  Future<void> apply(StepContext context) async {
    await context.files.write(path, unit, mode: mode);
    await context.shell.run(const Command('systemctl', <String>['daemon-reload']));
  }

  @override
  Future<void> undo(StepContext context) async {
    // Stopping it first is what takes the rules out of the kernel — deleting the file would leave
    // them there with nothing on the machine saying they exist.
    await context.shell.run(const Command('systemctl', <String>['disable', '--now', unitName]));
    await context.files.delete(path);
    await context.shell.run(const Command('systemctl', <String>['daemon-reload']));
  }

  /// The service file itself.
  String get unit {
    final String rule = WritePublicSrcRoutingScript(
      path: scriptPath,
      rulesPath: rulesPath,
      mark: mark,
      table: table,
      priority: priority,
    ).ruleArguments('del').join(' ');
    return '[Unit]\n'
        'Description=Steer replies to traffic that arrived on the public address\n'
        '# The rules are installed on the interfaces, so nothing may run before they are up.\n'
        'After=network-online.target\n'
        'Wants=network-online.target\n'
        '\n'
        '[Service]\n'
        'Type=oneshot\n'
        'RemainAfterExit=yes\n'
        'ExecStart=$scriptPath\n'
        '# Stopping the service is what takes the rules out of the kernel. Deleting the files does\n'
        '# not, because by then the kernel is holding them.\n'
        'ExecStop=-/usr/sbin/nft destroy table inet ${WriteConnmarkNftTable.tableName}\n'
        'ExecStop=-/usr/sbin/ip $rule\n'
        '\n'
        '[Install]\n'
        'WantedBy=multi-user.target\n';
  }
}
