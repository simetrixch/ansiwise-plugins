import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// The four mechanisms the cluster's own networking rests on, and the addon patch beside them.
void main() {
  const StepName under = StepName('under_test');
  const String argsPath = StampKubeProxyClusterCidr.defaultPath;
  const String traefikArgs =
      r'microk8s kubectl -n ingress get daemonset traefik -o '
      r'jsonpath={range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}';
  const String traefikPorts =
      r'microk8s kubectl -n ingress get daemonset traefik -o '
      r'jsonpath={range .spec.template.spec.containers[0].ports[*]}{.hostPort}{"\n"}{end}';
  const String runningTraefik =
      'microk8s kubectl -n ingress get pods -l app.kubernetes.io/name=traefik '
      r'--field-selector=status.phase=Running -o jsonpath={range .items[*]}{.metadata.name}{"\t"}'
      r'{range .spec.containers[0].args[*]}{@}{" "}{end}{"\n"}{end}';
  const String pendingTraefik =
      'microk8s kubectl -n ingress get pods -l app.kubernetes.io/name=traefik '
      r'--field-selector=status.phase=Pending -o jsonpath={range .items[*]}{.metadata.name}{"\t"}'
      r'{range .spec.containers[0].args[*]}{@}{" "}{end}{"\n"}{end}';
  const String liveCorefile =
      'microk8s kubectl -n kube-system get configmap coredns -o jsonpath={.data.Corefile}';
  const String felixBackend =
      'microk8s kubectl get felixconfiguration/default -o jsonpath={.spec.iptablesBackend}';

  group('the service proxy on the modern packet-filtering backend', () {
    test('the arguments carry the flag exactly once', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[argsPath] = '--proxy-mode=ipvs\n';

      const ConfigureKubeProxyNftables step = ConfigureKubeProxyNftables(
        proxyMode: 'nftables',
        argsPath: argsPath,
      );
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

      const ConfigureKubeProxyNftables step = ConfigureKubeProxyNftables(
        proxyMode: 'nftables',
        argsPath: argsPath,
      );
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Satisfied>());
      expect(machine.files.written, isEmpty);
      expect(machine.changing, isEmpty);
    });

    test('a machine with no such file is refused rather than given one', () async {
      const ConfigureKubeProxyNftables step = ConfigureKubeProxyNftables(
        proxyMode: 'nftables',
        argsPath: argsPath,
      );
      final CheckResult answer = await step.check(ClusterMachine().contextFor(under));
      expect((answer as Blocked).reason, contains(argsPath));
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

  group("the cluster's own name service", () {
    const PatchCorednsCorefile plain = PatchCorednsCorefile(
      upstreamServers: <String>[],
      forceTcp: false,
      backupPath: PatchCorednsCorefile.defaultBackupPath,
      rolloutTimeoutSeconds: 60,
    );

    ClusterMachine withCorefile(String corefile) {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('resolvectl status', '  DNS Servers: ${upstreamResolvers.join(' ')}\n')
        ..answers(liveCorefile, corefile);
      return machine;
    }

    test('the whole configuration is replaced from the template here', () async {
      final ClusterMachine machine = withCorefile('.:53 {\n    forward . 127.0.0.53\n}\n');
      machine.shell.changes(
        'microk8s kubectl -n kube-system patch configmap coredns --type merge -p '
        '{"data":{"Corefile":${_json(PatchCorednsCorefile.corefile(upstreamResolvers, forceTcp: false))}}}',
        () {
          machine.shell.answers(
            liveCorefile,
            PatchCorednsCorefile.corefile(upstreamResolvers, forceTcp: false),
          );
        },
      );

      final StepContext context = machine.contextFor(under);
      expect(await plain.check(context), isA<Ready>());
      await plain.apply(context);
      expect(await plain.check(context), isA<Satisfied>());
      expect(machine.shell.ran.join('\n'), contains('rollout restart deployment/coredns'));
    });

    test('the copy taken before the change is what an undo puts back', () async {
      const String before = '.:53 {\n    forward . 127.0.0.53\n}\n';
      final ClusterMachine machine = withCorefile(before);
      await plain.apply(machine.contextFor(under));
      expect(machine.files.contents[PatchCorednsCorefile.defaultBackupPath], before);
    });

    test('the idempotence covers the forwarders AND whether lookups go out over TCP', () async {
      final ClusterMachine machine = withCorefile(
        PatchCorednsCorefile.corefile(upstreamResolvers, forceTcp: false),
      );
      expect(await plain.check(machine.contextFor(under)), isA<Satisfied>());

      const PatchCorednsCorefile overTcp = PatchCorednsCorefile(
        upstreamServers: <String>[],
        forceTcp: true,
        backupPath: PatchCorednsCorefile.defaultBackupPath,
        rolloutTimeoutSeconds: 60,
      );
      expect(
        await overTcp.check(machine.contextFor(under)),
        isA<Ready>(),
        reason: 'the same forwarders over TCP is a different configuration',
      );
      expect(
        PatchCorednsCorefile.corefile(upstreamResolvers, forceTcp: true),
        contains('force_tcp'),
      );
    });

    test('name servers written into the program win over what the machine says', () async {
      final ClusterMachine machine = withCorefile(
        PatchCorednsCorefile.corefile(<String>['9.9.9.9'], forceTcp: false),
      );
      const PatchCorednsCorefile explicit = PatchCorednsCorefile(
        upstreamServers: <String>['9.9.9.9'],
        forceTcp: false,
        backupPath: PatchCorednsCorefile.defaultBackupPath,
        rolloutTimeoutSeconds: 60,
      );
      expect(await explicit.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('a machine whose name addon is not up yet is refused, not patched', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('resolvectl status', '  DNS Servers: 185.12.64.1\n')
        ..fails(liveCorefile);
      expect(await plain.check(machine.contextFor(under)), isA<Blocked>());
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

  group('the ingress controller', () {
    test('a controller that is not there is a skip and not a failure', () async {
      final ClusterMachine machine = ClusterMachine()..shell.fails(traefikArgs);
      const PatchTraefikCrossNamespace step = PatchTraefikCrossNamespace(
        namespace: 'ingress',
        daemonSet: 'traefik',
      );
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('the flag is added once, and a second run adds nothing', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(traefikArgs, '--entrypoints.web.address=:8000/tcp\n')
        ..changes(
          'microk8s kubectl -n ingress patch daemonset traefik --type=json -p '
          '${PatchTraefikCrossNamespace.appendArgument(PatchTraefikCrossNamespace.flag)}',
          () => machine.shell.answers(
            traefikArgs,
            '--entrypoints.web.address=:8000/tcp\n${PatchTraefikCrossNamespace.flag}\n',
          ),
        );

      const PatchTraefikCrossNamespace step = PatchTraefikCrossNamespace(
        namespace: 'ingress',
        daemonSet: 'traefik',
      );
      final StepContext context = machine.contextFor(under);

      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      final int patched = machine.changing.length;
      expect(await step.check(context), isA<Satisfied>());
      expect(
        machine.changing,
        hasLength(patched),
        reason: 'a re-run duplicates the flag otherwise',
      );
    });

    test('a plain-TCP entry point produces BOTH the argument and the published port', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(traefikArgs, '${PatchTraefikCrossNamespace.flag}\n')
        ..answers(traefikPorts, '80\n443\n');

      const PatchTraefikTcpEntrypoint step = PatchTraefikTcpEntrypoint(
        entrypoints: <String>['postgres:5432'],
        namespace: 'ingress',
        daemonSet: 'traefik',
      );
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      final String patch = machine.changing.single;
      expect(patch, contains(PatchTraefikTcpEntrypoint.argumentFor('postgres', 5432)));
      expect(patch, contains('"hostPort":5432'));
      expect(patch, contains('"containerPort":5432'));
    });

    test('an entry point whose argument is there but whose port is not gets the port', () async {
      // The argument alone gives an entry point nothing can connect to.
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(
          traefikArgs,
          '${PatchTraefikCrossNamespace.flag}\n'
          '${PatchTraefikTcpEntrypoint.argumentFor('postgres', 5432)}\n',
        )
        ..answers(traefikPorts, '80\n443\n');

      const PatchTraefikTcpEntrypoint step = PatchTraefikTcpEntrypoint(
        entrypoints: <String>['postgres:5432'],
        namespace: 'ingress',
        daemonSet: 'traefik',
      );
      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      final String patch = machine.changing.single;
      expect(patch, contains('"hostPort":5432'));
      expect(
        patch,
        isNot(contains('"args/-"')),
        reason: 'the argument is already there and adding it again would duplicate it',
      );
    });

    test('an entry point written wrong is warned about and left out', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(traefikArgs, '${PatchTraefikCrossNamespace.flag}\n')
        ..answers(traefikPorts, '80\n');

      const PatchTraefikTcpEntrypoint step = PatchTraefikTcpEntrypoint(
        entrypoints: <String>['postgres'],
        namespace: 'ingress',
        daemonSet: 'traefik',
      );
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.said.join('\n'), contains('is not an entry point'));
    });

    test('an empty list is a step with nothing to do', () async {
      const PatchTraefikTcpEntrypoint step = PatchTraefikTcpEntrypoint(
        entrypoints: <String>[],
        namespace: 'ingress',
        daemonSet: 'traefik',
      );
      expect(await step.check(ClusterMachine().contextFor(under)), isA<Satisfied>());
    });
  });

  group('the running ingress pod, which the declaration does not reach on one machine', () {
    const ForceRollTraefikDaemonset step = ForceRollTraefikDaemonset(
      entrypoints: <String>['postgres:5432'],
      namespace: 'ingress',
      daemonSet: 'traefik',
      rolloutTimeoutSeconds: 90,
    );

    test('a pod carrying everything the declaration requires is left serving', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers(
        runningTraefik,
        'traefik-old\t${PatchTraefikCrossNamespace.flag} '
        '${PatchTraefikTcpEntrypoint.argumentFor('postgres', 5432)} \n',
      );
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('the stuck pods go first with no notice, then the one that is serving', () async {
      // Reversed, the replacement lands while a stuck pod still claims the machine's ports and the
      // whole deadlock happens again.
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(runningTraefik, 'traefik-old\t--entrypoints.web.address=:8000/tcp \n')
        ..answers(pendingTraefik, 'traefik-wedged\t \n');

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(machine.changing, <String>[
        'microk8s kubectl -n ingress delete pod traefik-wedged --grace-period=0 --force',
        'microk8s kubectl -n ingress delete pod traefik-old --grace-period=10',
        'microk8s kubectl -n ingress rollout status daemonset/traefik --timeout=90s',
      ]);
    });

    test('no pod at all is a skip, not a failure', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(runningTraefik, '');
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('it says what the interruption costs, because a restart cannot be taken back', () {
      expect(step.irreversibleReason, contains('443'));
    });
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
