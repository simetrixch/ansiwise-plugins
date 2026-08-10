import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';

import 'composition.dart';

/// A machine in memory, and the context one step of `deploy-cluster` is asked its questions in.
final class ClusterMachine {
  ClusterMachine({FakeShell? shell, FakeFiles? files, FakeClock? clock})
    : shell = shell ?? FakeShell(),
      files = files ?? FakeFiles(),
      clock = clock ?? FakeClock() {
    // The templates travel with the programs of an installation, so a machine one of these steps
    // meets carries them the way it carries its programs. A machine that carries none is what the
    // blocked check is for, and the test that wants that case takes one away.
    this.files.contents.addAll(shippedClusterTemplates());
  }

  final FakeShell shell;
  final FakeFiles files;
  final FakeClock clock;

  /// Everything the log was told, so a test can assert what a step said about what it found.
  final List<String> said = <String>[];

  /// The context [step] is run in, with [arguments] where the step reads any.
  ///
  /// [answers] carries what an operator stated about this installation, and every step gets them
  /// whether or not it reads any: a step reads its answers BY NAME out of the run, so a context
  /// built without them would measure the step against an empty bag rather than an installation.
  StepContext contextFor(
    StepName step, [
    Arguments arguments = Arguments.none,
    Arguments answers = clusterAnswers,
  ]) => StepContext(
    shell: shell,
    files: files,
    http: FakeHttp(),
    clock: clock,
    entropy: FakeEntropy(),
    log: _CollectingLog(said),
    step: step,
    arguments: arguments,
    answers: answers,
    facts: Facts.none,
  );

  /// Every command that changed something, in the order it ran.
  List<String> get changing => <String>[
    for (final Command command in shell.commands)
      if (!command.observes) command.argv.join(' '),
  ];
}

/// The pod range the program file writes, and the one every fixture here is built around.
const String podCidr = '10.244.0.0/16';

/// The domain the cluster in these fixtures answers under.
const String clusterFqdn = 'm1.example.com';

/// What an operator stated about the installation these fixtures describe.
///
/// One master that is its own build plane, so the two answers naming another cluster are empty —
/// which is what a single-cluster installation states, and the case every step here meets.
const Arguments clusterAnswers = Arguments(clusterAnswerValues);

/// The same installation with [changed] answered differently.
///
/// One place, so a test that varies a single answer does not restate the other nine — a second
/// full copy drifts, and then two tests describe two different installations.
Arguments clusterAnswering(Map<String, Object> changed) =>
    Arguments(<String, Object>{...clusterAnswerValues, ...changed});

/// The values [clusterAnswers] and [clusterAnswering] are both built from.
const Map<String, Object> clusterAnswerValues = <String, Object>{
  'fqdn': clusterFqdn,
  'stage': 'dev',
  'role': 'master',
  'master': '',
  'build_plane': '',
  'operator_user': operatorUser,
  'letsencrypt_email': 'certificates@example.com',
  'lan_cidr': '',
  'storage_path': '',
  'storage_directory': '',
};

/// The account that operates the machine in these fixtures.
const String operatorUser = 'operator';

/// Where that account lives.
const String operatorHome = '/home/$operatorUser';

/// The name servers the machine in these fixtures reaches the internet through.
const List<String> upstreamResolvers = <String>['185.12.64.1', '185.12.64.2'];

/// The configuration `deploy-cluster` writes into the cluster's own name service.
///
/// The same text the program file holds, with the slot standing for the machine's own name servers
/// filled by [servers]. It is written out here rather than read from a step, because no step
/// composes it any more: the value belongs to the program, and this is what a converged machine has
/// to be holding for that row to have nothing left to do. The double-run test is what binds the two
/// — let them drift and it reports the row as still having work.
String corefile(List<String> servers, {bool forceTcp = false}) {
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

/// The argument that opens middleware references across namespaces, as the program writes it.
const String crossNamespaceArgument = '--providers.kubernetescrd.allowCrossNamespace=true';

/// The command that reads the ingress controller as the cluster holds it.
const String traefikDaemonSet = 'microk8s kubectl -n ingress get daemonset traefik -o json';

/// The command that reads its pods, found through the selector the controller itself declares.
const String traefikPods =
    'microk8s kubectl -n ingress get pods -l app.kubernetes.io/name=traefik -o json';

/// A workload holding one container called [container], started with [arguments].
///
/// [ports] are the ports it publishes on the machine, each written as its name and the port it
/// answers on — the shape a container declares them in, so a step reads this the way it reads a real
/// one. [selector] is what the workload says its own pods are labelled with.
String workloadJson({
  required String container,
  required List<String> arguments,
  Map<String, int> ports = const <String, int>{},
  Map<String, String> selector = const <String, String>{'app.kubernetes.io/name': 'traefik'},
}) => jsonEncode(<String, Object>{
  'spec': <String, Object>{
    'selector': <String, Object>{'matchLabels': selector},
    'template': <String, Object>{
      'spec': <String, Object>{
        'containers': <Object>[_containerJson(container, arguments, ports)],
      },
    },
  },
});

/// The pods of a workload: one per entry of [pods], in the phase and with the container that entry
/// names.
String podsJson(Map<String, PodState> pods, {String container = 'traefik'}) => jsonEncode(
  <String, Object>{
    'items': <Object>[
      for (final MapEntry<String, PodState> pod in pods.entries)
        <String, Object>{
          'metadata': <String, Object>{'name': pod.key},
          'status': <String, Object>{'phase': pod.value.phase},
          'spec': <String, Object>{
            'containers': <Object>[_containerJson(container, pod.value.arguments, pod.value.ports)],
          },
        },
    ],
  },
);

/// One pod of a fixture: which phase it is in and what its container is running with.
final class PodState {
  /// A pod in [phase], running with [arguments] and publishing [ports].
  const PodState({
    required this.phase,
    this.arguments = const <String>[],
    this.ports = const <String, int>{},
  });

  /// Which phase the pod is in.
  final String phase;

  /// What its container was started with.
  final List<String> arguments;

  /// What it publishes on the machine.
  final Map<String, int> ports;
}

Map<String, Object> _containerJson(
  String container,
  List<String> arguments,
  Map<String, int> ports,
) => <String, Object>{
  'name': container,
  'args': arguments,
  'ports': <Object>[
    for (final MapEntry<String, int> port in ports.entries)
      <String, Object>{
        'name': port.key,
        'containerPort': port.value,
        'hostPort': port.value,
        'protocol': 'TCP',
      },
  ],
};

/// The addons `deploy-cluster` switches on.
const List<String> enabledAddons = <String>[
  'rbac',
  'dns',
  'hostpath-storage',
  'ingress',
  'cert-manager',
  'metrics-server',
];

/// The tools the program pins, with the versions its own file writes.
const Map<String, String> pinnedTools = <String, String>{
  'argocd': 'v3.4.5',
  'vault': 'v2.0.3',
  'yq': 'v4.53.3',
  'jq': 'jq-1.8.2',
  'tailscale': 'v1.98.10',
};

/// What `microk8s status` says on a machine whose addons are the ones the program switches on.
///
/// The addon that must be OFF is written into the section that lists what is off, which is the whole
/// point of it: a reading that searched the output rather than the section between the two headings
/// would find it there and report it as on.
String microk8sStatus() {
  final StringBuffer status = StringBuffer()
    ..writeln('microk8s is running')
    ..writeln('high-availability: no')
    ..writeln('addons:')
    ..writeln('  enabled:');
  for (final String addon in enabledAddons) {
    status.writeln('    $addon${' ' * (21 - addon.length)}# (core) an addon that is on');
  }
  status
    ..writeln('  disabled:')
    ..writeln('    registry             # (core) an addon that is off')
    ..writeln('    gpu                  # (core) an addon that is off');
  return status.toString();
}

/// The network manifest as it reads once the pod range has been stamped into it.
///
/// The value is on the line AFTER the one naming the variable, which is the parser trap the stamp
/// exists for: a rewrite that looked on the same line would match nothing and report success.
String cniManifest({String cidr = podCidr}) =>
    'apiVersion: apps/v1\n'
    'kind: DaemonSet\n'
    'spec:\n'
    '  template:\n'
    '    spec:\n'
    '      containers:\n'
    '        - name: calico-node\n'
    '          env:\n'
    '            - name: CALICO_IPV4POOL_IPIP\n'
    '              value: "Never"\n'
    '            - name: CALICO_IPV4POOL_CIDR\n'
    '              value: "$cidr"\n';

/// The arguments the service proxy is started with once both flags are on it.
String kubeProxyArgs({String cidr = podCidr, String proxyMode = 'nftables'}) =>
    '--proxy-mode=$proxyMode\n--cluster-cidr=$cidr\n';

/// The arguments the API server is started with once it accepts this platform's tokens.
const ConfigureKubeApiserverOidc apiserverOidc = ConfigureKubeApiserverOidc(
  clientId: 'headlamp',
  usernameClaim: 'preferred_username',
  usernamePrefix: 'oidc:',
  groupsClaim: 'groups',
  groupsPrefix: '',
  argsPath: ConfigureKubeApiserverOidc.defaultPath,
);

/// The certificate issuer as the program renders it.
const WriteClusterIssuerManifest clusterIssuer = WriteClusterIssuerManifest(
  templatePath: clusterIssuerTemplate,
  name: 'letsencrypt-prod',
  acmeServer: 'https://acme-v02.api.letsencrypt.org/directory',
  ingressClass: 'public',
  stateDirectory: ConfigureSlaveApiserverOidcTrust.defaultStateDirectory,
);

/// Where each template of the cluster area stands, as a program file names it.
const String connmarkNftTableTemplate = 'ansiwise/templates/connmark-nft-table.tpl';

/// See [connmarkNftTableTemplate].
const String netplanPublicSrcRoutingTemplate = 'ansiwise/templates/netplan-public-src-routing.tpl';

/// See [connmarkNftTableTemplate].
const String publicSrcRoutingScriptTemplate = 'ansiwise/templates/public-src-routing-script.tpl';

/// See [connmarkNftTableTemplate].
const String publicSrcRoutingUnitTemplate = 'ansiwise/templates/public-src-routing-unit.tpl';

/// See [connmarkNftTableTemplate].
const String clusterIssuerTemplate = 'ansiwise/templates/cluster-issuer-manifest.tpl';

/// Every template of the cluster area, keyed by the path a program file names it under.
///
/// READ OFF THE TREE, never pasted in. A test carrying its own copy of the text would measure that
/// copy: the template could name a slot nothing fills, or lose one a step fills, and every
/// assertion here would go on passing while the file that ships is broken. Reading the shipped file
/// is also what makes a wrong path here fail immediately instead of quietly arranging nothing.
Map<String, String> shippedClusterTemplates() => <String, String>{
  for (final String path in <String>[
    connmarkNftTableTemplate,
    netplanPublicSrcRoutingTemplate,
    publicSrcRoutingScriptTemplate,
    publicSrcRoutingUnitTemplate,
    clusterIssuerTemplate,
  ])
    // The KEY is what the program row writes, because that is the path the step asks the
    // fake machine for. The FILE is read from the installation tree, because that is where
    // the text actually stands now — the two differ by the root and nothing else.
    path: File('$installationRoot/$path').readAsStringSync(),
};

/// A machine `deploy-cluster` has already brought all the way up.
///
/// Every one of the program's steps answers that there is nothing to do against this, which is what
/// makes it the fixture the double-run test is written on: a run against it must write nothing and
/// run no command that changes anything.
/// What a fresh Ubuntu carries and `deploy-cluster` only uses, never installs.
///
/// The same list its head gate asks for. A fixture that did not answer for these would be a machine
/// no operator has, and every run against it would stop at the first step.
const List<String> clusterToolsAssumed = <String>[
  'snap',
  'systemctl',
  'ip',
  'nft',
  'netplan',
  'resolvectl',
  'mountpoint',
  'readlink',
  'chown',
  'getent',
  'groups',
  'gpasswd',
];

Future<ClusterMachine> convergedCluster() async {
  final FakeShell shell = FakeShell();
  final FakeFiles files = FakeFiles();

  for (final String command in clusterToolsAssumed) {
    shell.answers('command -v $command', '/usr/bin/$command\n');
  }

  // The snap: installed, on the path, on the pinned channel, and answering that it is running.
  shell
    ..answers('command -v microk8s', '/snap/bin/microk8s\n')
    ..answers(
      'snap list microk8s',
      'Name      Version  Rev   Tracking     Publisher   Notes\n'
          'microk8s  v1.35.0  7964  1.35/stable  canonical   classic\n',
    )
    ..answers('microk8s status --wait-ready --timeout 300', 'microk8s is running\n')
    ..answers('microk8s status', microk8sStatus());

  // The pod network, converged: the live pool, the declaration and the running agent all carry it.
  shell
    ..answers('microk8s kubectl get ippool default-ipv4-ippool -o jsonpath={.spec.cidr}', podCidr)
    ..answers(
      'microk8s kubectl -n kube-system get daemonset calico-node -o '
      'jsonpath={.spec.template.spec.containers[0].env[?(@.name=="CALICO_IPV4POOL_CIDR")].value}',
      podCidr,
    )
    ..answers(
      r'microk8s kubectl -n kube-system get pods -l k8s-app=calico-node -o '
          r'jsonpath={range .items[*]}{.spec.containers[0].env'
          r'[?(@.name=="CALICO_IPV4POOL_CIDR")].value}{"\n"}{end}',
      '$podCidr\n',
    )
    ..answers(
      r'microk8s kubectl get pods --all-namespaces -o '
          r'jsonpath={range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}'
          r'{.spec.hostNetwork}{"\n"}{end}',
      'kube-system calico-node-abc true\n',
    )
    // The agent is on the host's own network and holds no address out of the pool; the controller
    // is on the pod network and holds one inside it.
    ..answers(
      r'microk8s kubectl -n kube-system get pods -o '
          r'jsonpath={range .items[*]}{.metadata.name}{" "}{.spec.hostNetwork}{" "}'
          r'{.status.podIP}{"\n"}{end}',
      'calico-node-abc true 10.1.1.10\n'
          'calico-kube-controllers-def  10.244.0.5\n',
    );

  // The account, the addons, the name service and the network agent.
  shell
    ..answers('getent passwd $operatorUser', '$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n')
    ..answers('groups $operatorUser', '$operatorUser : $operatorUser sudo microk8s\n')
    ..answers('resolvectl status', 'Global\n  DNS Servers: ${upstreamResolvers.join(' ')}\n')
    ..answers(
      'microk8s kubectl -n kube-system get configmap coredns -o jsonpath={.data.Corefile}',
      corefile(upstreamResolvers),
    )
    ..answers(
      'microk8s kubectl get felixconfiguration/default -o jsonpath={.spec.iptablesBackend}',
      'Auto\n',
    );

  // The ingress controller: the declaration carries the argument and so does the pod that is
  // serving. Both are answered, because a machine where only the declaration carried it is exactly
  // the one the step exists to repair.
  const List<String> traefikArguments = <String>[
    '--entrypoints.web.address=:8000/tcp',
    crossNamespaceArgument,
  ];
  shell
    ..answers(traefikDaemonSet, workloadJson(container: 'traefik', arguments: traefikArguments))
    ..answers(
      traefikPods,
      podsJson(<String, PodState>{
        'traefik-abc': const PodState(phase: 'Running', arguments: traefikArguments),
      }),
    );

  // Storage and certificates.
  shell
    ..answers(
      'microk8s kubectl get storageclass -o '
          r'jsonpath={range .items[*]}{.metadata.name}{" "}'
          r'{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}',
      'microk8s-hostpath true\n',
    )
    ..answers(
      'microk8s kubectl -n cert-manager get pods -l app=webhook -o '
          r'jsonpath={range .items[*]}{.status.phase}{"\n"}{end}',
      'Running\n',
    )
    ..answers(
      'microk8s kubectl get clusterissuer letsencrypt-prod -o jsonpath={.metadata.name}',
      'letsencrypt-prod',
    )
    ..answers(
      'microk8s kubectl get clusterissuer letsencrypt-prod -o '
          'jsonpath={.status.conditions[?(@.type=="Ready")].status}',
      'True',
    )
    ..answers('microk8s config', 'apiVersion: v1\nkind: Config\nclusters: []\n');

  // The tools, each answering the version this platform pins for it.
  for (final String tool in <String>['curl', 'unzip', 'jq', 'argocd', 'vault', 'yq', 'tailscale']) {
    shell.answers('command -v $tool', '/usr/local/bin/$tool\n');
  }
  // The one that comes from the package manager is judged on the package manager's own record, and
  // that is a different question from being on the path: a package removed but not purged is still
  // known to dpkg, and a binary somebody copied in by hand is on the path and unknown to it.
  shell.answers(r'dpkg-query -W -f=${Status} jq', 'install ok installed');
  shell
    ..answers('argocd version --client --short', 'argocd: v3.4.5+abcdef1\n')
    ..answers('vault version', 'Vault v2.0.3 (abcdef1), built 2026-01-01\n')
    ..answers('yq --version', 'yq (https://github.com/mikefarah/yq/) version v4.53.3\n')
    ..answers('jq --version', 'jq-1.8.2\n')
    ..answers('tailscale version', '1.98.10\n  tailscale commit: abcdef1\n');

  // The two files below are what a step RENDERS, and both render from the run's answers now — so
  // the fixture asks the same context a test will, rather than keeping a second copy of the text.
  final ClusterMachine machine = ClusterMachine(shell: shell, files: files);
  final StepContext context = machine.contextFor(const StepName('converged_fixture'));

  files.contents.addAll(<String, String>{
    microk8sKubeProxyArguments: kubeProxyArgs(),
    StampCalicoPoolCidrInCniManifest.defaultPath: cniManifest(),
    ConfigureKubeApiserverOidc.defaultPath: ConfigureKubeApiserverOidc.withFlags(
      '',
      apiserverOidc.flagsIn(context),
    ),
    clusterIssuer.path: await clusterIssuer.manifestFor(context),
    '$operatorHome/.bashrc': "alias kubectl='microk8s.kubectl'\nalias helm='microk8s.helm3'\n",
    '$operatorHome/.kube/config': 'apiVersion: v1\nkind: Config\nclusters: []\n',
  });

  return machine;
}

final class _CollectingLog implements Logger {
  const _CollectingLog(this.said);

  final List<String> said;

  @override
  void debug(String message) => said.add(message);

  @override
  void info(String message) => said.add(message);

  @override
  void warn(String message) => said.add(message);

  @override
  void error(String message) => said.add(message);
}
