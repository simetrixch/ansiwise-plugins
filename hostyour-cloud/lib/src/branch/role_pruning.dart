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
///
/// THE PATHS THE RULE SPEAKS IN ARE CONFIGURATION, stated once as the defaults below. The step
/// takes them from its program row, defaulting to these; the gate constructs the rule with the same
/// defaults. The two therefore agree exactly as long as no program row overrides a default — a row
/// that does is a row the gate's stamp checks no longer describe, and dissolving the gate is what
/// removes that edge, not a second statement here.
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
  /// The four path parameters default to the layout this tree has today, so a caller that says
  /// nothing gets the rule the program rows also get by default.
  const RolePruning({
    required this.stage,
    required this.stages,
    required this.isSlave,
    required this.ownMap,
    this.stageFiles = defaultStageFiles,
    this.stageTrees = defaultStageTrees,
    this.booksTree = defaultBooksTree,
    this.mapsTree = defaultMapsTree,
  });

  /// The stage this branch keeps.
  final String stage;

  /// Every stage the product carries, so the rule needs no list of its own to fall out of date.
  final List<String> stages;

  /// Whether this branch is a slave's, which is what decides the books.
  final bool isSlave;

  /// Where this branch's own cluster map stands, relative to the top of the checkout.
  final String ownMap;

  /// The files a stage owns, as regular expressions carrying the `<stage>` slot.
  ///
  /// Anchored at the top of the checkout, so the product material a chart keeps under its own
  /// `templates/` is never one of them — that is shipped to every installation and belongs to none.
  final List<String> stageFiles;

  /// The directories a stage owns, as plain paths carrying the `<stage>` slot.
  ///
  /// A directory rather than a pattern, because the step also removes the directory itself once it
  /// is emptied — one value serves both, so the two cannot disagree about where a stage tree is.
  final List<String> stageTrees;

  /// The directory the books of onboarded units stand in, which only a master's branch keeps.
  final String booksTree;

  /// The directory the cluster maps stand in, of which a slave's branch keeps only its own.
  final String mapsTree;

  /// The text a path value writes where the name of a stage belongs.
  ///
  /// The same notation a template and a program file use for a value that cannot be written down in
  /// advance: a name and nothing else, no expression and no condition.
  static const String stageSlot = '<stage>';

  /// The files a stage owns, unless a program row says otherwise.
  static const List<String> defaultStageFiles = <String>[
    r'^platform/values-<stage>\.yaml$',
    r'^apps/[^/]+/values-<stage>\.yaml$',
  ];

  /// The directories a stage owns, unless a program row says otherwise.
  static const List<String> defaultStageTrees = <String>['$generatorTree/$stageSlot'];

  /// Where the books stand, unless a program row says otherwise.
  static const String defaultBooksTree = 'registrations';

  /// Where the cluster maps stand, unless a program row says otherwise.
  static const String defaultMapsTree = 'clusters/active';

  /// The directory holding the manifests that name the branch they are read from.
  ///
  /// Layout of the tree being generated rather than a value of one installation: every installation
  /// keeps its generators in the same place, so anything that could point elsewhere would only be
  /// able to point somewhere wrong. The default stage trees reduce it to one stage, the gate reads
  /// it to decide which paths a run writes again, and the program row that stamps the branch names
  /// the same directory.
  static const String generatorTree = 'argocd';

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
    if (path.startsWith('$booksTree/')) {
      return PruneReason.registration;
    }
    if (_oneMap.hasMatch(path) && path != ownMap) {
      return PruneReason.foreignMap;
    }
    return null;
  }

  /// One cluster's map, and no directory below it.
  RegExp get _oneMap => RegExp('^${RegExp.escape(mapsTree)}/[^/]+\\.yaml\$');

  bool _belongsToStage(String path, String other) {
    for (final String tree in stageTrees) {
      if (path.startsWith('${filled(tree, other)}/')) {
        return true;
      }
    }
    for (final String pattern in stageFiles) {
      if (RegExp(pattern.replaceAll(stageSlot, RegExp.escape(other))).hasMatch(path)) {
        return true;
      }
    }
    return false;
  }

  /// [value] with its `<stage>` slot holding [stage], for a plain path.
  static String filled(String value, String stage) => value.replaceAll(stageSlot, stage);
}
