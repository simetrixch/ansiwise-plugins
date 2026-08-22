/// The packages this repository releases, and the two things a release writes into each of them.
///
/// ONE TAG SERVES TWELVE PACKAGES, AND A THIRTEENTH NEEDS NO LINE ANYWHERE. This is the decision
/// this file exists to carry, and whoever adds a package here is the reader it is written for. A git
/// dependency names a REF and a PATH, so one ref can serve every package of one repository and each
/// consumer picks its own path out of it. That is why a release here is one tag and not twelve.
///
/// WHAT THE OTHER ANSWER WOULD HAVE COST. Twelve tags per release is the smaller half of it. The
/// larger half is that a consumer could then hold two packages of this repository at two refs — and
/// that is a tree nobody can build from any single checkout, because the second ref is a second
/// clone of the same repository with a different tree in it. It is not a theory: ansiwise-vault-
/// kubernetes/pubspec.yaml depends on ansiwise_vault and ansiwise_kubernetes, its own two siblings,
/// so two refs of this repository in one resolution meet each other. Asked with real pub against
/// real GitHub, one package of this repository pinned at a commit while a sibling of it named
/// `master`, the answer was:
///
/// ```
/// Because every version of ansiwise_vault_kubernetes from git depends on ansiwise_vault from git
/// … at master in ansiwise-vault and pin_probe depends on ansiwise_vault from git … at
/// 1133b984bb4f15d36a1cac47aa22cd3443ff1de6 in ansiwise-vault, ansiwise_vault_kubernetes from git is
/// forbidden.
/// ```
///
/// So a package of this repository is added by making a directory named `ansiwise-<tool>` with a
/// pubspec.yaml in it, and nothing else: the walk below finds it, the release bumps it with the
/// other twelve, the gate runs its `dart test`, and the tag a consumer pins already carries it.
///
/// THE SECOND THING A RELEASE WRITES IS WHY THAT MEASUREMENT IS HERE. Those two sibling
/// dependencies say `ref: master` in the tree, and a tag whose inside says `master` pins nothing at
/// all — a consumer naming the tag would resolve one package from it and its sibling from whatever
/// master holds today, which is the very thing a pinned consumer is meant to stop. pub does not even
/// get that far, as the answer above shows. So the release stamps every sibling dependency's `ref:`
/// to the tag being cut, IN THE COMMIT THE TAG NAMES, and the tree at that tag then names exactly
/// one version of every package in it.
///
/// WHAT DECIDES THAT A DEPENDENCY IS A SIBLING IS ITS `path:` AND NOT ITS `url:`. A url can be
/// written several ways for one repository — over https or over ssh, with the `.git` or without —
/// and a program comparing spellings would quietly stamp nothing the day somebody wrote another
/// one. A `path:` names a directory of this checkout, and whether that directory is a package here
/// is a fact this program can read off the disk rather than a spelling it has to recognise.
///
/// A DEPENDENCY THAT IS NOT A SIBLING IS NOT STAMPED, AND THAT IS WHY IT IS REFUSED INSTEAD. The tag
/// a release cuts is a name in THIS repository. Writing it into the dependency on ansiwise_core
/// would name a tag ansiwise-core does not have, so a consumer resolving it would get nothing at
/// all — worse than the branch it replaced, which at least resolves. Nor may the program pick a tag
/// of its own: which version of the framework these packages were built and gated against is stated
/// by the manifests, and a release choosing a different one would change what the gate ran over in
/// the same act that published it.
///
/// SO A FOREIGN REF HAS TO ALREADY NAME A RELEASED TAG BEFORE A RELEASE STARTS, and one that names a
/// branch stops it and is reported line by line. What counts as a released tag is the grammar
/// hostyour-manager/shared/release.ts:22 owns and every repository of this organisation cuts under,
/// read out of this repository's own workflow rather than spelled a second time here. Left alone,
/// the alternative is a tag whose twelve manifests each resolve the framework from whatever master
/// holds that day — the very defect the sibling half above exists to close, one repository out.
library;

import 'dart:io';

import 'release_tag_filter.dart';

/// The manifests of the packages a release carries, as something the release program is handed.
///
/// The same split tool/release_git.dart makes: what the release program DECIDES is one thing and
/// reading and writing files on this operating system is another. It is what lets the deciding half
/// — including the half that bumps twelve manifests and stamps the refs inside two of them — be
/// driven by a check on a machine where no pubspec.yaml is touched.
abstract interface class Manifests {
  /// Every manifest, as a path relative to the repository root, in the order a screen lists them.
  List<String> get paths;

  /// What the manifest at [path] holds, or null when there is no such file.
  String? read(String path);

  /// Replaces what the manifest at [path] holds with [text].
  void write(String path, String text);
}

/// The name every package directory of this repository begins with.
///
/// A package here is one TOOL, and the twelve are named after the tool each drives. The prefix is
/// what the walk looks for, so this package — which drives no tool and is nobody's dependency —
/// stands beside them under a name of its own and is not released as one of them.
const String packageDirectoryPrefix = 'ansiwise-';

/// The pubspec.yaml of every package directory of a repository, read off the disk.
final class PubspecsInRepository implements Manifests {
  /// The manifests standing under [repository], found rather than listed.
  ///
  /// WHAT IS SORTED IS THE DIRECTORY AND NOT THE PATH. `ansiwise-vault-kubernetes/pubspec.yaml`
  /// stands before `ansiwise-vault/pubspec.yaml` when whole paths are compared, because a hyphen
  /// comes before a slash — and a screen listing the packages of this repository in that order is
  /// answering about the separator rather than about the packages.
  factory PubspecsInRepository(Directory repository) {
    final List<String> found = <String>[];
    for (final FileSystemEntity entry in repository.listSync()) {
      final String name = entry.path.split(RegExp(r'[/\\]')).last;
      if (entry is Directory &&
          name.startsWith(packageDirectoryPrefix) &&
          File('${entry.path}/pubspec.yaml').existsSync()) {
        found.add(name);
      }
    }
    found.sort();
    return PubspecsInRepository._(repository, <String>[
      for (final String directory in found) '$directory/pubspec.yaml',
    ]);
  }

  const PubspecsInRepository._(this._repository, this.paths);

  final Directory _repository;

  @override
  final List<String> paths;

  @override
  String? read(String path) {
    final File file = File('${_repository.path}/$path');
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  void write(String path, String text) => File('${_repository.path}/$path').writeAsStringSync(text);
}

/// One package's manifest, as it stands.
final class ManifestState {
  /// The manifest at [path] holds [text] and declares [declaredName] at [declaredVersion].
  ManifestState({required this.path, required this.text})
    : declaredVersion = declaredVersionIn(text),
      declaredName = declaredNameIn(text);

  /// Where it is, as a refusal names it.
  final String path;

  /// What it holds.
  final String text;

  /// The version it declares, or null when it declares none.
  final String? declaredVersion;

  /// The package name it declares, which is what a consumer writes the dependency under.
  final String? declaredName;

  /// The directory it stands in, which is the `path:` a consumer names to reach this package.
  String get directory => path.split('/').first;
}

/// Every package a release of this repository carries, read together.
final class ReleasedPackages {
  const ReleasedPackages._({required this.manifests, required this.missing});

  /// What [manifests] holds, read once.
  factory ReleasedPackages.read(Manifests manifests) {
    final List<ManifestState> states = <ManifestState>[];
    final List<String> missing = <String>[];
    for (final String path in manifests.paths) {
      final String? text = manifests.read(path);
      if (text == null) {
        missing.add(path);
      } else {
        states.add(ManifestState(path: path, text: text));
      }
    }
    return ReleasedPackages._(manifests: states, missing: missing);
  }

  /// Every manifest that could be read, in the order the walk found them.
  final List<ManifestState> manifests;

  /// The manifests the walk named and could not read.
  final List<String> missing;

  /// The directory of every package here, which is the set of `path:` values a consumer can name.
  Set<String> get directories => <String>{
    for (final ManifestState each in manifests) each.directory,
  };

  /// Why this repository cannot be released as it stands, or null when it can.
  ///
  /// ONE TAG IS ONE VERSION, SO TWELVE VERSIONS THAT DISAGREE ARE TWELVE ANSWERS TO WHAT THE TAG
  /// IS. A consumer reading `ansiwise_helm` at tag 0.2.0-stable-… asks what version it is holding,
  /// and the manifest inside is the only thing that answers. If one of them said 0.1.0 while its
  /// neighbours said 0.2.0, the tag would carry both answers and nothing would say which is the
  /// release. So the release refuses, names every version standing here and which package declares
  /// it, and lets a person put them right — rather than picking one and overwriting the rest, which
  /// would hide the disagreement in the same act that resolved it.
  String? get refusal {
    if (missing.isNotEmpty) {
      return 'the walk over this repository named ${missing.join(', ')} and could not read '
          '${missing.length == 1 ? 'it' : 'them'}, so what the release would bump is unknown';
    }
    if (manifests.isEmpty) {
      return 'no directory of this repository is named $packageDirectoryPrefix… with a pubspec.yaml '
          'in it, so there is nothing here to release and a tag would name a tree with no package '
          'in it';
    }
    final List<String> undeclared = <String>[
      for (final ManifestState each in manifests)
        if (each.declaredVersion == null) each.path,
    ];
    if (undeclared.isNotEmpty) {
      return '${undeclared.join(', ')} declares no version, and a package released under a tag that '
          'states a version while the package states none is two answers to what a consumer is '
          'holding';
    }
    final Map<String, List<String>> byVersion = <String, List<String>>{};
    for (final ManifestState each in manifests) {
      byVersion.putIfAbsent(each.declaredVersion!, () => <String>[]).add(each.directory);
    }
    if (byVersion.length > 1) {
      final List<String> spelled = <String>[
        for (final MapEntry<String, List<String>> entry in byVersion.entries)
          '${entry.key} (${entry.value.join(', ')})',
      ];
      return 'the packages of this repository declare ${byVersion.length} different versions — '
          '${spelled.join('; ')} — and one tag carries one version, so a release cut now would '
          'publish a tag that answers that question two ways';
    }
    return null;
  }

  /// The one version every package here declares, or null when they do not agree on one.
  String? get declaredVersion => refusal == null ? manifests.first.declaredVersion : null;

  /// The address this repository's own packages name it by, or null when none of them names it.
  ///
  /// THE RELEASE PAGE MUST NOT INVENT A SECOND SPELLING OF IT. pub reads a git dependency's url as
  /// part of what identifies the package, so `…/ansiwise-plugins` and `…/ansiwise-plugins.git` are
  /// two sources of one thing and a consumer holding one of each cannot resolve. The packages here
  /// already spell it — that is what a sibling dependency's `url:` is — so the page copies theirs
  /// instead of composing one from a remote, which would be spelled however a checkout happened to
  /// set `origin` up.
  String? get siblingUrl {
    for (final ManifestState manifest in manifests) {
      for (final GitDependency dependency in gitDependenciesIn(manifest.text)) {
        if (dependency.isSiblingOf(directories) && dependency.url != null) {
          return dependency.url;
        }
      }
    }
    return null;
  }

  /// Every dependency on ANOTHER repository naming something [filter] would not have released.
  ///
  /// A sibling is never in here, and the two halves are not the same question. A sibling's `ref:` is
  /// a line this release is about to overwrite with the tag it is cutting, so a sibling naming a
  /// branch today is already answered. A foreign ref names a commit in a repository this release
  /// does not tag, so nothing here can put it right and it has to be right before the release runs.
  ///
  /// Read by the screen and by the refusal, so that what a person is shown and what stops them are
  /// one answer rather than two that can drift apart.
  List<String> followed(TagFilter filter) => <String>[
    for (final ManifestState manifest in manifests)
      for (final GitDependency dependency in gitDependenciesIn(manifest.text))
        if (!dependency.isSiblingOf(directories) && !dependency.isReleased(filter))
          followedAs(manifest.path, dependency),
  ];
}

/// How one dependency naming no released tag reads on the screen and in a refusal.
///
/// It opens with `path:line` because twelve manifests naming `master` are twelve separate lines to
/// put right, and a sentence naming only the ref would say which value is wrong without saying where
/// it is written. The dependency's own name follows where the manifest gives it one, since that is
/// the word standing over the block a person edits.
String followedAs(String manifest, GitDependency dependency) =>
    '$manifest:${dependency.gitLine + 1}'
    '${dependency.package == null ? '' : ' ${dependency.package}'} at '
    '${dependency.ref == null ? 'no ref at all, which is the default branch' : '"${dependency.ref}"'}';

/// What a release would write into the manifests, or why it could not be composed.
final class Bump {
  /// [texts] is what each manifest is to be replaced with, keyed by its path.
  const Bump.written({required this.texts, required this.stamped, required this.already})
    : refusal = null;

  /// Nothing is to be written, and [refusal] says what stopped it.
  const Bump.refused(this.refusal)
    : texts = const <String, String>{},
      stamped = const <String>[],
      already = const <String>[];

  /// What each manifest is to be replaced with — only the ones that really change are in here.
  final Map<String, String> texts;

  /// The sibling dependencies whose `ref:` this bump stamps, as `<manifest> → <package>`.
  final List<String> stamped;

  /// The manifests that already said what the bump would write, so nothing is to be done to them.
  final List<String> already;

  /// Why there is nothing to write, or null when there is.
  final String? refusal;

  /// Whether the bump could be composed.
  bool get isGreen => refusal == null;
}

/// What [packages] become when the release is [version] and the tag is [tag].
///
/// TWO EDITS PER MANIFEST AND BOTH IN ONE COMMIT: the version every package declares is set to
/// [version], and every sibling dependency's `ref:` is set to [tag]. They travel together because
/// they are two halves of one statement — the tag says which tree this is, and the tree has to say
/// the same thing back from the inside.
///
/// A MANIFEST THAT ALREADY SAYS BOTH IS NOT AN ERROR AND IS NOT A WRITE. Cutting 0.1.0 on alpha and
/// then on stable is two releases of one version, and the version half of the second has nothing to
/// change; the ref half always does, because the ts14 makes every tag a new one.
///
/// A THIRD THING IS ASKED AND NEVER WRITTEN: every dependency these manifests declare on ANOTHER
/// repository has to name a tag [filter] would have released. There is no edit that could put such a
/// ref right — the tag being cut is a name in this repository — so it is a refusal and not a write,
/// and every one of them is named at once rather than one per run.
Bump bumpFor({
  required ReleasedPackages packages,
  required String version,
  required String tag,
  required TagFilter filter,
}) {
  if (packages.refusal case final String why) {
    return Bump.refused(why);
  }
  // BEFORE ANY REF IS JUDGED, because a shape the reader cannot see is not a dependency that passed
  // — it is one nothing looked at, and the two are indistinguishable in a green run.
  final List<String> unreadable = <String>[
    for (final ManifestState manifest in packages.manifests)
      for (final String where in unreadableGitShapesIn(manifest.text)) '${manifest.path} $where',
  ];
  if (unreadable.isNotEmpty) {
    return Bump.refused(
      'these lines write a git dependency in a shape this program does not read — '
      '${unreadable.join('; ')}. `pub` takes them and so would a release, which is the problem: a '
      'one-line `git: <url>` names no ref and follows the default branch, and a dependency written '
      'inside braces keeps its ref where the walk for indented keys never looks. Either way the '
      'line would be neither stamped nor refused, and a tag published over it would pin nothing '
      'while looking pinned. Write the dependency as a block — `git:` on its own line with `url:`, '
      '`ref:` and `path:` indented under it — which is the shape every manifest of this repository '
      'already uses',
    );
  }
  final List<String> followed = packages.followed(filter);
  if (followed.isNotEmpty) {
    return Bump.refused(
      'these packages name another repository at something that is no released tag — '
      '${followed.join('; ')}. The tag $tag is a name in THIS repository and says nothing about '
      'theirs, so there is no line here to stamp and this program will not guess which version was '
      'meant. These packages compile to no file, so the tree at $tag IS the release, and a tree '
      'naming a branch resolves to something else tomorrow under the same name — the pin a consumer '
      'took the tag for. Pin each of them to a released tag of the repository it names first. What '
      'counts as a released tag is the grammar hostyour-manager/shared/release.ts:22 owns and every '
      'repository of this organisation cuts under, read here out of $releaseWorkflowPath',
    );
  }
  final Set<String> siblings = packages.directories;
  final Map<String, String> texts = <String, String>{};
  final List<String> stamped = <String>[];
  final List<String> already = <String>[];
  for (final ManifestState manifest in packages.manifests) {
    final String? versioned = pubspecWithVersion(manifest.text, version);
    if (versioned == null) {
      return Bump.refused(
        '${manifest.path} declares no version, so there is nothing to set to $version',
      );
    }
    final List<GitDependency> unstampable = <GitDependency>[
      for (final GitDependency each in gitDependenciesIn(manifest.text))
        if (each.isSiblingOf(siblings) && each.refLine == null) each,
    ];
    if (unstampable.isNotEmpty) {
      return Bump.refused(
        '${manifest.path} depends on '
        '${unstampable.map((GitDependency each) => each.path).join(', ')} of this repository '
        'without a `ref:` line, so the release cannot say which tag that dependency is at — and a '
        'git dependency with no ref resolves the default branch, which is the pin this release '
        'exists to replace. Give it a ref line and the release will stamp it',
      );
    }
    final (String stampedText, List<String> refs) = pubspecWithSiblingRefs(
      versioned,
      siblings: siblings,
      ref: tag,
    );
    for (final String each in refs) {
      stamped.add('${manifest.path} → $each');
    }
    if (stampedText == manifest.text) {
      already.add(manifest.path);
    } else {
      texts[manifest.path] = stampedText;
    }
  }
  return Bump.written(texts: texts, stamped: stamped, already: already);
}

/// The version [pubspec] declares this package at, or null when it declares none.
String? declaredVersionIn(String pubspec) => _declaredVersion.firstMatch(pubspec)?.group(1)?.trim();

/// [pubspec] with the version it declares set to [version], or null when it declares none.
///
/// WHAT IS WRITTEN IS THE THREE NUMBERS AND NOT THE TAG. The release surface takes a version and a
/// channel and never a whole tag — hostyour-manager/shared/release.ts:47 — and the version offered
/// as the first release is read straight back out of here, so a manifest carrying
/// `0.1.0-alpha-20260821194500` would propose a string nobody types as a version.
String? pubspecWithVersion(String pubspec, String version) => _declaredVersion.hasMatch(pubspec)
    ? pubspec.replaceFirst(_declaredVersion, 'version: $version')
    : null;

final RegExp _declaredVersion = RegExp(r'^version:[ \t]*(\S+)[ \t]*$', multiLine: true);

/// The package name [pubspec] declares, or null when it declares none.
///
/// It is the word a consumer writes its dependency under, and it is not the directory name: the
/// directory is `ansiwise-vault` and the package is `ansiwise_vault`. The release page carries both,
/// because a consumer's pubspec needs one of each and reading one off the other is a rule nobody
/// stated.
String? declaredNameIn(String pubspec) => _declaredName.firstMatch(pubspec)?.group(1)?.trim();

final RegExp _declaredName = RegExp(r'^name:[ \t]*(\S+)[ \t]*$', multiLine: true);

/// One `git:` block of a pubspec, read into the things a release cares about.
final class GitDependency {
  /// The block opened at [gitLine] under [package], naming [url] and [path], pinned at [ref] on
  /// [refLine].
  const GitDependency({
    required this.gitLine,
    required this.package,
    required this.url,
    required this.path,
    required this.ref,
    required this.refLine,
    required this.refIndent,
  });

  /// The line the `git:` key stands on, counted from zero.
  final int gitLine;

  /// The name the manifest writes this dependency under, or null when nothing encloses the `git:`.
  ///
  /// It is the word a person edits — `ansiwise_core`, not the directory and not the url — and it is
  /// the key the `git:` block stands inside rather than anything read out of that block.
  final String? package;

  /// The url it names, or null when it names none.
  final String? url;

  /// The path inside that repository it names, or null when it names none.
  final String? path;

  /// The ref it is pinned at, or null when it carries no `ref:` line.
  final String? ref;

  /// The line the `ref:` key stands on, or null when there is none.
  final int? refLine;

  /// The blank space the `ref:` line begins with, so a stamped line stands where the old one did.
  final String refIndent;

  /// Whether this names a package standing beside the one that declares it.
  ///
  /// [siblings] are the package directories of this repository, so a `path:` among them is a
  /// dependency inside this repository and every other one points somewhere else entirely.
  bool isSiblingOf(Set<String> siblings) => path != null && siblings.contains(path);

  /// Whether what it names is a tag [filter] would have released, rather than a branch.
  ///
  /// A block carrying no `ref:` line answers no rather than being passed over: pub then resolves the
  /// repository's default branch, which is the same thing as naming one and is the outcome this
  /// question exists to find.
  bool isReleased(TagFilter filter) => ref != null && filter.accepts(ref!);
}

/// Every `git:` block in [pubspec], in the order they stand.
///
/// READ AS LINES rather than as YAML, because everything under tool/ imports nothing but `dart:`.
/// What is walked is one key and the lines indented under it, which is the whole of what a git
/// dependency is written as. The keys inside a block may stand in any order — this repository's own
/// consumers already write `path:` before `ref:` in one place and after it in another — so nothing
/// here depends on which comes first.
///
/// **A SHAPE THIS READER CANNOT SEE IS REFUSED, never passed over.** `pub` also accepts a git
/// dependency written on one line — `git: <url>`, which follows the default branch and names no
/// ref — and one written as a flow mapping in braces. Neither is a block, so neither reaches the
/// walk below, and a reader that simply skipped them would let exactly the defect this program
/// exists to stop through: a manifest following a branch, published under a tag, reported as
/// pinned. Teaching the walk to read them would be a YAML parser inside a program that may import
/// no parser. So [unreadableGitShapesIn] finds them by their shape and the release stops, naming
/// the line and the block form to write instead.
List<GitDependency> gitDependenciesIn(String pubspec) {
  final List<String> lines = pubspec.split('\n');
  final List<GitDependency> found = <GitDependency>[];
  for (int index = 0; index < lines.length; index++) {
    if (_keyOf(lines[index]) != 'git' || _valueOf(lines[index]).isNotEmpty) {
      continue;
    }
    final int enclosing = _indentOf(lines[index]);
    String? url;
    String? path;
    String? ref;
    int? refLine;
    String refIndent = '';
    for (int inner = index + 1; inner < lines.length; inner++) {
      if (lines[inner].trim().isEmpty) {
        continue;
      }
      if (_indentOf(lines[inner]) <= enclosing) {
        break;
      }
      switch (_keyOf(lines[inner])) {
        case 'url':
          url = _valueOf(lines[inner]);
        case 'path':
          path = _valueOf(lines[inner]);
        case 'ref':
          ref = _valueOf(lines[inner]);
          refLine = inner;
          refIndent = lines[inner].substring(0, _indentOf(lines[inner]));
      }
    }
    found.add(
      GitDependency(
        gitLine: index,
        package: _enclosingKeyOf(lines, index),
        url: url,
        path: path,
        ref: ref,
        refLine: refLine,
        refIndent: refIndent,
      ),
    );
  }
  return found;
}

/// [pubspec] with every sibling dependency's `ref:` set to [ref], and which packages were stamped.
///
/// THE REF LINE IS REPLACED WHERE IT STANDS, and its own indentation is written back rather than
/// composed: the line has to go back exactly where it came from, and a pubspec whose blank space
/// this program normalised would be a diff about whitespace on top of the diff about the release.
///
/// WHAT IS MATCHED IS THE PATH AND NOT THE OLD REF. Stamping by looking for `master` would work
/// exactly once — the release after it would find the previous tag standing there and leave it — so
/// the old value is never read, only overwritten.
(String, List<String>) pubspecWithSiblingRefs(
  String pubspec, {
  required Set<String> siblings,
  required String ref,
}) {
  final List<String> lines = pubspec.split('\n');
  final List<String> stamped = <String>[];
  for (final GitDependency dependency in gitDependenciesIn(pubspec)) {
    if (!dependency.isSiblingOf(siblings) || dependency.refLine == null) {
      continue;
    }
    lines[dependency.refLine!] = '${dependency.refIndent}ref: $ref';
    stamped.add(dependency.path!);
  }
  return (lines.join('\n'), stamped);
}

/// The key the line at [line] of [lines] stands inside, or null when it stands inside no bare key.
///
/// It is the nearest line above carrying a SMALLER indent, which is how a block is written: the
/// dependency's name stands one level out from the `git:` inside it. A COMMENT IS STEPPED OVER
/// RATHER THAN READ, because YAML lets one stand at any indent — a `#` line written flush left
/// between the name and the `git:` under it is the nearest smaller indent there is, and one carrying
/// a colon, which an address does, would otherwise be handed back as the name.
String? _enclosingKeyOf(List<String> lines, int line) {
  final int indent = _indentOf(lines[line]);
  for (int above = line - 1; above >= 0; above--) {
    final String content = lines[above].trim();
    if (content.isEmpty || content.startsWith('#') || _indentOf(lines[above]) >= indent) {
      continue;
    }
    if (_valueOf(lines[above]).isNotEmpty) {
      return null;
    }
    final String key = _keyOf(lines[above]);
    return key.isEmpty ? null : key;
  }
  return null;
}

int _indentOf(String line) => line.length - line.trimLeft().length;

String _keyOf(String line) {
  final String content = line.trim();
  final int colon = content.indexOf(':');
  return colon < 0 ? '' : content.substring(0, colon).trim();
}

String _valueOf(String line) {
  final String content = line.trim();
  final int colon = content.indexOf(':');
  return colon < 0 ? '' : content.substring(colon + 1).trim();
}

/// Every line of [pubspec] that writes a git dependency in a shape [gitDependenciesIn] cannot read.
///
/// Two of them, and both are legal `pub`:
///
///   * `git: <url>` on one line. It names no ref, so it follows the default branch of the
///     repository it points at — the same defect as a written-out `ref: master`, wearing no clothes.
///   * a flow mapping, `<name>: {git: {url: ..., ref: ...}}` or `git: {url: ..., ref: ...}`. The
///     whole dependency stands on the name line, so the walk that looks for indented keys under a
///     bare `git:` never opens it.
///
/// Reported as LINES rather than as dependencies, because what is known about them is where they
/// stand and nothing else — reading the ref out of a brace is the parser this program may not have.
List<String> unreadableGitShapesIn(String pubspec) {
  final List<String> lines = pubspec.split('\n');
  final List<String> found = <String>[];
  for (int index = 0; index < lines.length; index++) {
    final String content = lines[index].trim();
    if (content.isEmpty || content.startsWith('#')) {
      continue;
    }
    final String value = _valueOf(lines[index]);
    if (value.isEmpty) {
      continue;
    }
    final bool oneLineGit = _keyOf(lines[index]) == 'git';
    final bool flowMapping = value.startsWith('{') && value.contains('git');
    if (oneLineGit || flowMapping) {
      found.add('line ${index + 1}: $content');
    }
  }
  return found;
}
