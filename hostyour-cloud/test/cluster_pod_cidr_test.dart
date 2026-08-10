import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// The pod range as this platform stamps it into the network agent's own manifest, and every way
/// that stamp was found to converge to a wrong-looking right state.
void main() {
  const StepName under = StepName('under_test');

  const String manifestPath = StampCalicoPoolCidrInCniManifest.defaultPath;
  group('the stamp into the network manifest', () {
    test('the value on the line FOLLOWING the variable is what changes', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(machine.files.contents[manifestPath], contains('value: "$podCidr"'));
      expect(machine.files.contents[manifestPath], isNot(contains('10.1.0.0/16')));
      expect(await step.check(context), isA<Satisfied>());
    });

    test('the value of another variable on the same manifest is untouched', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      await step.apply(machine.contextFor(under));
      expect(machine.files.contents[manifestPath], contains('value: "Never"'));
    });

    test('a manifest carrying no such variable is refused rather than reported as done', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = 'kind: DaemonSet\nspec: {}\n';

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('CALICO_IPV4POOL_CIDR'));
    });

    test('a rewrite that quietly did nothing fails rather than reporting success', () async {
      // The failure an exit code cannot see: the write ran, returned zero and changed nothing.
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
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
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
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
      final ClusterMachine machine = ClusterMachine();
      final String before = cniManifest(cidr: '10.1.0.0/16');
      machine.files.contents[manifestPath] = before;

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
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
  Future<bool> exists(String path) => inner.exists(path);

  @override
  Future<String> read(String path) => inner.read(path);

  @override
  Future<List<String>> list(String path) => inner.list(path);

  @override
  Future<void> write(String path, String content, {required int mode}) async {}

  @override
  Future<void> delete(String path) async {}

  @override
  Future<void> createDirectory(String path, {required int mode}) async {}
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
