/// What an install branch does NOT carry, as a rule and nothing else.
///
/// The trunk is generic in two directions at once: it carries all three stages, because it is the
/// tree every installation is cut from, and it carries the books, because it does not know which
/// cluster will read them. An installation is neither — exactly one stage, exactly one role — and
/// `StampRole` is what reduces it.
///
/// REMOVING THE OTHER TWO STAGES IS NOT TIDYING. It is what makes it impossible for the stage a
/// chart renders, the paths its secrets are read from and the names of its releases to disagree with
/// one another: there is no second stage left for anything to resolve to by accident.
///
/// THE ROLE IS NEVER GUESSED, AND THE BRANCH'S OWN MAP IS KEPT BY NAME. A slave's branch is pruned
/// of every registration and of every foreign cluster map; its own map is what the pruning was
/// decided from, so it survives — and that one exception is the whole of the difference between the
/// two reasons a slave loses a file.
///
/// WHY THIS IS A CLASS OF ITS OWN AND NOT A METHOD OF THE STEP. Two callers need the same answer.
/// The step asks it of the paths git tracks, in order to remove them; the gate asks it of a tree it
/// walked, in order to decide whether the `derived:` rules in `branch-classes.yaml` name the same
/// paths a run would really resolve. The two used to be written out separately — the step in regular
/// expressions, the gate in string operations — and nothing compared them, so a changed pattern left
/// every probe in the gate green while it certified a pruning it was no longer describing.
///
/// IT ANSWERS WHICH RULE MATCHED, not merely whether one did, because the caller that measures the
/// declaration has to name the axis a removal came from. What that axis is CALLED is the gate's
/// business and not this rule's.
library;

/// Why a path does not survive the reduction to one stage and one role.
enum PruneReason {
  /// It belongs to a stage this branch is not.
  otherStage,

  /// It is a registration, and this branch is a slave's.
  registration,

  /// It is another cluster's map, and this branch is a slave's.
  foreignMap,
}

/// The rule that decides what an install branch loses.
final class RolePruning {
  /// The rule for a branch of [stage], slave or not by [isSlave], whose own map is [ownMap].
  ///
  /// [ownMap] is a path relative to the top of the checkout, and it is the one map a slave keeps.
  const RolePruning({
    required this.stage,
    required this.stages,
    required this.isSlave,
    required this.ownMap,
  });

  /// The stage this branch keeps.
  final String stage;

  /// Every stage the product carries, so the rule needs no list of its own to fall out of date.
  final List<String> stages;

  /// Whether this branch is a slave's, which is what decides the books.
  final bool isSlave;

  /// Where this branch's own cluster map stands, relative to the top of the checkout.
  final String ownMap;

  /// Why [path] is pruned, or null when it stays.
  PruneReason? reasonFor(String path) {
    for (final String other in stages) {
      if (other != stage && _belongsToStage(path, other)) {
        return PruneReason.otherStage;
      }
    }
    if (!isSlave) {
      return null;
    }
    if (path.startsWith(registrations)) {
      return PruneReason.registration;
    }
    if (clusterMap.hasMatch(path) && path != ownMap) {
      return PruneReason.foreignMap;
    }
    return null;
  }

  /// Where an onboarded unit's registrations stand.
  static const String registrations = 'registrations/';

  /// The directory holding the manifests that name the branch they are read from.
  ///
  /// Layout of the tree being generated rather than a value of one installation: every installation
  /// keeps its generators in the same place, so anything that could point elsewhere would only be
  /// able to point somewhere wrong. The stage patterns below reduce it to one stage, the gate reads
  /// it to decide which paths a run writes again, and the program row that stamps the branch names
  /// the same directory.
  static const String generatorTree = 'argocd';

  /// One cluster's map, and no directory below it.
  static final RegExp clusterMap = RegExp(r'^clusters/active/[^/]+\.yaml$');

  /// The three shapes a stage owns: its platform values, its manifest tree, its per-app overrides.
  ///
  /// Anchored at the top of the checkout, so the product material a chart keeps under its own
  /// `templates/` is never one of them — that is shipped to every installation and belongs to none.
  static List<RegExp> patternsForStage(String stage) {
    final String quoted = RegExp.escape(stage);
    return <RegExp>[
      RegExp('^platform/values-$quoted\\.yaml\$'),
      RegExp('^$generatorTree/$quoted/'),
      RegExp('^apps/[^/]+/values-$quoted\\.yaml\$'),
    ];
  }

  static bool _belongsToStage(String path, String stage) =>
      patternsForStage(stage).any((RegExp pattern) => pattern.hasMatch(path));
}
