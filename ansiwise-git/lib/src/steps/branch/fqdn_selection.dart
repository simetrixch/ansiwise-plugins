/// Which files of a checkout hold this installation's own domain, as a rule and nothing else.
///
/// Generating an installation means replacing the placeholder with that installation's fqdn in every
/// file where the placeholder IS installation state — and in NONE of the files where it is a guard,
/// a fixture, an illustration or the documentation of the stamp itself.
///
/// WHY THIS IS A CLASS OF ITS OWN AND NOT A METHOD OF THE STEP. Two callers need the same answer for
/// different reasons. The stamp asks it about a file it read off a machine, in order to rewrite it.
/// The gate asks it about a tree it walked, in order to decide whether the declaration in
/// `branch-classes.yaml` agrees with what would really happen. When the rule was written out twice —
/// once inside the step, once as a mirror in the gate — the two could drift, and nothing compared
/// them: a changed exclusion left every probe in the gate green while it certified a stamp it was no
/// longer describing. There is nothing to compare now because there is nothing stated twice.
///
/// NO PORTS AND NO CONTEXT. It takes a path and the text at that path, so a caller that has the text
/// already does not read the file again, and a test can drive it over paths no real tree carries —
/// which is the only way the exclusions can be proven to hold.
///
/// THE EXCLUSION LISTS ARE CONFIGURATION, stated once as the defaults below. The stamp step takes
/// them from its program row, defaulting to these; the gate reads the default rule. The two agree
/// exactly as long as no program row overrides a default — a row that does is a row the gate's
/// stamp checks no longer describe, and dissolving the gate is what removes that edge, not a second
/// statement here.
///
/// TWO OF THE EXCLUSIONS WERE PAID FOR. Scripts are excluded as a class, because the placeholder
/// inside one is never installation state: before the exclusion existed, a script whose own guard
/// compared against the placeholder came out refusing the very domain it was being installed for,
/// and a library whose empty-value test read the placeholder came out producing hosts with no domain
/// at all. And a script is recognised by its FIRST LINE as well as by its suffix, because a suffix
/// list alone let an extensionless script through and the stamp reached into one again.
library;

/// The rule that decides what the domain stamp rewrites.
final class FqdnSelection {
  /// The rule, over the exclusion lists given — or over the defaults, which are what the gate reads
  /// and what a program row that says nothing gets.
  const FqdnSelection({
    this.excludedSegments = defaultExcludedSegments,
    this.excludedNames = defaultExcludedNames,
    this.scriptSuffixes = defaultScriptSuffixes,
  });

  /// What the trunk carries in place of a domain.
  static const String placeholder = 'example.invalid';

  /// Path segments whose contents are product material, unless a program row says otherwise.
  static const List<String> defaultExcludedSegments = <String>['docs', 'templates'];

  /// Files excluded by name, unless a program row says otherwise.
  static const List<String> defaultExcludedNames = <String>['branch-classes.yaml'];

  /// The script suffixes, unless a program row says otherwise.
  static const List<String> defaultScriptSuffixes = <String>['.sh', '.ps1'];

  /// Path segments whose contents are product material rather than installation state.
  ///
  /// A segment and not a prefix: a chart's `templates/` sits several levels down and is the same
  /// kind of thing as one at the top of the tree.
  final List<String> excludedSegments;

  /// Files excluded by their name, because each is a declaration about this stamp.
  ///
  /// The default names the file that states which paths hold installation state: it quotes the
  /// placeholder in order to explain what is done to it. Rewritten, the one file an operator opens
  /// to learn which paths must never be stamped would itself name a real domain, and the section
  /// listing what is never stamped would read as its own opposite.
  final List<String> excludedNames;

  /// The suffixes of the scripts that carry no first line to recognise them by.
  final List<String> scriptSuffixes;

  /// Whether the domain stamp rewrites [path], whose content is [text].
  ///
  /// A [text] of null is a path with nothing readable at it — absent, or bytes rather than text —
  /// and nothing is rewritten there.
  bool selects(String path, String? text) =>
      text != null && text.contains(placeholder) && holdsInstallationState(path, text);

  /// Whether [path], whose content is [text], holds installation state at all.
  ///
  /// [selects] is this question plus the placeholder being in the file, and asks it through here so
  /// that the two cannot come apart. Every stamp into a checkout asks this one and only differs in
  /// which literal it then replaces: a script, a document and a chart template hold product material
  /// whatever the literal is, and rewriting one is the failure the exclusions were paid for.
  bool holdsInstallationState(String path, String? text) =>
      text != null && !excludesByName(path) && !text.startsWith('#!');

  /// Whether what [path] is called already says it holds no installation state.
  ///
  /// Separate from [selects] because the step tests it BEFORE opening the file: a content search has
  /// already narrowed several hundred tracked paths to a few, and a name test costs nothing where
  /// reading the file costs a syscall.
  bool excludesByName(String path) {
    final List<String> segments = path.split('/');
    return segments.any(excludedSegments.contains) ||
        excludedNames.contains(segments.last) ||
        scriptSuffixes.any(path.endsWith);
  }
}
