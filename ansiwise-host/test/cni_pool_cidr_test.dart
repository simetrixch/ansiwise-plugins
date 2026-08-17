import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The pod range stamped into the network manifest, and every way that stamp was found to converge
/// to a wrong-looking right state.
void main() {
  const StepName under = StepName('under_test');

  // The whole path, the way a program row states it. Where the manifest stands is a fact of
  // whatever installed the cluster, so this package composes none.
  const String manifestPath = '/var/lib/cni-network/cni.yaml';
  const String podCidr = '10.244.0.0/16';

  /// `0600` — what a program row states for an argument file a privileged service reads.
  const int fileMode = 0x180;

  /// The manifest as it reads once a range has been stamped into it.
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
      '            - name: ${StampCalicoPoolCidrInCniManifest.variable}\n'
      '              value: "$cidr"\n';

  const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
    podCidr: podCidr,
    manifestPath: manifestPath,
    fileMode: fileMode,
  );

  group('the stamp into the network manifest', () {
    test('the value on the line FOLLOWING the variable is what changes', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(machine.files.contents[manifestPath], contains('value: "$podCidr"'));
      expect(machine.files.contents[manifestPath], isNot(contains('10.1.0.0/16')));
      expect(await step.check(context), isA<Satisfied>());
    });

    test('the value of another variable in the same manifest is untouched', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');
      await step.apply(machine.contextFor(under));
      expect(machine.files.contents[manifestPath], contains('value: "Never"'));
    });

    test('the manifest is written with the permissions the row states', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');
      await step.apply(machine.contextFor(under));
      expect(machine.files.modes[manifestPath], fileMode);
    });

    test('a manifest carrying no such variable is refused rather than reported as done', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[manifestPath] = 'kind: DaemonSet\nspec: {}\n';

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains(StampCalicoPoolCidrInCniManifest.variable));
    });

    test('a machine with no manifest at all is refused, not passed over', () async {
      expect(await step.check(HostMachine().contextFor(under)), isA<Blocked>());
    });

    test('a rewrite that quietly did nothing fails rather than reporting success', () async {
      // The failure an exit code cannot see: the write ran, returned zero and changed nothing.
      final HostMachine machine = HostMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');

      await expectLater(
        step.apply(
          StepContext(
            shell: machine.shell,
            files: _SwallowingFiles(machine.files),
            http: FakeHttp(),
            clock: machine.clock,
            entropy: FakeEntropy(),
            log: _SilentLog(machine.said),
            step: under,
            arguments: Arguments.none,
            facts: Facts.none,
          ),
        ),
        throwsA(isA<CommandFailed>()),
      );
    });

    test('a second run writes nothing and leaves no new copy behind', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');
      final StepContext context = machine.contextFor(under);

      await step.apply(context);
      final int backupsAfterOne = machine.files.contents.keys
          .where((String path) => path.contains('.bak.'))
          .length;
      machine.files.written.clear();

      expect(await step.check(context), isA<Satisfied>());
      await step.apply(context);
      expect(machine.files.written, isEmpty);
      expect(
        machine.files.contents.keys.where((String path) => path.contains('.bak.')).length,
        backupsAfterOne,
      );
    });

    test('the copy taken before the change is what an undo puts back', () async {
      final HostMachine machine = HostMachine();
      final String before = cniManifest(cidr: '10.1.0.0/16');
      machine.files.contents[manifestPath] = before;

      final StepContext context = machine.contextFor(under);
      final String? captured = await step.capture(context);
      await step.apply(context);
      await step.undo(context, captured);
      expect(machine.files.contents[manifestPath], before);
    });
  });
}

/// A file system that answers every read and drops every write.
final class _SwallowingFiles implements Files {
  const _SwallowingFiles(this.inner);

  final Files inner;

  @override
  Future<bool> exists(String path, {bool elevated = false}) => inner.exists(path);

  @override
  Future<String> read(String path, {bool elevated = false}) => inner.read(path);

  @override
  Future<List<String>> list(String path, {bool elevated = false}) => inner.list(path);

  @override
  Future<void> write(
    String path,
    String content, {
    required int mode,
    bool elevated = false,
  }) async {}

  @override
  Future<void> delete(String path, {bool elevated = false}) async {}

  @override
  Future<void> createDirectory(String path, {required int mode, bool elevated = false}) async {}
}

final class _SilentLog implements Logger {
  const _SilentLog(this.said);

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
