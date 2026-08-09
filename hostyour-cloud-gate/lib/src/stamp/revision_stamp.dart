import 'package:hostyour_cloud/hostyour_cloud.dart';

/// Which manifests a branch run writes again, mirrored so a declaration can be measured against it.
///
/// Everything under `argocd/` names the branch it reads from. On the trunk that is the trunk
/// itself, which is what makes the trunk a product tree rather than an installation; on a branch it
/// is that installation's own name. The step that retargets it is `StampRevision`, Dart, in
/// simetrixch/ansiwise-plugins under `hostyour-cloud/lib/src/steps/branch/stamp_revision.dart`.
///
/// WHAT EARNS THE LICENCE HERE IS THE UNDO AND NOT THE APPLY. The step's `apply` rewrites only the
/// lines that still name the trunk, so on its own it would leave anything else a branch had put
/// there. Its `undo` is `git checkout -- argocd`, which restores the whole directory, and
/// `StampRole` removes the two stage trees this installation is not. Between them, nothing a branch
/// holds under this directory survives a run that the trunk does not also hold.
///
/// THIS IS NO LONGER A MIRROR. It used to restate the one constant it turns on, because the step
/// lived in another repository and this one could not reach it. It lives in this repository now, so
/// the constant is READ. Nothing is stated twice, so nothing can drift.
final class RevisionStamp {
  /// The stamp as the step defines it.
  const RevisionStamp();

  /// The directory holding the manifests that name a branch, as the step names it.
  ///
  /// Layout of the tree being generated rather than a value of one installation: every installation
  /// keeps its generators in the same place.
  static const String tree = StampRevision.tree;

  /// Whether a run writes [path] again, whatever the stage and whatever the role.
  bool regenerates(String path) => path == tree || path.startsWith('$tree/');
}
