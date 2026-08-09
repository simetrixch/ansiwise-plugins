import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'detect_host_upstream_resolvers.dart';
import 'stamp_kube_proxy_cluster_cidr.dart';

/// Points the cluster's own name service at name servers a pod can actually reach.
///
/// **The default forwarder is the machine's loopback, and a pod's loopback is its own.** The cluster
/// name service inherits the machine's resolver file, which on the pinned Ubuntu names the local
/// stub — so every lookup for anything outside the cluster goes to an address that answers nothing
/// from inside a pod.
///
/// **The obvious fix is the one that fails.** Turning the name addon off and on again is fragile
/// inside a script from MicroK8s 1.32 onwards. Editing the live configuration works on every
/// version, because the configuration is an ordinary object in the cluster.
///
/// **The whole configuration is replaced, never merged into.** A merge drifts with whatever the
/// addon ships next; a replacement from a template written here is the same on every version and on
/// every machine.
///
/// **A copy of what was there goes to a file first, so an undo has something to put back.** Nothing
/// else keeps one — the object being replaced is the only copy — and an undo that claimed to restore
/// a configuration it never captured would be a promise the step cannot keep.
final class PatchCorednsCorefile extends ReversibleStep {
  /// Replaces the cluster name service's configuration, forwarding to [upstreamServers].
  const PatchCorednsCorefile({
    required this.upstreamServers,
    required this.forceTcp,
    required this.backupPath,
    required this.rolloutTimeoutSeconds,
  });

  /// Builds the step from what the program gave it.
  factory PatchCorednsCorefile.fromArguments(Arguments arguments) => PatchCorednsCorefile(
    upstreamServers: arguments.textList('upstream_servers'),
    forceTcp: arguments.flag('force_tcp'),
    backupPath: arguments.text('backup_path'),
    rolloutTimeoutSeconds: arguments.integer('rollout_timeout_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'upstream_servers',
      kind: ArgumentKind.textList,
      describes:
          'the name servers to forward to, or empty to use the ones this machine reaches the '
          'internet through',
      required: false,
      defaultValue: <String>[],
    ),
    ArgumentSpec(
      name: 'force_tcp',
      kind: ArgumentKind.flag,
      describes:
          'whether lookups go out over TCP, which is what a network that blocks outbound UDP '
          'name traffic needs',
      required: false,
      defaultValue: false,
    ),
    ArgumentSpec(
      name: 'backup_path',
      kind: ArgumentKind.text,
      describes: 'where the configuration as it was is written before it is replaced',
      required: false,
      defaultValue: defaultBackupPath,
    ),
    ArgumentSpec(
      name: 'rollout_timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the name service is given to come back after its configuration changed',
      required: false,
      defaultValue: 60,
    ),
  ];

  /// Where the configuration as it was goes.
  static const String defaultBackupPath = '/var/snap/microk8s/current/args/coredns-corefile.before';

  /// The namespace the cluster name service runs in.
  static const String namespace = 'kube-system';

  /// The object holding its configuration.
  static const String configMap = 'coredns';

  /// The key inside that object.
  static const String key = 'Corefile';

  /// The name servers to forward to, or empty to measure the machine.
  final List<String> upstreamServers;

  /// Whether lookups go out over TCP.
  final bool forceTcp;

  /// Where the configuration as it was is kept.
  final String backupPath;

  /// How long the name service is given to come back.
  final int rolloutTimeoutSeconds;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? live = await liveCorefile(context);
    if (live == null) {
      return const CheckResult.blocked(
        'the $configMap configuration in $namespace could not be read — the name addon has to be up '
        'before its configuration can be changed',
      );
    }
    final List<String> servers = await _servers(context);
    if (servers.isEmpty) {
      return const CheckResult.blocked(
        'no name server was given and this machine names none a pod could reach, so there is nothing '
        'to forward to',
      );
    }
    if (live == corefile(servers, forceTcp: forceTcp)) {
      return CheckResult.satisfied(
        'the cluster forwards to ${servers.join(' ')}'
        '${forceTcp ? ' over TCP' : ''}',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final List<String> servers = await _servers(context);
    return StepPlan.diff(
      '$namespace/$configMap.$key',
      before: await liveCorefile(context) ?? '',
      after: servers.isEmpty ? '' : corefile(servers, forceTcp: forceTcp),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? live = await liveCorefile(context);
    if (live != null) {
      await context.files.write(backupPath, live, mode: StampKubeProxyClusterCidr.mode);
      context.log.info('the configuration as it was is at $backupPath');
    }
    final List<String> servers = await _servers(context);
    context.log.info('forwarding lookups outside the cluster to ${servers.join(' ')}');
    await _replace(context, corefile(servers, forceTcp: forceTcp));
  }

  @override
  Future<void> undo(StepContext context) async {
    if (!await context.files.exists(backupPath)) {
      return;
    }
    await _replace(context, await context.files.read(backupPath));
  }

  /// The configuration this step writes, for [servers].
  ///
  /// The template is written out here rather than derived from what is in the cluster, so that the
  /// same machine comes out the same whichever version of the addon put the configuration there.
  static String corefile(List<String> servers, {required bool forceTcp}) {
    final String forward = forceTcp
        ? '    forward . ${servers.join(' ')} {\n      force_tcp\n    }'
        : '    forward . ${servers.join(' ')}';
    return '.:53 {\n'
        '    errors\n'
        '    health {\n'
        '      lameduck 5s\n'
        '    }\n'
        '    ready\n'
        '    log . {\n'
        '      class error\n'
        '    }\n'
        '    kubernetes cluster.local in-addr.arpa ip6.arpa {\n'
        '      pods insecure\n'
        '      fallthrough in-addr.arpa ip6.arpa\n'
        '    }\n'
        '    prometheus :9153\n'
        '$forward\n'
        '    cache 30\n'
        '    loop\n'
        '    reload\n'
        '    loadbalance\n'
        '}\n';
  }

  /// The configuration the cluster is running on, or null when it cannot be read.
  static Future<String?> liveCorefile(StepContext context) async {
    final CommandResult live = await context.shell.run(
      const Command.observing('microk8s', <String>[
        'kubectl',
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

  /// The name servers this run forwards to: the ones given, or the ones the machine names.
  Future<List<String>> _servers(StepContext context) async =>
      upstreamServers.isNotEmpty ? upstreamServers : DetectHostUpstreamResolvers.detect(context);

  Future<void> _replace(StepContext context, String corefileText) async {
    final String patch = jsonEncode(<String, Object>{
      'data': <String, String>{key: corefileText},
    });
    await _mustRun(context, <String>[
      'microk8s',
      'kubectl',
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
    await _mustRun(context, <String>[
      'microk8s',
      'kubectl',
      '-n',
      namespace,
      'rollout',
      'restart',
      'deployment/$configMap',
    ]);
    await _mustRun(context, <String>[
      'microk8s',
      'kubectl',
      '-n',
      namespace,
      'rollout',
      'status',
      'deployment/$configMap',
      '--timeout=${rolloutTimeoutSeconds}s',
    ]);
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!answer.ok) {
      throw CommandFailed(argv: argv, exitCode: answer.exitCode, stderr: answer.stderr);
    }
  }
}
