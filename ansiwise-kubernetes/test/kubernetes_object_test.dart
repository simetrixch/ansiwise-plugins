import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The one step that puts a manifest of the checkout on the cluster.
///
/// What decides it is where the answer comes from. The check asks the API SERVER whether the
/// cluster already holds what the file says, instead of reading the objects and comparing them
/// here — a comparison of our own would be a second opinion about a question the server answers
/// exactly, and it would be wrong in the cases nobody thinks of: a default the server fills in, a
/// field it normalises, a list it reorders.
void main() {
  const StepName under = StepName('kubernetes_object');
  const KubernetesObject step = KubernetesObject(
    repository: '/srv/checkout',
    manifest: 'manifests/certificate.yaml',
  );
  const String path = '/srv/checkout/manifests/certificate.yaml';

  /// A machine whose `kubectl diff` exits with [exitCode], with the manifest present or not.
  ClusterMachine diffing(int exitCode, {bool present = true}) {
    final ClusterMachine machine = ClusterMachine();
    machine.shell.answer(
      'kubectl diff --filename $path',
      CommandResult(
        exitCode: exitCode,
        stdout: '',
        stderr: exitCode > 1 ? 'the server could not be reached' : '',
        elapsed: Duration.zero,
      ),
    );
    if (present) {
      machine.files.contents[path] = 'kind: Certificate\n';
    }
    return machine;
  }

  group('the check', () {
    test('no difference is what it is finished against', () async {
      expect(await step.check(diffing(0).contextFor(under)), isA<Satisfied>());
    });

    test('a difference is work', () async {
      expect(await step.check(diffing(1).contextFor(under)), isA<Ready>());
    });

    test('a failure to ASK is not the same as work to do', () async {
      // The distinction the exit codes carry: one means "they differ", anything above it means the
      // question was never answered. Reading the second as the first applies a manifest against a
      // cluster nobody could measure.
      expect(await step.check(diffing(2).contextFor(under)), isA<Blocked>());
    });

    test('a manifest the checkout does not carry is blocked and named', () async {
      final CheckResult result = await step.check(diffing(1, present: false).contextFor(under));
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('manifests/certificate.yaml'));
    });

    test('a missing manifest is not asked about', () async {
      // Asking the cluster about a file that is not there gets an answer about the file rather than
      // about the cluster, and that answer reads exactly like a difference.
      final ClusterMachine machine = diffing(1, present: false);
      await step.check(machine.contextFor(under));
      expect(machine.shell.commands, isEmpty);
    });
  });

  test('the apply sends the file and not the objects in it', () async {
    // Declarative on purpose: the server works out what changes. A step that created objects would
    // fail the second time on everything that already exists.
    final ClusterMachine machine = diffing(1);
    await step.apply(machine.contextFor(under));
    expect(machine.shell.commands.single.argv, <String>['kubectl', 'apply', '--filename', path]);
  });

  test('a refused apply is a failure and not a shrug', () async {
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents[path] = 'kind: Certificate\n';
    machine.shell.answer(
      'kubectl apply --filename $path',
      const CommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'no matches for kind "Certificate"',
        elapsed: Duration.zero,
      ),
    );
    await expectLater(step.apply(machine.contextFor(under)), throwsA(isA<CommandFailed>()));
  });

  test('the undo removes what the file names, by reading the same file', () async {
    // By the file and not by kind and name: a manifest holding several objects would otherwise need
    // this step to parse it, and the parse would drift from the file the day somebody adds a
    // document to it.
    // False is what the capture answers for a cluster that held none of these objects, which is the
    // only case where taking the run back means deleting them. It is passed rather than captured
    // here so the single command below is the delete and not a `kubectl get` in front of it.
    final ClusterMachine machine = diffing(0);
    await step.undo(machine.contextFor(under), false);
    expect(machine.shell.commands.single.argv, <String>[
      'kubectl',
      'delete',
      '--filename',
      path,
      '--ignore-not-found',
    ]);
  });

  test('a wrapped client is invoked word for word, in front of every subcommand', () async {
    // The invocation is an argument: a row that names a wrapped client changes one row, not the
    // step. This is the seam an installation whose kubectl sits behind another command uses.
    final KubernetesObject wrapped = KubernetesObject.fromArguments(
      const Arguments(<String, Object>{
        'repository': '/srv/checkout',
        'manifest': 'manifests/certificate.yaml',
        'kubectl': <String>['wrapper', 'kubectl'],
      }),
    );
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents[path] = 'kind: Certificate\n';
    await wrapped.apply(machine.contextFor(under));
    expect(machine.shell.commands.single.argv, <String>[
      'wrapper',
      'kubectl',
      'apply',
      '--filename',
      path,
    ]);
  });

  group('the ownership label', () {
    const KubernetesObject guarded = KubernetesObject(
      repository: '/srv/checkout',
      manifest: 'manifests/certificate.yaml',
      ownerLabel: 'example.com/managed',
      ownerLabelValue: 'true',
    );
    const String getKey = 'kubectl get --filename $path -o json';

    test('a live object WITHOUT the label is refused, never applied over', () async {
      // The planted defect this guards: a name collision handing somebody else's object to this
      // manifest — the apply would rewrite its contents on the strength of a shared name.
      final ClusterMachine machine = diffing(1);
      machine.shell.answers(getKey, '{"kind":"Certificate","metadata":{"name":"c1","labels":{}}}');
      final CheckResult answer = await guarded.check(machine.contextFor(under));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('belongs to something else'));
    });

    test('a live object CARRYING the label is this program\'s to rewrite', () async {
      final ClusterMachine machine = diffing(1);
      machine.shell.answers(
        getKey,
        '{"kind":"Certificate","metadata":{"name":"c1",'
        '"labels":{"example.com/managed":"true"}}}',
      );
      expect(await guarded.check(machine.contextFor(under)), isA<Ready>());
    });

    test('objects the cluster does not hold collide with nothing', () async {
      final ClusterMachine machine = diffing(1);
      machine.shell.fails(getKey, stderr: 'not found');
      expect(await guarded.check(machine.contextFor(under)), isA<Ready>());
    });

    test('a key with no value to hold it against is refused rather than guessed', () async {
      const KubernetesObject halfALabel = KubernetesObject(
        repository: '/srv/checkout',
        manifest: 'manifests/certificate.yaml',
        ownerLabel: 'example.com/managed',
      );
      final ClusterMachine machine = diffing(1);
      machine.shell.answers(getKey, '{"kind":"Certificate","metadata":{"name":"c1","labels":{}}}');
      final CheckResult answer = await halfALabel.check(machine.contextFor(under));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('owner_label_value'));
    });
  });
}
