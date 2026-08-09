/// registry-completeness — the registry and the classes on disk say the same thing.
///
/// Dart compiled ahead of time has no reflection, so the map from the names a program file writes to
/// the classes that implement them is written out by hand. That is not a workaround, it is what makes
/// this check possible: a registry that is written is a registry that can be counted against the tree
/// in both directions. No step exists unregistered, and no entry points at a class that is gone.
///
/// THE THIRD DIRECTION IS THE `source:` OF EACH ENTRY, and it is the one that rots. It is the file
/// and line the record reports and the operator opens when a step fails, and nothing about it is
/// checked by a compiler: insert four lines above a class and the number is wrong, with no symptom
/// until somebody follows it at the worst moment of a deployment and lands in the middle of another
/// step. So the file has to exist, the line has to hold that class's declaration, and the path has to
/// be relative to the repository root — which is what the record's reader resolves it against.
library;

import 'finding.dart';
import 'registry_reading.dart';
import 'source_tree.dart';

/// Where a step class belongs, relative to the repository root.
const String stepsDirectory = 'lib/src/steps';

/// One step class as it is declared on disk.
final class DeclaredStepClass {
  /// Records a declaration found at [line] of [path].
  const DeclaredStepClass({required this.path, required this.line, required this.className});

  /// The repository-relative file it is declared in.
  final String path;

  /// The line the declaration sits on, counted from one.
  final int line;

  /// The name of the class.
  final String className;
}

/// The check itself, over a tree and a registry it is given.
final class RegistryCompleteness {
  /// Judges [reading] against [tree].
  const RegistryCompleteness({required this.tree, required this.reading});

  /// The tree the classes are read from.
  final SourceTree tree;

  /// The registry as a running program sees it.
  final RegistryReading reading;

  /// Every step class declared under [stepsDirectory], sorted by where it sits.
  ///
  /// `abstract` is left out because an abstract class cannot be instantiated, so no entry could build
  /// one; a class whose name begins with an underscore is left out because the registry file imports
  /// the step's file and a private class is not visible across that boundary. Everything else
  /// declared there and extending something whose name ends in `Step` is a step, whether it extends
  /// one of the three kinds directly or a base class written between.
  List<DeclaredStepClass> get classesOnDisk => stepClassesIn(tree, under: stepsDirectory);

  /// Everything the registry and the tree disagree about.
  List<Finding> get findings => <Finding>[
    ...reading.problems,
    for (final RegistryEntry entry in reading.entries)
      ..._sourceFindingsFor(
        entry.name,
        source: entry.source,
        className: entry.className,
        declaredWith: extendsAKind,
      ),
    // A predicate is registered as one instance rather than as a factory, so its class is read off
    // that instance. Its source is what the plan sends an operator to when a condition skipped the
    // steps they were waiting for, and it rots exactly the way a step's does.
    for (final PredicateEntry entry in reading.predicates) ...<Finding>[
      ..._sourceFindingsFor(
        entry.name,
        source: entry.source,
        className: entry.className,
        declaredWith: implementsAnInterface,
      ),
      if (entry.describes.trim().isEmpty)
        Finding(
          entry.name,
          'it describes nothing, and what it describes is the line the operator reads in the plan '
          'beside the steps this predicate switched off',
        ),
    ],
    ..._unregisteredFindings,
  ];

  /// Everything wrong with one entry's `source`.
  List<Finding> _sourceFindingsFor(
    String name, {
    required String source,
    required String className,
    required String declaredWith,
  }) {
    if (!sourceIsRepositoryRelative(source)) {
      return <Finding>[
        Finding(name, 'its source "$source" is not a path relative to the repository root'),
      ];
    }

    final int cut = source.lastIndexOf(':');
    if (cut < 0) {
      return <Finding>[
        Finding(
          name,
          'its source "$source" carries no line number, and the record points at a line',
        ),
      ];
    }

    final String path = source.substring(0, cut);
    final int? line = int.tryParse(source.substring(cut + 1));
    if (line == null) {
      return <Finding>[
        Finding(name, 'its source "$source" ends in something that is not a line number'),
      ];
    }
    if (tree.textOf(path) == null) {
      return <Finding>[
        Finding(name, 'its source names $path, and there is no such text file in this repository'),
      ];
    }
    if (!declaresClass(
      tree,
      path: path,
      line: line,
      className: className,
      declaredWith: declaredWith,
    )) {
      return <Finding>[
        Finding(
          name,
          'its source says $path:$line, and that line does not declare '
          '"final class $className $declaredWith"',
        ),
      ];
    }
    return const <Finding>[];
  }

  List<Finding> get _unregisteredFindings {
    final Set<String> registered = reading.classNames;
    return <Finding>[
      for (final DeclaredStepClass declared in classesOnDisk)
        if (!registered.contains(declared.className))
          Finding(
            declared.path,
            'no registry entry builds ${declared.className}, so no program file can name it',
            line: declared.line,
          ),
    ];
  }
}

/// Whether [source] is a path this repository can resolve.
///
/// An absolute path is one machine's, a drive letter is one operating system's, and `..` climbs out
/// of the tree — all three read fine in a record and none of them opens anywhere else.
bool sourceIsRepositoryRelative(String source) {
  if (source.startsWith('/') || source.startsWith('../')) {
    return false;
  }
  if (_driveLetter.hasMatch(source) || source.contains('/../')) {
    return false;
  }
  return true;
}

/// How a step's class is declared: it extends one of the three kinds.
const String extendsAKind = 'extends';

/// How a predicate's class is declared: it implements the interface.
const String implementsAnInterface = 'implements';

/// Whether [line] of [path] declares [className], read from the file itself.
///
/// `final class <Name> <declaredWith>` and nothing looser. A step is a final class extending one of
/// the three kinds and a predicate is a final class implementing `Predicate`, so this is the whole
/// shape of the declaration; matching a bare `class <Name>` would accept the doc comment above it,
/// and matching the name alone would accept any line that mentions it.
///
/// The `extends` may stand on the FOLLOWING line, because `dart format` moves it there once the
/// class name and its type argument no longer fit in one line — `ConfigureSlaveApiserverOidcTrust`
/// captures a record of two things and does not fit. Which line it lands on is the formatter's
/// decision and says nothing about the code, so a check that failed on it would be reporting the
/// line width.
bool declaresClass(
  SourceTree tree, {
  required String path,
  required int line,
  required String className,
  String declaredWith = extendsAKind,
}) {
  final String? text = tree.textOf(path);
  if (text == null) {
    return false;
  }
  final List<String> lines = linesOf(text);
  if (line < 1 || line > lines.length) {
    return false;
  }
  // Leading whitespace off, so a class that is one day nested reads the same as one at the margin.
  final String declaration = lines[line - 1].trimLeft();
  if (declaration.startsWith('final class $className $declaredWith')) {
    return true;
  }
  // The wrapped form, and only where the name stands alone on the line — `final class Foo` must not
  // be accepted as the declaration of `FooBar`.
  return declaration == 'final class $className' &&
      line < lines.length &&
      lines[line].trimLeft().startsWith('$declaredWith ');
}

/// Every step class declared under [under] in [tree], sorted by where it sits.
List<DeclaredStepClass> stepClassesIn(SourceTree tree, {required String under}) {
  final List<DeclaredStepClass> found = <DeclaredStepClass>[];
  for (final String path in tree.dartFiles) {
    if (under.isNotEmpty && !path.startsWith('$under/')) {
      continue;
    }
    final String? text = tree.textOf(path);
    if (text == null) {
      continue;
    }
    final List<String> lines = linesOf(text);
    for (int i = 0; i < lines.length; i++) {
      if (_stepDeclaration.firstMatch(lines[i])?.group(1) case final String className) {
        found.add(DeclaredStepClass(path: path, line: i + 1, className: className));
      }
    }
  }
  return found;
}

final RegExp _driveLetter = RegExp(r'^[A-Za-z]:');

final RegExp _stepDeclaration = RegExp(
  r'^\s*(?:base|final|sealed)?\s*class\s+([A-Za-z][A-Za-z0-9_]*)\s+extends\s+[A-Za-z0-9_]*Step\s*\{?\s*$',
);
