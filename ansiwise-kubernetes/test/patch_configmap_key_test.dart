import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// A key of an object's data, and the marked slot for the machine's own name servers.
void main() {
  const StepName under = StepName('patch_configmap_key');
  const String backupPath = '/var/backups/coredns-corefile.before';
  const String liveCorefile =
      'kubectl -n kube-system get configmap coredns -o jsonpath={.data.Corefile}';
  const List<String> upstreamResolvers = <String>['185.12.64.1', '185.12.64.2'];

  /// The value the program writes, with the forwarders [servers].
  String corefile(List<String> servers, {bool forceTcp = false}) {
    final String forward = forceTcp
        ? '    forward . ${servers.join(' ')} {\n      force_tcp\n    }'
        : '    forward . ${servers.join(' ')}';
    return '.:53 {\n$forward\n    cache 30\n}\n';
  }

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
    corefile(<String>[PatchConfigmapKey.placeholder]),
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
        'kubectl -n kube-system patch configmap coredns --type merge -p '
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

  test('the system resolver is asked first, and the file only when it says nothing', () async {
    // Reading the file first answers with the local stub, which no pod can reach — and the filling
    // is then finished with a value that does not work.
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers('resolvectl status', '  DNS Servers: 127.0.0.53\n')
      ..answers(liveCorefile, corefile(<String>['9.9.9.9']));
    machine.files.contents['/etc/resolv.conf'] = 'nameserver 127.0.0.53\nnameserver 9.9.9.9\n';

    expect(
      await nameService.check(machine.contextFor(under)),
      isA<Satisfied>(),
      reason: 'the local stub goes from BOTH sources, and the file supplied the usable address',
    );
  });

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
      corefile(<String>[PatchConfigmapKey.placeholder], forceTcp: true),
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
