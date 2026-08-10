import 'package:hostyour_cloud/hostyour_cloud.dart';

import '../tree/source_tree.dart';

/// Where an installation's own domain is written into the tree, applied to a tree so it can be
/// measured.
///
/// Generating an installation means replacing the placeholder with that installation's fqdn in every
/// file where the placeholder IS installation state — and in none of the files where it is a guard,
/// a fixture, an illustration or the documentation of the stamp itself. The step that does it is
/// `StampPlaceholderInTrackedFiles`, and the rule it selects by is [FqdnSelection].
///
/// THIS IS NO LONGER A MIRROR. It used to restate the step's rule, because the step lived in another
/// repository and this one could not reach it. It lives in this repository now, so the rule is READ:
/// every constant and every test below comes from the one object the step itself asks. Nothing is
/// stated twice, so nothing can drift — a changed exclusion changes what the gate measures in the
/// same edit, without anyone remembering that a second copy exists.
///
/// WHAT IS LEFT HERE IS THE PART A STEP HAS NO USE FOR: applying the rule to a whole tree at once,
/// which is what the branch-class audit needs and what a counter-probe drives over paths it planted.
final class DomainStamp {
  /// The stamp as the step defines it.
  const DomainStamp();

  /// The rule itself, as the step selects by it.
  static const FqdnSelection rule = StampPlaceholderInTrackedFiles.selection;

  /// What the trunk says where an installation says its own name.
  static const String placeholder = FqdnSelection.placeholder;

  /// The paths of [tree] this stamp would rewrite, sorted.
  ///
  /// Takes a tree rather than reaching for the repository, so a counter-probe can drive the same
  /// selection over paths it planted — including the ones the exclusions must hold for, which no
  /// real tree is obliged to carry.
  List<String> selectionIn(SourceTree tree) => <String>[
    for (final String path in tree.paths)
      if (rule.selects(path, tree.textOf(path))) path,
  ];

  /// Whether this stamp would rewrite [path], whose content is [text].
  bool selects(String path, String? text) => rule.selects(path, text);
}
