import 'package:ansiwise_api/ansiwise_api.dart';

/// Hands the cluster over, and stops.
///
/// This is the last step of this program and the one act that makes the platform exist. Nothing in
/// the branch's application tree reaches the cluster except through the single application this
/// applies: it is what creates the projects, the generators and every platform application below
/// them. Skipping it leaves a bare control plane — an identity provider, a dashboard, a reconciler
/// and a secret store, and not one platform application — on a run that otherwise ends green.
///
/// **After this, the question "which file put this object on the cluster" is answered by the
/// reconciler and not by any record here.** Every application it creates names its own path, and
/// from that moment the attribution is its. That boundary is what makes this a recorded step with a
/// verdict of its own rather than a line at the end of a run: it is the last thing a bring-up does
/// and the first thing an operator asks about afterwards.
///
/// **A branch that has lost the manifest is refused with the repair.** The trunk carries one for
/// every stage and the reduction to one stage keeps the one it prunes to, so a branch without it is
/// a branch something removed — and the operator needs the two commands that put it back, not a
/// message that a file is missing.
final class ArgocdRootApp extends IrreversibleStep {
  /// Applies the root application of this run's stage out of the checkout at [repository].
  const ArgocdRootApp({required this.repository, required this.trunk});

  /// Builds the step from what the program gave it.
  factory ArgocdRootApp.fromArguments(Arguments arguments) =>
      ArgocdRootApp(repository: arguments.text('repository'), trunk: arguments.text('trunk'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout this installation was generated into',
    ),
    ArgumentSpec(
      name: 'trunk',
      kind: ArgumentKind.text,
      describes: 'the product branch, which is where a lost manifest is merged back from',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The stage names the manifest, and it is the operator's own answer rather than an argument: the
  /// trunk carries one manifest per stage and the branch keeps the one it was reduced to.
  static const List<String> answers = <String>[stageAnswer];

  /// The name the one stage this installation runs is answered under.
  static const String stageAnswer = 'stage';

  /// The checkout.
  final String repository;

  /// The product branch.
  final String trunk;

  @override
  String get irreversibleReason =>
      'this is where the authority over the cluster moves: from here the reconciler owns every '
      'object of every platform application, and taking the application away again takes all of '
      'them with it';

  /// The manifest this applies, for the stage this run was told about.
  String manifestIn(StepContext context) =>
      '$repository/argocd/${context.answers.text(stageAnswer)}/root-app.yaml';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String manifest = manifestIn(context);
    if (!await context.files.exists(manifest)) {
      return CheckResult.blocked(
        'the handoff is impossible: $manifest is not on this branch. The trunk carries one for '
        'every stage and the reduction to one stage keeps the one it prunes to, so this branch has '
        'lost it — restore it with "git -C $repository merge $trunk" and re-run',
      );
    }

    // The cluster's own answer to what applying this would change, rather than a prediction. It
    // also settles what nothing else can: whether the reconciler's own kinds are on this cluster
    // yet, because a manifest of a kind nobody registered cannot be compared at all.
    final CommandResult difference = await context.shell.run(
      Command.observing('kubectl', <String>['diff', '-f', manifest]),
    );
    switch (difference.exitCode) {
      case 0:
        return CheckResult.satisfied('the cluster already holds what $manifest declares');
      case 1:
        return const CheckResult.ready();
      default:
        return CheckResult.blocked(
          'the cluster could not be asked what $manifest would change: '
          '${difference.stderr.trim().isEmpty ? 'kubectl returned ${difference.exitCode}' : difference.stderr.trim()}',
        );
    }
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      // Verified rather than predicted: the check asked the cluster itself, so what this says would
      // change is what the cluster answered.
      StepPlan.argv(_apply(context), serverVerified: true);

  @override
  Future<void> apply(StepContext context) async {
    final List<String> argv = _apply(context);
    final CommandResult applied = await context.shell.run(
      Command.detailed('kubectl', arguments: argv.sublist(1), timeout: const Duration(seconds: 60)),
    );
    if (!applied.ok) {
      throw CommandFailed(argv: argv, exitCode: applied.exitCode, stderr: applied.stderr);
    }
  }

  List<String> _apply(StepContext context) => <String>[
    'kubectl',
    'apply',
    '-f',
    manifestIn(context),
    '--request-timeout=30s',
  ];
}
