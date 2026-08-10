import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// The four mechanisms the cluster's own networking rests on, and the addon patch beside them.
void main() {
  const StepName under = StepName('under_test');
  const String argsPath = microk8sKubeProxyArguments;
  const String liveCorefile =
      'microk8s kubectl -n kube-system get configmap coredns -o jsonpath={.data.Corefile}';
  const String entrypointArgument = '--entryPoints.postgres.address=:5432/tcp';
  const String felixBackend =
      'microk8s kubectl get felixconfiguration/default -o jsonpath={.spec.iptablesBackend}';

  group('the service proxy on the modern packet-filtering backend', () {
    // The row `deploy-cluster` writes: kube-proxy paints its rules where the network agent does.
    // Set after an addon is up the old rules already exist, and nothing here removes them — this
    // row prevents them rather than cleaning them up.
    const SetProcessFlag proxyMode = SetProcessFlag(
      argsPath: argsPath,
      flag: '--proxy-mode',
      value: 'nftables',
    );

    test('the arguments carry the flag exactly once', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[argsPath] = '--proxy-mode=ipvs\n';

      const SetProcessFlag step = proxyMode;
      final StepContext context = machine.contextFor(under);
      await step.apply(context);

      final Iterable<String> flags = machine.files.contents[argsPath]!
          .split('\n')
          .where((String each) => each.startsWith('--proxy-mode='));
      expect(flags, <String>['--proxy-mode=nftables']);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('a second run neither appends nor restarts anything', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[argsPath] = '--proxy-mode=nftables\n';

      const SetProcessFlag step = proxyMode;
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Satisfied>());
      expect(machine.files.written, isEmpty);
      expect(machine.changing, isEmpty);
    });

    test('a machine with no such file is refused rather than given one', () async {
      final CheckResult answer = await proxyMode.check(ClusterMachine().contextFor(under));
      expect((answer as Blocked).reason, contains(argsPath));
    });

    test('the value as it stood is what an undo puts back, not the line taken out', () async {
      // Several rows write this one file, so a row that removed its own line at undo time would
      // leave the machine with no backend where it had one before the run.
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[argsPath] = '--proxy-mode=ipvs\n';
      final StepContext context = machine.contextFor(under);

      final String? captured = await proxyMode.capture(context);
      await proxyMode.apply(context);
      await proxyMode.undo(context, captured);
      expect(machine.files.contents[argsPath], '--proxy-mode=ipvs\n');
    });
  });

  group("the machine's real name servers", () {
    test(
      'the system resolver is asked first, and the resolver file only when it says nothing',
      () async {
        // Reading the file first answers with the local stub, which no pod can reach — and the
        // detection is then finished with a value that does not work.
        final ClusterMachine machine = ClusterMachine();
        machine.shell.answers(
          'resolvectl status',
          'Global\n  DNS Servers: 185.12.64.1 185.12.64.2\n  DNSSEC setting: no\n',
        );
        machine.files.contents['/etc/resolv.conf'] = 'nameserver 127.0.0.53\n';

        expect(await DetectHostUpstreamResolvers.detect(machine.contextFor(under)), <String>[
          '185.12.64.1',
          '185.12.64.2',
        ]);
      },
    );

    test('the local stub is dropped from BOTH sources', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers('resolvectl status', 'Global\n  DNS Servers: 127.0.0.53\n');
      machine.files.contents['/etc/resolv.conf'] = 'nameserver 127.0.0.53\nnameserver 9.9.9.9\n';

      expect(await DetectHostUpstreamResolvers.detect(machine.contextFor(under)), <String>[
        '9.9.9.9',
      ]);
    });

    test('an address carrying the interface it is valid on comes back without it', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers('resolvectl status', '  DNS Servers: fe80::1%eth0\n');
      expect(await DetectHostUpstreamResolvers.detect(machine.contextFor(under)), <String>[
        'fe80::1',
      ]);
    });

    test('the same address named twice is named once', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers(
        'resolvectl status',
        '  DNS Servers: 185.12.64.1 185.12.64.2\n  Current DNS Server: 185.12.64.1\n',
      );
      expect(await DetectHostUpstreamResolvers.detect(machine.contextFor(under)), <String>[
        '185.12.64.1',
        '185.12.64.2',
      ]);
    });

    test('a machine naming nothing a pod could reach is refused', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers('resolvectl status', '  DNS Servers: 127.0.0.53\n');
      machine.files.contents['/etc/resolv.conf'] = 'nameserver 127.0.0.53\n';

      const DetectHostUpstreamResolvers step = DetectHostUpstreamResolvers(
        resolvConf: '/etc/resolv.conf',
      );
      expect(await step.check(machine.contextFor(under)), isA<Blocked>());
    });
  });

  group("a key of an object's data, and the cluster's own name service through it", () {
    const String backupPath = '/var/snap/microk8s/current/args/coredns-corefile.before';

    /// The row `deploy-cluster` writes, with the slot the program cannot fill still in it.
    PatchConfigmapKey rowWriting(String content) => PatchConfigmapKey(
      namespace: 'kube-system',
      configMap: 'coredns',
      key: 'Corefile',
      content: content,
      rollout: 'deployment/coredns',
      backupPath: backupPath,
      rolloutTimeoutSeconds: 60,
    );

    final PatchConfigmapKey nameService = rowWriting(
      corefile(<String>[DetectHostUpstreamResolvers.placeholder]),
    );

    ClusterMachine withCorefile(String held) {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('resolvectl status', '  DNS Servers: ${upstreamResolvers.join(' ')}\n')
        ..answers(liveCorefile, held);
      return machine;
    }

    test(
      'the key is set to the whole value the program holds, and what reads it is rolled',
      () async {
        final ClusterMachine machine = withCorefile('.:53 {\n    forward . 127.0.0.53\n}\n');
        machine.shell.changes(
          'microk8s kubectl -n kube-system patch configmap coredns --type merge -p '
          '{"data":{"Corefile":${_json(corefile(upstreamResolvers))}}}',
          () => machine.shell.answers(liveCorefile, corefile(upstreamResolvers)),
        );

        final StepContext context = machine.contextFor(under);
        expect(await nameService.check(context), isA<Ready>());
        await nameService.apply(context);
        expect(await nameService.check(context), isA<Satisfied>());
        expect(
          machine.changing.join('\n'),
          contains('rollout restart deployment/coredns'),
          reason: 'a key changed and not rolled is a change nothing is running yet',
        );
        expect(machine.changing.join('\n'), contains('rollout status deployment/coredns'));
      },
    );

    test(
      'the marked slot is filled from what the machine really reaches the internet through',
      () async {
        final ClusterMachine machine = withCorefile(corefile(upstreamResolvers));
        expect(
          await nameService.check(machine.contextFor(under)),
          isA<Satisfied>(),
          reason: 'the slot stands for exactly the addresses this machine names',
        );
      },
    );

    test('the copy taken before the change is what an undo puts back', () async {
      const String before = '.:53 {\n    forward . 127.0.0.53\n}\n';
      final ClusterMachine machine = withCorefile(before);
      final StepContext context = machine.contextFor(under);
      final String? captured = await nameService.capture(context);
      await nameService.apply(context);
      expect(machine.files.contents[backupPath], before);

      machine.shell.answers(liveCorefile, corefile(upstreamResolvers));
      await nameService.undo(context, captured);
      expect(
        machine.changing.join('\n'),
        contains('{"data":{"Corefile":${_json(before)}}}'),
        reason: 'the value read before the change is what goes back, not the file on disk',
      );
    });

    test('a value that differs anywhere at all is work to do', () async {
      final ClusterMachine machine = withCorefile(corefile(upstreamResolvers));
      final PatchConfigmapKey overTcp = rowWriting(
        corefile(<String>[DetectHostUpstreamResolvers.placeholder], forceTcp: true),
      );
      expect(
        await overTcp.check(machine.contextFor(under)),
        isA<Ready>(),
        reason: 'the same forwarders over TCP is a different value of the same key',
      );
    });

    test('a value with no slot in it is written exactly as the program holds it', () async {
      final ClusterMachine machine = withCorefile(corefile(<String>['9.9.9.9']));
      // The machine names other servers, and nothing measures it: there is no slot to fill.
      machine.shell.fails('resolvectl status');
      expect(
        await rowWriting(corefile(<String>['9.9.9.9'])).check(machine.contextFor(under)),
        isA<Satisfied>(),
      );
    });

    test('a machine that cannot fill the slot is refused, not written to', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('resolvectl status', '  DNS Servers: 127.0.0.53\n')
        ..answers(liveCorefile, '.:53 {\n}\n');
      machine.files.contents['/etc/resolv.conf'] = 'nameserver 127.0.0.53\n';

      expect(await nameService.check(machine.contextFor(under)), isA<Blocked>());
      expect(machine.changing, isEmpty);
      expect(machine.files.written, isEmpty);
    });

    test('a machine whose object is not there yet is refused, not patched', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('resolvectl status', '  DNS Servers: 185.12.64.1\n')
        ..fails(liveCorefile);
      expect(await nameService.check(machine.contextFor(under)), isA<Blocked>());
      expect(machine.changing, isEmpty);
    });
  });

  group("the network agent's packet-filtering backend", () {
    test('an agent that works it out for itself is left alone', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(felixBackend, 'Auto\n');
      const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('an empty answer is the same thing', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(felixBackend, '');
      const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('an agent pinned against the machine is repinned, and no rule is touched', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(felixBackend, 'Legacy\n')
        ..answers('readlink -f /etc/alternatives/iptables', '/usr/sbin/xtables-nft-multi\n')
        ..changes(
          'microk8s kubectl patch felixconfiguration/default --type merge -p '
          '{"spec":{"iptablesBackend":"NFT"}}',
          () => machine.shell.answers(felixBackend, 'NFT\n'),
        );

      const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120);
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(
        machine.changing.join('\n'),
        isNot(anyOf(contains('iptables -F'), contains('iptables-legacy'))),
        reason: 'flushing the other backend wiped the ingress translation rules once',
      );
    });

    test('a machine this cannot be read from is reported as being on the modern backend', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.fails('readlink -f /etc/alternatives/iptables')
        ..shell.fails('readlink -f /usr/sbin/iptables');
      expect(
        await DetectHostIptablesBackend.detect(machine.contextFor(under)),
        DetectHostIptablesBackend.nft,
      );
    });

    test('a machine set to the older one is reported as it is', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers(
          'readlink -f /etc/alternatives/iptables',
          '/usr/sbin/xtables-legacy-multi\n',
        );
      expect(
        await DetectHostIptablesBackend.detect(machine.contextFor(under)),
        DetectHostIptablesBackend.legacy,
      );
    });
  });

  group('arguments and ports on a container, and the ingress controller through them', () {
    PatchContainerArgumentsAndPorts asking({
      List<String> arguments = const <String>[crossNamespaceArgument],
      List<String> ports = const <String>[],
      String container = 'traefik',
    }) => PatchContainerArgumentsAndPorts(
      namespace: 'ingress',
      kind: 'daemonset',
      name: 'traefik',
      container: container,
      containerArguments: arguments,
      ports: ports,
      rolloutTimeoutSeconds: 90,
    );

    /// A machine whose controller is declared with [declared] and whose pods are [pods].
    ClusterMachine withController({
      required List<String> declared,
      Map<String, int> declaredPorts = const <String, int>{},
      Map<String, PodState> pods = const <String, PodState>{},
      String container = 'traefik',
    }) {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(
          traefikDaemonSet,
          workloadJson(container: container, arguments: declared, ports: declaredPorts),
        )
        ..answers(traefikPods, podsJson(pods, container: container));
      return machine;
    }

    test('a controller that is not there is a skip and not a failure', () async {
      final ClusterMachine machine = ClusterMachine()..shell.fails(traefikDaemonSet);
      expect(await asking().check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a workload with no container of that name is refused, and says what it has', () async {
      final ClusterMachine machine = withController(
        declared: const <String>[],
        container: 'controller',
      );
      final CheckResult answer = await asking().check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('controller'));
      expect(machine.changing, isEmpty);
    });

    test('the argument is added once, and a second run adds nothing', () async {
      final ClusterMachine machine = withController(
        declared: const <String>['--entrypoints.web.address=:8000/tcp'],
        pods: const <String, PodState>{
          'traefik-old': PodState(
            phase: 'Running',
            arguments: <String>['--entrypoints.web.address=:8000/tcp'],
          ),
        },
      );
      machine.shell.changes('microk8s kubectl -n ingress patch daemonset traefik --type=json -p '
          '[{"op":"add","path":"/spec/template/spec/containers/0/args/-",'
          '"value":"$crossNamespaceArgument"}]', () {
        machine.shell
          ..answers(
            traefikDaemonSet,
            workloadJson(
              container: 'traefik',
              arguments: const <String>[
                '--entrypoints.web.address=:8000/tcp',
                crossNamespaceArgument,
              ],
            ),
          )
          ..answers(
            traefikPods,
            podsJson(const <String, PodState>{
              'traefik-new': PodState(
                phase: 'Running',
                arguments: <String>['--entrypoints.web.address=:8000/tcp', crossNamespaceArgument],
              ),
            }),
          );
      });

      final StepContext context = machine.contextFor(under);
      expect(await asking().check(context), isA<Ready>());
      await asking().apply(context);
      expect(await asking().check(context), isA<Satisfied>());
      final int done = machine.changing.length;
      expect(await asking().check(context), isA<Satisfied>());
      expect(
        machine.changing,
        hasLength(done),
        reason: 'a re-run duplicates the argument otherwise',
      );
    });

    test('a port produces BOTH the argument and the published port, in one patch', () async {
      final ClusterMachine machine = withController(
        declared: const <String>[crossNamespaceArgument],
        pods: const <String, PodState>{
          'traefik-old': PodState(phase: 'Running', arguments: <String>[crossNamespaceArgument]),
        },
      );

      final StepContext context = machine.contextFor(under);
      final PatchContainerArgumentsAndPorts step = asking(
        arguments: const <String>[crossNamespaceArgument, entrypointArgument],
        ports: const <String>['postgres:5432'],
      );
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      final String patch = machine.changing.first;
      expect(patch, contains(entrypointArgument));
      expect(patch, contains('"hostPort":5432'));
      expect(patch, contains('"containerPort":5432'));
      expect(patch, contains('"name":"postgres"'));
    });

    test('an argument that is there but a port that is not gets only the port', () async {
      // The argument alone gives an address nothing can connect to.
      final ClusterMachine machine = withController(
        declared: const <String>[crossNamespaceArgument, entrypointArgument],
        pods: const <String, PodState>{
          'traefik-old': PodState(
            phase: 'Running',
            arguments: <String>[crossNamespaceArgument, entrypointArgument],
          ),
        },
      );

      await asking(
        arguments: const <String>[crossNamespaceArgument, entrypointArgument],
        ports: const <String>['postgres:5432'],
      ).apply(machine.contextFor(under));

      final String patch = machine.changing.first;
      expect(patch, contains('"hostPort":5432'));
      expect(
        patch,
        isNot(contains('args/-')),
        reason: 'the argument is already there and adding it again would duplicate it',
      );
    });

    test('a port written wrong is warned about and left out', () async {
      final ClusterMachine machine = withController(
        declared: const <String>[crossNamespaceArgument],
        pods: const <String, PodState>{
          'traefik-old': PodState(phase: 'Running', arguments: <String>[crossNamespaceArgument]),
        },
      );
      expect(
        await asking(ports: const <String>['postgres']).check(machine.contextFor(under)),
        isA<Satisfied>(),
      );
      expect(machine.said.join('\n'), contains('is not a port'));
    });

    test('asking for nothing is a step with nothing to do', () async {
      expect(
        await asking(arguments: const <String>[]).check(ClusterMachine().contextFor(under)),
        isA<Satisfied>(),
      );
    });

    test('a pod still serving with what it was started with is replaced, stuck ones first', () async {
      // Patching the declaration reports success and does not reach the pod: on one machine the
      // replacement cannot be created while the old pod holds the machine's ports. Reversed, the
      // replacement lands while a stuck pod still claims them and the whole deadlock happens again.
      final ClusterMachine machine = withController(
        declared: const <String>[crossNamespaceArgument],
        pods: const <String, PodState>{
          'traefik-wedged': PodState(phase: 'Pending'),
          'traefik-old': PodState(
            phase: 'Running',
            arguments: <String>['--entrypoints.web.address=:8000/tcp'],
          ),
        },
      );

      final StepContext context = machine.contextFor(under);
      expect(
        await asking().check(context),
        isA<Ready>(),
        reason: 'the declaration carries it and what is serving does not',
      );
      await asking().apply(context);

      expect(machine.changing, <String>[
        'microk8s kubectl -n ingress delete pod traefik-wedged --grace-period=0 --force',
        'microk8s kubectl -n ingress delete pod traefik-old --grace-period=10',
        'microk8s kubectl -n ingress rollout status daemonset/traefik --timeout=90s',
      ]);
    });

    test('a pod running with the same value under a different port is replaced too', () async {
      final ClusterMachine machine = withController(
        declared: const <String>[crossNamespaceArgument, entrypointArgument],
        declaredPorts: const <String, int>{'postgres': 5432},
        pods: const <String, PodState>{
          'traefik-old': PodState(
            phase: 'Running',
            arguments: <String>[crossNamespaceArgument, entrypointArgument],
          ),
        },
      );
      final PatchContainerArgumentsAndPorts step = asking(
        arguments: const <String>[crossNamespaceArgument, entrypointArgument],
        ports: const <String>['postgres:5432'],
      );
      expect(
        await step.check(machine.contextFor(under)),
        isA<Ready>(),
        reason: 'the declaration publishes the port and the running pod does not',
      );
    });

    test('no pod at all is a skip, not a failure', () async {
      final ClusterMachine machine = withController(
        declared: const <String>[crossNamespaceArgument],
      );
      expect(await asking().check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test(
      'what was already there is left alone, and only what this run added comes back out',
      () async {
        final ClusterMachine machine = withController(
          declared: const <String>[crossNamespaceArgument],
          pods: const <String, PodState>{
            'traefik-old': PodState(phase: 'Running', arguments: <String>[crossNamespaceArgument]),
          },
        );
        final PatchContainerArgumentsAndPorts step = asking(
          arguments: const <String>[crossNamespaceArgument, entrypointArgument],
        );
        final StepContext context = machine.contextFor(under);

        final ContainerAdditions added = await step.capture(context);
        expect(
          added.arguments,
          <String>[entrypointArgument],
          reason:
              'an argument the controller carried before this ran belongs to whoever put it there',
        );

        machine.shell.answers(
          traefikDaemonSet,
          workloadJson(
            container: 'traefik',
            arguments: const <String>[crossNamespaceArgument, entrypointArgument],
          ),
        );
        await step.undo(context, added);
        expect(
          machine.changing.first,
          contains('{"op":"remove","path":"/spec/template/spec/containers/0/args/1"}'),
        );
      },
    );
  });
}

/// The text of [value] as it appears inside a patch, so a test can name the command exactly.
String _json(String value) {
  final StringBuffer written = StringBuffer('"');
  for (final int unit in value.runes) {
    written.write(switch (unit) {
      0x22 => r'\"',
      0x5C => r'\\',
      0x0A => r'\n',
      _ => String.fromCharCode(unit),
    });
  }
  return (written..write('"')).toString();
}
