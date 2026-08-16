/// Which files of a checkout a stamp may rewrite, as a rule and nothing else.
///
/// A stamp replaces a literal wherever that literal is a VALUE, and in none of the places where it
/// is a guard, a fixture, an illustration or the documentation of the stamp itself. Telling those
/// apart cannot be done by looking at the literal — it is the same literal — so it is done by
/// looking at the path and at the first line of the file.
///
/// WHY THIS IS A CLASS OF ITS OWN AND NOT A METHOD OF THE STEP. It is asked twice about different
/// things: once about a path, before the file is opened, and once about the text, after. Keeping it
/// in one place means those two questions cannot come apart, and it means a test can drive it over
/// paths no real checkout carries — which is the only way an exclusion can be shown to hold.
///
/// NO PORTS AND NO CONTEXT. It takes a path and the text at that path, so a caller that already has
/// the text does not read the file again.
///
/// EVERY LIST IS THE CALLER'S. Which directories hold material rather than state, which files
/// declare something about the stamp, and which suffixes name a script are facts of the tree being
/// stamped. A default here would be this package deciding them for whatever tree it is pointed at,
/// and a caller with a different tree would inherit choices nobody made for it.
///
/// TWO OF THE EXCLUSIONS WERE PAID FOR, and the reason is kept because it is what stops somebody
/// removing them. Scripts are excluded as a class, because a literal inside a script is never a
/// value: before the exclusion existed, a script whose own guard compared against the literal came
/// out refusing the very value it was being given, and a library whose empty-value test read the
/// literal came out producing empty results. And a script is recognised by its FIRST LINE as well as
/// by its suffix, because a suffix list alone let an extensionless script through and the stamp
/// reached into one again.
library;

/// The rule that decides what a stamp rewrites.
final class StampSelection {
  /// The rule, over the exclusion lists the caller states.
  const StampSelection({
    required this.excludedSegments,
    required this.excludedNames,
    required this.scriptSuffixes,
  });

  /// Path segments whose contents are material rather than state.
  ///
  /// A segment and not a prefix: a directory of that name is excluded wherever it sits, because one
  /// several levels down is the same kind of thing as one at the top of the tree.
  final List<String> excludedSegments;

  /// Files excluded by their name, because each declares something about this stamp.
  ///
  /// A file that explains what is stamped quotes the literal in order to explain it. Rewritten, the
  /// one file somebody opens to learn what is never stamped would read as its own opposite.
  final List<String> excludedNames;

  /// The suffixes of the scripts that carry no first line to recognise them by.
  final List<String> scriptSuffixes;

  /// Whether [path], whose content is [text], holds a value a stamp may rewrite.
  ///
  /// A [text] of null is a path with nothing readable at it — absent, or bytes rather than text —
  /// and nothing is rewritten there.
  bool holdsStampableValue(String path, String? text) =>
      text != null && !excludesByName(path) && !text.startsWith('#!');

  /// Whether what [path] is called already says it holds nothing to stamp.
  ///
  /// Separate, because the caller tests it BEFORE opening the file: a content search has already
  /// narrowed several hundred tracked paths to a few, and a name test costs nothing where reading
  /// the file costs a syscall.
  bool excludesByName(String path) {
    final List<String> segments = path.split('/');
    return segments.any(excludedSegments.contains) ||
        excludedNames.contains(segments.last) ||
        scriptSuffixes.any(path.endsWith);
  }
}
