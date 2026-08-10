import 'package:ansiwise_api/ansiwise_api.dart';

import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';

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
/// from that moment the attribution is its. That boundary keeps this an IRREVERSIBLE step rather
/// than a `kubernetes_object` row: that row's undo deletes what its manifest names, and deleting
/// the root application takes all of them with it — the point of no return is announced instead.
///
/// **Which manifest is applied is the row's to say, with the stage in a marked slot.** A branch
/// that has lost it is refused with the repair — the two commands that put it back — because the
/// trunk carries one per stage and the reduction to one stage keeps the one it prunes to.
final class ArgocdRootApp extends IrreversibleStep {
  /// Applies the root application of this run's stage out of the checkout at [repository].
  const ArgocdRootApp({
    required this.repository,
    required this.trunk,
    this.manifest = defaultManifest,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory ArgocdRootApp.fromArguments(Arguments arguments) => ArgocdRootApp(
    repository: arguments.text('repository'),
    trunk: arguments.text('trunk'),
    manifest: arguments.text('manifest'),
    kubectl: Kubectl.fromArguments(arguments),
  );

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
    ArgumentSpec(
      name: 'manifest',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: defaultManifest,
      describes:
          'the manifest of the root application, as a path under the checkout, written with '
          '$stageSlot where the stage of this installation belongs',
    ),
    Kubectl.argument,
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The stage fills the manifest's slot, and it is the operator's own answer rather than an
  /// argument: the trunk carries one manifest per stage and the branch keeps the one it was
  /// reduced to.
  static const List<String> answers = <String>[stageAnswer];

  /// The name the one stage this installation runs is answered under.
  static const String stageAnswer = 'stage';

  /// The text a manifest row writes where the stage of this installation belongs.
  ///
  /// Derived from the name the stage is answered under, so the slot and the answer cannot come
  /// apart.
  static const String stageSlot = '<$stageAnswer>';

  /// The manifest this platform's own trunk carries, when a program names no other.
  static const String defaultManifest = 'argocd/$stageSlot/root-app.yaml';

  /// The checkout.
  final String repository;

  /// The product branch.
  final String trunk;

  /// The manifest, relative to the checkout, with the stage still in its slot.
  final String manifest;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  String get irreversibleReason =>
      'this is where the authority over the cluster moves: from here the reconciler owns every '
      'object of every platform application, and taking the application away again takes all of '
      'them with it';

  /// The manifest this applies, for the stage this run was told about.
  String manifestIn(StepContext context) =>
      '$repository/${filledSlots(manifest, <String, String>{stageAnswer: context.answers.text(stageAnswer)})}';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String path = manifestIn(context);
    if (leftoverSlotIn(path) case final String left) {
      return CheckResult.blocked(
        'the manifest "$manifest" carries $left, and the one slot such a row may write is '
        '$stageSlot, which this run fills from its stage answer — the file would be looked for '
        'under the name as it stands',
      );
    }
    if (!await context.files.exists(path)) {
      return CheckResult.blocked(
        'the handoff is impossible: $path is not on this branch. The trunk carries one for '
        'every stage and the reduction to one stage keeps the one it prunes to, so this branch has '
        'lost it — restore it with "git -C $repository merge $trunk" and re-run',
      );
    }

    // The cluster's own answer to what applying this would change, rather than a prediction. It
    // also settles what nothing else can: whether the reconciler's own kinds are on this cluster
    // yet, because a manifest of a kind nobody registered cannot be compared at all.
    final CommandResult difference = await context.shell.run(
      kubectl.observing(<String>['diff', '-f', path]),
    );
    switch (difference.exitCode) {
      case 0:
        return CheckResult.satisfied('the cluster already holds what $path declares');
      case 1:
        return const CheckResult.ready();
      default:
        return CheckResult.blocked(
          'the cluster could not be asked what $path would change: '
          '${difference.stderr.trim().isEmpty ? 'the client returned ${difference.exitCode}' : difference.stderr.trim()}',
        );
    }
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      // Verified rather than predicted: the check asked the cluster itself, so what this says would
      // change is what the cluster answered.
      StepPlan.argv(kubectl.argv(_apply(context)), serverVerified: true);

  @override
  Future<void> apply(StepContext context) async {
    final Command apply = kubectl.command(_apply(context), timeout: const Duration(seconds: 60));
    final CommandResult applied = await context.shell.run(apply);
    if (!applied.ok) {
      throw CommandFailed(argv: apply.argv, exitCode: applied.exitCode, stderr: applied.stderr);
    }
  }

  List<String> _apply(StepContext context) => <String>[
    'apply',
    '-f',
    manifestIn(context),
    '--request-timeout=30s',
  ];
}
