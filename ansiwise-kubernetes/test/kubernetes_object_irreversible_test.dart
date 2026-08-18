import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The apply that is not taken back, and the three things the ROW says about it.
///
/// Why it exists beside [KubernetesObject] is one property: the objects of this manifest are read
/// by a controller that creates further objects, so `kubectl delete --filename` would take away
/// what this run never applied. The step therefore announces the point of no return instead — and
/// the reason, the repair, and which answer fills the path's one slot are all the row's, because
/// this package knows how a manifest is applied and nothing about the tree it stands in.
void main() {
  const StepName under = StepName('kubernetes_object_irreversible');
  const String repair =
      'the branch this was cut from carries one for every stage and the reduction to one stage '
      'keeps the one it prunes to, so this branch has lost it — merge that branch back in and '
      're-run';
  const String reason =
      'this is where the authority over the cluster moves: from here a controller owns every '
      'object it created from this one, and taking this object away again takes all of them with it';

  const KubernetesObjectIrreversible step = KubernetesObjectIrreversible(
    repository: '/srv/checkout',
    manifest: 'apps/<stage>/root.yaml',
    reason: reason,
    repair: repair,
    runAnswer: 'stage',
  );
  const String path = '/srv/checkout/apps/dev/root.yaml';
  const Arguments onThisRun = Arguments(<String, Object>{'stage': 'dev'});

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
      machine.files.contents[path] = 'kind: ConfigMap\n';
    }
    return machine;
  }

  group('the path the row writes', () {
    test('carries one slot, and the run fills it under the name the row chose', () {
      // The row cannot say which run this is, so that one value stands as a slot. The slot is
      // derived from the answer's name, so a row that renames the answer renames the slot with it.
      expect(step.runSlot, '<stage>');
      expect(step.pathIn(diffing(1).contextFor(under, Arguments.none, onThisRun)), path);
    });

    test('a row naming no answer fills nothing at all', () {
      // Absent is a first-class case: a product keeping one manifest for every run writes no
      // run_answer, and nothing is substituted into its path.
      const KubernetesObjectIrreversible plain = KubernetesObjectIrreversible(
        repository: '/srv/checkout',
        manifest: 'apps/root.yaml',
        reason: reason,
        repair: repair,
      );
      expect(plain.runSlot, isNull);
      expect(
        plain.pathIn(diffing(1).contextFor(under, Arguments.none, onThisRun)),
        '/srv/checkout/apps/root.yaml',
      );
    });

    test('a slot nothing fills is refused, not looked for', () async {
      // A misspelled slot would otherwise be looked for on disk in angle brackets, and the refusal
      // would report a checkout missing a file nobody ever named.
      const KubernetesObjectIrreversible misspelled = KubernetesObjectIrreversible(
        repository: '/srv/checkout',
        manifest: 'apps/<stag>/root.yaml',
        reason: reason,
        repair: repair,
        runAnswer: 'stage',
      );
      final CheckResult answer = await misspelled.check(
        diffing(1, present: false).contextFor(under, Arguments.none, onThisRun),
      );
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('<stag>'));
      expect(answer.reason, contains('<stage>'));
    });

    test(
      'a slot in a row that names no answer says so rather than naming a slot it has not',
      () async {
        // The refusal has to name what a row MAY write, and a row naming no answer may write nothing
        // — a message quoting a slot this row does not have would send the operator to spell it.
        const KubernetesObjectIrreversible slotted = KubernetesObjectIrreversible(
          repository: '/srv/checkout',
          manifest: 'apps/<stage>/root.yaml',
          reason: reason,
          repair: repair,
        );
        final CheckResult answer = await slotted.check(
          diffing(1, present: false).contextFor(under, Arguments.none, onThisRun),
        );
        expect(answer, isA<Blocked>());
        expect((answer as Blocked).reason, contains('no run_answer'));
      },
    );
  });

  group('the check', () {
    test('no difference is what it is finished against', () async {
      expect(
        await step.check(diffing(0).contextFor(under, Arguments.none, onThisRun)),
        isA<Satisfied>(),
      );
    });

    test('a difference is work', () async {
      expect(
        await step.check(diffing(1).contextFor(under, Arguments.none, onThisRun)),
        isA<Ready>(),
      );
    });

    test('a failure to ASK is not the same as work to do', () async {
      // The distinction the exit codes carry: one means "they differ", anything above it means the
      // question was never answered. Reading the second as the first hands a cluster over on a
      // measurement nobody made, and there is no way back from this one.
      expect(
        await step.check(diffing(2).contextFor(under, Arguments.none, onThisRun)),
        isA<Blocked>(),
      );
    });

    test('a checkout that lost the manifest is refused with the ROW\'s repair', () async {
      // The operator needs the act that puts it back, and this package cannot know it: it knows how
      // a manifest is applied and nothing about how the tree it stands in was produced.
      final CheckResult answer = await step.check(
        diffing(1, present: false).contextFor(under, Arguments.none, onThisRun),
      );
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains(path));
      expect(answer.reason, contains(repair));
    });

    test('a missing manifest is not asked about', () async {
      final ClusterMachine machine = diffing(1, present: false);
      await step.check(machine.contextFor(under, Arguments.none, onThisRun));
      expect(machine.shell.commands, isEmpty);
    });
  });

  test('what cannot be taken back is said in the row\'s words', () {
    // Not "no undo implemented". What the dry run shows an operator at the point of no return is
    // what is lost, and only the row knows what this particular object owns.
    expect(step.irreversibleReason, reason);
  });

  test('the plan says the cluster verified it, because the cluster is what answered', () async {
    final StepPlan plan = await step.plan(diffing(1).contextFor(under, Arguments.none, onThisRun));
    expect(plan.serverVerified, isTrue);
    expect(plan.summary, contains(path));
  });

  test('the apply sends the file, with the client held to a timeout', () async {
    // A hanging apply is the shape this guards against: the object goes to a controller that
    // creates further objects, so an operator watching a command that never returns cannot tell a
    // slow admission webhook from a handover that already happened.
    final ClusterMachine machine = diffing(1);
    await step.apply(machine.contextFor(under, Arguments.none, onThisRun));
    expect(machine.shell.commands.single.argv, <String>[
      'kubectl',
      'apply',
      '--filename',
      path,
      '--request-timeout=${KubernetesObjectIrreversible.requestTimeout.inSeconds}s',
    ]);
    expect(machine.shell.commands.single.timeout, KubernetesObjectIrreversible.commandTimeout);
  });

  test('a refused apply is a failure and not a shrug', () async {
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents[path] = 'kind: ConfigMap\n';
    machine.shell.answer(
      'kubectl apply --filename $path '
      '--request-timeout=${KubernetesObjectIrreversible.requestTimeout.inSeconds}s',
      const CommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'no matches for kind "Application"',
        elapsed: Duration.zero,
      ),
    );
    await expectLater(
      step.apply(machine.contextFor(under, Arguments.none, onThisRun)),
      throwsA(isA<CommandFailed>()),
    );
  });

  test('a wrapped client is invoked word for word, in front of every subcommand', () async {
    final KubernetesObjectIrreversible wrapped = KubernetesObjectIrreversible.fromArguments(
      const Arguments(<String, Object>{
        'repository': '/srv/checkout',
        'manifest': 'apps/<stage>/root.yaml',
        'irreversible_reason': reason,
        'repair': repair,
        'run_answer': 'stage',
        'kubectl': <String>['wrapper', 'kubectl'],
      }),
    );
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents[path] = 'kind: ConfigMap\n';
    await wrapped.apply(machine.contextFor(under, Arguments.none, onThisRun));
    expect(machine.shell.commands.single.argv, <String>[
      'wrapper',
      'kubectl',
      'apply',
      '--filename',
      path,
      '--request-timeout=${KubernetesObjectIrreversible.requestTimeout.inSeconds}s',
    ]);
  });

  test('a row that states no reason cannot be built at all', () {
    // The reason is what the dry run shows at the point of no return, so it is required rather than
    // defaulted: a step that fell back to a sentence this package wrote would be telling the
    // operator something nobody who knows the object said.
    expect(
      () => KubernetesObjectIrreversible.fromArguments(
        const Arguments(<String, Object>{
          'repository': '/srv/checkout',
          'manifest': 'apps/root.yaml',
          'repair': repair,
          'kubectl': <String>['kubectl'],
        }),
      ),
      throwsA(isA<Error>()),
    );
  });
}
