import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

/// The one step that puts a manifest of the checkout on the cluster.
///
/// What decides it is where the answer comes from. The check asks the API SERVER whether the
/// cluster already holds what the file says, instead of reading the objects and comparing them
/// here — a comparison of our own would be a second opinion about a question the server answers
/// exactly, and it would be wrong in the cases nobody thinks of: a default the server fills in, a
/// field it normalises, a list it reorders.
void main() {
  const KubernetesObject step = KubernetesObject(
    repository: '/srv/hostyour-cloud',
    manifest: 'bootstrap/vault/certificate.yaml',
  );
  const String path = '/srv/hostyour-cloud/bootstrap/vault/certificate.yaml';

  StepContext contextOn(FakeShell shell, {bool present = true}) => StepContext(
    shell: shell,
    files: FakeFiles(present ? <String, String>{path: 'kind: Certificate\n'} : <String, String>{}),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SaysNothing(),
    step: const StepName('kubernetes_object'),
    arguments: Arguments.none,
    facts: Facts.none,
  );

  /// A shell whose `kubectl diff` exits with [exitCode].
  FakeShell diffing(int exitCode) => FakeShell(<String, CommandResult>{
    'kubectl diff --filename $path': CommandResult(
      exitCode: exitCode,
      stdout: '',
      stderr: exitCode > 1 ? 'the server could not be reached' : '',
      elapsed: Duration.zero,
    ),
  });

  group('the check', () {
    test('no difference is what it is finished against', () async {
      expect(await step.check(contextOn(diffing(0))), isA<Satisfied>());
    });

    test('a difference is work', () async {
      expect(await step.check(contextOn(diffing(1))), isA<Ready>());
    });

    test('a failure to ASK is not the same as work to do', () async {
      // The distinction the exit codes carry: one means "they differ", anything above it means the
      // question was never answered. Reading the second as the first applies a manifest against a
      // cluster nobody could measure.
      expect(await step.check(contextOn(diffing(2))), isA<Blocked>());
    });

    test('a manifest the checkout does not carry is blocked and named', () async {
      final CheckResult result = await step.check(contextOn(diffing(1), present: false));
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('bootstrap/vault/certificate.yaml'));
    });

    test('a missing manifest is not asked about', () async {
      // Asking the cluster about a file that is not there gets an answer about the file rather than
      // about the cluster, and that answer reads exactly like a difference.
      final FakeShell shell = diffing(1);
      await step.check(contextOn(shell, present: false));
      expect(shell.commands, isEmpty);
    });
  });

  test('the apply sends the file and not the objects in it', () async {
    // Declarative on purpose: the server works out what changes. A step that created objects would
    // fail the second time on everything that already exists.
    final FakeShell shell = diffing(1);
    await step.apply(contextOn(shell));
    expect(shell.commands.single.argv, <String>['kubectl', 'apply', '--filename', path]);
  });

  test('a refused apply is a failure and not a shrug', () async {
    final FakeShell shell = FakeShell(<String, CommandResult>{
      'kubectl apply --filename $path': const CommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'no matches for kind "Certificate"',
        elapsed: Duration.zero,
      ),
    });
    await expectLater(step.apply(contextOn(shell)), throwsA(isA<CommandFailed>()));
  });

  test('the undo removes what the file names, by reading the same file', () async {
    // By the file and not by kind and name: a manifest holding several objects would otherwise need
    // this step to parse it, and the parse would drift from the file the day somebody adds a
    // document to it.
    // False is what the capture answers for a cluster that held none of these objects, which is the
    // only case where taking the run back means deleting them. It is passed rather than captured
    // here so the single command below is the delete and not a `kubectl get` in front of it.
    final FakeShell shell = diffing(0);
    await step.undo(contextOn(shell), false);
    expect(shell.commands.single.argv, <String>[
      'kubectl',
      'delete',
      '--filename',
      path,
      '--ignore-not-found',
    ]);
  });
}

/// A log for a test that has to build a context and has nothing to say in it.
final class _SaysNothing implements Logger {
  const _SaysNothing();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
