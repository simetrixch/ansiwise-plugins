import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'kubectl.dart';

/// Sets one key of one ConfigMap, and rolls the workload that reads it.
///
/// **The roll is part of this and not a step of its own.** An object changed and not rolled is a
/// change nothing is running yet: the process that read the key at start-up goes on running with
/// what the key held then, and every command before this one reported success. So the program names
/// the workload that reads the key, and the change and the restart are one act.
///
/// **The key is set to exactly what the program holds, never merged into.** A merge drifts with
/// whatever put the object there — an addon that ships a new default adds it, and the same machine
/// then comes out differently depending on which version installed it. What is written here is the
/// whole value, so the result is the same on every version and on every machine.
///
/// **A ConfigMap and nothing else with a `data` field.** A Secret spells the same field in base64,
/// so text written into one would be stored as something other than what it says and read back as
/// nonsense. The name of this step is what it can actually do.
///
/// **What the undo puts back is what was read before the change, and a copy also goes to a file.**
/// The object being changed is the only copy the cluster keeps, so reading it afterwards would read
/// this step's own value. The file is what stays on the machine, named in the log, for whoever comes
/// looking once the run is over.
///
/// **The content may carry one marked slot, and only one.** A program file ships to every
/// installation, so a value belonging to ONE machine cannot stand in it — see [placeholder].
/// Anything else between angle brackets is content and is written as it stands, because a ConfigMap
/// key legitimately holds markup.
///
/// **What this can measure, and what it cannot.** The check compares the key against what the
/// program holds. It cannot ask whether the running process has re-read it, because the value only
/// exists inside that process — so a key somebody changed by hand and never rolled reads here as
/// satisfied. Every change this step makes itself is rolled, in the same apply.
final class PatchConfigmapKey extends ReversibleStep<String?> {
  /// Sets [key] of [configMap] in [namespace] to [content], then rolls [rollout].
  const PatchConfigmapKey({
    required this.namespace,
    required this.configMap,
    required this.key,
    required this.content,
    required this.rollout,
    required this.backupPath,
    required this.rolloutTimeoutSeconds,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory PatchConfigmapKey.fromArguments(Arguments arguments) => PatchConfigmapKey(
    namespace: arguments.text('namespace'),
    configMap: arguments.text('configmap'),
    key: arguments.text('key'),
    content: arguments.text('content'),
    rollout: arguments.text('rollout'),
    backupPath: arguments.text('backup_path'),
    rolloutTimeoutSeconds: arguments.integer('rollout_timeout_seconds'),
    kubectl: Kubectl.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the ConfigMap is in',
    ),
    ArgumentSpec(
      name: 'configmap',
      kind: ArgumentKind.text,
      describes: 'the ConfigMap whose key is set',
    ),
    ArgumentSpec(name: 'key', kind: ArgumentKind.text, describes: 'the key inside it'),
    ArgumentSpec(
      name: 'content',
      kind: ArgumentKind.text,
      describes:
          'what that key holds, written out in full — it replaces whatever is there, and may '
          'carry "$placeholder" where the name servers this machine reaches the internet through '
          'belong',
    ),
    ArgumentSpec(
      name: 'rollout',
      kind: ArgumentKind.text,
      describes:
          'the workload that reads this key, as its kind and its name — it is restarted after the '
          'key changes, because a process that read the key at start-up does not read it again',
    ),
    ArgumentSpec(
      name: 'backup_path',
      kind: ArgumentKind.text,
      describes: 'where the value as it was is written before it is replaced',
    ),
    ArgumentSpec(
      name: 'rollout_timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the workload is given to come back after the key changed',
      required: false,
      defaultValue: 60,
    ),
    Kubectl.argument,
  ];

  /// The text a program row writes where this machine's own name servers belong.
  ///
  /// A program file ships to every installation and nothing rewrites it, so the addresses of ONE
  /// machine cannot stand in it. What stands there instead is this marked slot, and the step fills
  /// it from what the machine says.
  ///
  /// **A slot is not a template.** No expression, no condition and no loop, only a name standing
  /// for one value this run holds.
  static const String placeholder = '<upstream-servers>';

  /// Who may read the file the value as it was is written to.
  ///
  /// The owner alone. A key of a ConfigMap holds whatever the program put there, and a copy every
  /// account on the machine can read would publish it to accounts the object itself never reached.
  static const int backupMode = 0x180;

  /// The namespace the ConfigMap is in.
  final String namespace;

  /// The ConfigMap.
  final String configMap;

  /// The key inside it.
  final String key;

  /// What that key is set to, before any slot in it is filled.
  final String content;

  /// The workload that reads the key, as its kind and its name.
  final String rollout;

  /// Where the value as it was is kept.
  final String backupPath;

  /// How long the workload is given to come back.
  final int rolloutTimeoutSeconds;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? live = await _live(context);
    if (live == null) {
      return CheckResult.blocked(
        'the $configMap ConfigMap in $namespace could not be read — the object has to be there '
        'before one of its keys can be set',
      );
    }
    final String? wanted = await _filled(context, content);
    if (wanted == null) {
      return CheckResult.blocked(
        'the content of $key carries $placeholder and this machine names no name server a pod '
        'could reach, so there is nothing to write there',
      );
    }
    if (live == wanted) {
      return CheckResult.satisfied('$namespace/$configMap.$key holds what this program writes');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.diff(
    '$namespace/$configMap.$key',
    before: await _live(context) ?? '',
    after: await _filled(context, content) ?? '',
  );

  @override
  Future<void> apply(StepContext context) async {
    // What is written is worked out before anything is touched, so a machine that cannot fill the
    // slot leaves no half-finished copy of the value it was about to replace.
    final String? wanted = await _filled(context, content);
    if (wanted == null) {
      throw StateError(
        'the content of $key carries $placeholder and this machine names no name server a pod '
        'could reach',
      );
    }
    final String? live = await _live(context);
    if (live != null) {
      await context.files.write(backupPath, live, mode: backupMode);
      context.log.info('the value as it was is at $backupPath');
    }
    await _write(context, wanted);
  }

  /// The value the key holds, read BEFORE it is replaced.
  ///
  /// Null is the object or the key being unreadable, which is also when there is nothing to put
  /// back. Reading the object at undo time would read what this step wrote, and reading the file the
  /// apply leaves behind would read whatever the last run of this step put there.
  @override
  Future<String?> capture(StepContext context) => _live(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      return;
    }
    await _write(context, captured);
  }

  /// The value the key holds now, or null when it cannot be read.
  Future<String?> _live(StepContext context) async {
    final CommandResult live = await context.shell.run(
      kubectl.observing(<String>[
        '-n',
        namespace,
        'get',
        'configmap',
        configMap,
        '-o',
        'jsonpath={.data.$key}',
      ]),
    );
    return live.ok && live.stdout.trim().isNotEmpty ? live.stdout : null;
  }

  /// Writes [value] into the key and restarts what reads it.
  ///
  /// The restart and the wait are not optional halves of this: without them the value is on the
  /// cluster and the process that reads it is still running with the old one, which is the state
  /// this step exists to leave behind.
  Future<void> _write(StepContext context, String value) async {
    final String patch = jsonEncode(<String, Object>{
      'data': <String, String>{key: value},
    });
    await _mustRun(context, <String>[
      '-n',
      namespace,
      'patch',
      'configmap',
      configMap,
      '--type',
      'merge',
      '-p',
      patch,
    ]);
    await _mustRun(context, <String>['-n', namespace, 'rollout', 'restart', rollout]);
    await _mustRun(context, <String>[
      '-n',
      namespace,
      'rollout',
      'status',
      rollout,
      '--timeout=${rolloutTimeoutSeconds}s',
    ]);
  }

  Future<void> _mustRun(StepContext context, List<String> arguments) async {
    final Command command = kubectl.command(arguments);
    final CommandResult answer = await context.shell.run(command);
    if (!answer.ok) {
      throw CommandFailed(argv: command.argv, exitCode: answer.exitCode, stderr: answer.stderr);
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Filling the slot: the name servers this machine really reaches the internet through.
  //
  // The order of the two sources is the incident this encodes. On a machine running the system
  // resolver, the resolver file names `127.0.0.53`, the local stub — an answer no pod can reach,
  // because a pod's own loopback is not the machine's. So the resolver is asked first for the
  // servers it actually forwards to, and the file is only read when that yields nothing. Loopback
  // goes from BOTH sources, a zone id after `%` is cut, and repeats are dropped.
  // ---------------------------------------------------------------------------------------------

  /// [text] with [placeholder] replaced by this machine's name servers, or null when it names none.
  ///
  /// The addresses stand where the slot was, one after another separated by a space. Text carrying
  /// no slot comes back as it is, without the machine being measured at all.
  static Future<String?> _filled(StepContext context, String text) async {
    if (!text.contains(placeholder)) {
      return text;
    }
    final List<String> found = _usable(await _fromSystemResolver(context));
    final List<String> servers = found.isNotEmpty
        ? found
        : _usable(await _fromResolvConf(context, _resolvConf));
    if (servers.isEmpty) {
      return null;
    }
    return text.replaceAll(placeholder, servers.join(' '));
  }

  /// The file the second source reads.
  static const String _resolvConf = '/etc/resolv.conf';

  /// What the system resolver says it forwards to.
  static Future<List<String>> _fromSystemResolver(StepContext context) async {
    final CommandResult status = await context.shell.run(
      const Command.observing('resolvectl', <String>['status']),
    );
    if (!status.ok) {
      return const <String>[];
    }
    final List<String> found = <String>[];
    for (final String line in status.stdout.split('\n')) {
      for (final String label in _labels) {
        final int at = line.indexOf(label);
        if (at < 0) {
          continue;
        }
        found.addAll(
          line
              .substring(at + label.length)
              .split(RegExp(r'\s+'))
              .where((String value) => value.isNotEmpty),
        );
        break;
      }
    }
    return found;
  }

  /// What the resolver file names.
  static Future<List<String>> _fromResolvConf(StepContext context, String path) async {
    if (!await context.files.exists(path)) {
      return const <String>[];
    }
    final List<String> found = <String>[];
    for (final String line in (await context.files.read(path)).split('\n')) {
      final String trimmed = line.trim();
      if (!trimmed.startsWith('nameserver')) {
        continue;
      }
      found.addAll(
        trimmed
            .substring('nameserver'.length)
            .split(RegExp(r'\s+'))
            .where((String value) => value.isNotEmpty),
      );
    }
    return found;
  }

  /// [found] with the zone ids cut, the local stubs dropped and the repeats removed.
  static List<String> _usable(List<String> found) {
    final List<String> usable = <String>[];
    for (final String address in found) {
      final String withoutZone = address.split('%').first.trim();
      if (withoutZone.isEmpty || _isLoopback(withoutZone) || usable.contains(withoutZone)) {
        continue;
      }
      usable.add(withoutZone);
    }
    return usable;
  }

  /// Whether [address] is the machine's own loopback, which a pod cannot reach.
  static bool _isLoopback(String address) =>
      address.startsWith('127.') || address == '::1' || address == '0:0:0:0:0:0:0:1';

  /// The two labels the system resolver writes its forwarders behind.
  ///
  /// The list of them and the one currently in use, in that order — a line matches one label and the
  /// search for the other stops there, so the list is never read twice out of the same line.
  static const List<String> _labels = <String>['DNS Servers:', 'Current DNS Server:'];
}
