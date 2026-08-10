import 'package:ansiwise_api/ansiwise_api.dart';

import 'kubectl.dart';
import 'kubernetes_object.dart';

/// Applies one manifest of the checkout and announces that its objects are not taken away again.
///
/// **Why this is not [KubernetesObject] with the undo left out.** That step's undo is `kubectl
/// delete --filename`, which removes exactly what the file names — correct for as long as the
/// file's own objects are the whole of what the apply produced. It stops being correct the moment
/// one of them is read by a controller that creates further objects from it: deleting the object
/// the controller watches takes everything the controller made with it, and none of that was
/// applied by this run. An undo that removed more than the step put there is worse than no undo, so
/// this kind announces the point of no return instead — which is what a dry run shows an operator
/// before they reach it.
///
/// **Both sentences an operator reads are the ROW'S.** Why it cannot be taken back, and what to do
/// when the manifest is not in the checkout. This package knows how a manifest is applied and
/// nothing about how the checkout it stands in was produced, so a refusal composed here could only
/// name the path that is missing; the row is where the repair for that particular tree is written.
///
/// **The path may carry ONE slot, and the row says which answer fills it.** A product keeping one
/// manifest per environment, per region or per whatever axis it runs writes that answer's name
/// under `run_answer` and spells the slot with the same name, so the two cannot come apart. A row
/// naming no answer fills nothing, which is the ordinary case rather than a mistake.
///
/// **What still looks like a slot after filling blocks the step.** A misspelled name would
/// otherwise be looked for on disk in angle brackets, and the refusal would report a checkout
/// missing a file nobody ever named.
final class KubernetesObjectIrreversible extends IrreversibleStep {
  /// Applies the manifest at [manifest], under [repository], and does not take it back.
  const KubernetesObjectIrreversible({
    required this.repository,
    required this.manifest,
    required this.reason,
    required this.repair,
    this.runAnswer,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory KubernetesObjectIrreversible.fromArguments(Arguments arguments) =>
      KubernetesObjectIrreversible(
        repository: arguments.text('repository'),
        manifest: arguments.text('manifest'),
        reason: arguments.text('irreversible_reason'),
        repair: arguments.text('repair'),
        runAnswer: arguments.optionalText('run_answer'),
        kubectl: Kubectl.fromArguments(arguments),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout the manifest is read from',
    ),
    ArgumentSpec(
      name: 'manifest',
      kind: ArgumentKind.text,
      describes:
          'the manifest, as a path under that checkout — it may carry the slot spelled with the '
          'name written under run_answer, and nothing else in angle brackets',
    ),
    ArgumentSpec(
      name: 'irreversible_reason',
      kind: ArgumentKind.text,
      describes:
          'what about this apply cannot be taken back, in the words the dry run shows the operator '
          'where it names the point of no return — what is lost, not that no undo was written',
    ),
    ArgumentSpec(
      name: 'repair',
      kind: ArgumentKind.text,
      describes:
          'what an operator does when the manifest is not in the checkout, written out as the act '
          'that puts it back — this package knows nothing about how the checkout was produced, so '
          'a refusal composed here could only name the path',
    ),
    // The ONE axis a product may keep the same manifest along more than once, and the reason it is
    // named rather than known: a cluster has no such axis. A product with three environments keeps
    // one manifest per environment, one with three regions wants the same per region, and one with
    // neither wants a single file — so what the axis is CALLED is the product's, and a name written
    // into this package would make every vendor carry that one.
    //
    // Absent is a first-class case and not a mistake: with nothing here, no slot is filled, and a
    // path still carrying angle brackets is refused rather than looked for.
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name — write '
          '"stage" here and every "<stage>" in the manifest path is filled with this run\'s stage. '
          'Leave it off where the product keeps one manifest for every run',
    ),
    Kubectl.argument,
  ];

  /// How long the client is given to talk to the API server before it gives up.
  ///
  /// An apply that hangs is the shape this guards against: the object goes to a controller that
  /// creates further objects, so an operator watching a command that never returns cannot tell a
  /// slow admission webhook from a handover that already happened.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// How long the command itself is given, which is longer than the request it carries.
  ///
  /// The client's own timeout is what produces a message naming the API server; a shorter outer one
  /// would kill the process first and report nothing about why.
  static const Duration commandTimeout = Duration(seconds: 60);

  /// The checkout.
  final String repository;

  /// The manifest, relative to it, with the run answer's place still marked.
  final String manifest;

  /// Why this cannot be undone, as the row wrote it.
  final String reason;

  /// What puts the manifest back, as the row wrote it.
  final String repair;

  /// The name of the answer whose value fills the slot spelled with that same name, or null where
  /// the product running this step has no such axis.
  final String? runAnswer;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  String get irreversibleReason => reason;

  /// The text that stands where this run's own value for [runAnswer] belongs, or null where there
  /// is no such answer.
  ///
  /// Derived from the name rather than declared beside it, so the slot and the answer cannot come
  /// apart: a row that renames the answer renames the slot in the same act.
  String? get runSlot => runAnswer == null ? null : '<$runAnswer>';

  /// The manifest as the machine holds it, for the run this step was given.
  String pathIn(StepContext context) => '$repository/${_filled(context)}';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String path = pathIn(context);
    if (leftoverSlotIn(path) case final String left) {
      return CheckResult.blocked(
        'the manifest "$manifest" carries $left, and the one slot such a row may write is '
        '${runSlot ?? 'nothing at all, because this row names no run_answer'} — the file would be '
        'looked for under the name as it stands',
      );
    }
    if (!await context.files.exists(path)) {
      // Blocked and not failed: the tree is what it is, and no run can write this file. What the
      // operator needs beyond the path is the act that puts it back, and only the row knows it.
      return CheckResult.blocked('$path is not in this checkout. $repair');
    }

    // The cluster's own answer to what applying this would change, rather than a prediction. It
    // also settles what nothing else can: whether the kinds this manifest names are registered on
    // this cluster yet, because an object of a kind nobody registered cannot be compared at all.
    final CommandResult difference = await context.shell.run(kubectl.observing(_diff(context)));
    // `kubectl diff` exits zero when the cluster already holds what the file says and one when it
    // does not. Anything above one is the command failing, and a failure to measure is not the same
    // as work to do.
    return switch (difference.exitCode) {
      0 => CheckResult.satisfied('the cluster already holds what $path declares'),
      1 => const CheckResult.ready(),
      _ => CheckResult.blocked(
        'the cluster could not be asked what $path would change: '
        '${difference.stderr.trim().isEmpty ? 'the client returned ${difference.exitCode}' : difference.stderr.trim()}',
      ),
    };
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      // Verified rather than predicted: the check asked the cluster itself, so what this says would
      // change is what the cluster answered.
      StepPlan.argv(kubectl.argv(_apply(context)), serverVerified: true);

  @override
  Future<void> apply(StepContext context) async {
    final Command apply = kubectl.command(_apply(context), timeout: commandTimeout);
    final CommandResult applied = await context.shell.run(apply);
    if (!applied.ok) {
      throw CommandFailed(argv: apply.argv, exitCode: applied.exitCode, stderr: applied.stderr);
    }
  }

  /// [manifest] with this run's own value for [runAnswer] where the slot marks it.
  ///
  /// Text carrying no slot, a row naming no answer, and a run that does not hold the answer all
  /// come back unchanged — the last of them so the slot is still visible in the refusal that
  /// reports it, rather than being replaced by an empty string nobody could see.
  String _filled(StepContext context) {
    final String? slot = runSlot;
    final String? answer = runAnswer;
    if (slot == null ||
        answer == null ||
        !manifest.contains(slot) ||
        !context.answers.has(answer)) {
      return manifest;
    }
    return manifest.replaceAll(slot, context.answers.text(answer));
  }

  List<String> _diff(StepContext context) => <String>['diff', '--filename', pathIn(context)];

  List<String> _apply(StepContext context) => <String>[
    'apply',
    '--filename',
    pathIn(context),
    '--request-timeout=${requestTimeout.inSeconds}s',
  ];
}
