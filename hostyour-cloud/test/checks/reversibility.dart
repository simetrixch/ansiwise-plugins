/// reversibility — every step answers "can this be taken back", and an irreversible one says why.
///
/// THE FIRST HALF IS ALREADY THE COMPILER'S, and it is checked anyway. `Step` has a private
/// constructor, so it can be extended only through `ReversibleStep`, `IrreversibleStep` or
/// `ObservingStep`, and the compiler refuses anything else. The day that constructor stops being
/// private the compiler stops asking, and a step that answers neither would arrive silently — with a
/// dry run that no longer knows whether it has passed the point of no return. This is what notices.
///
/// THE SECOND HALF IS NOT ANYBODY'S. `irreversibleReason` is a string, and any string compiles. It is
/// what the dry run shows an operator when it names the point beyond which there is no going back, so
/// it has to say what about the change cannot be reversed — not that no undo was written. "No undo
/// implemented" tells the operator nothing they can weigh; "the address pool a running cluster is
/// using is gone, and what is lost is state nothing wrote down" tells them everything. A placeholder
/// is therefore a finding, and it is a finding precisely because it compiles and reads like an answer.
///
/// The reason is read off the built object rather than out of the source, because it is a getter and
/// may be composed: [RegistryReading] reports what the step would actually show.
library;

import 'finding.dart';
import 'registry_completeness.dart';
import 'registry_reading.dart';
import 'source_tree.dart';

/// What an operator learns nothing from.
///
/// Each of these says that no undo was written, or says nothing at all; none of them says what about
/// the change cannot be taken back. Matched against the WHOLE reason, because the failure is a reason
/// CONSISTING of one of these rather than one mentioning it: "the packages are gone and putting them
/// back would mean guessing" is a real answer and contains the word guessing, and "not implemented"
/// is not an answer however it is capitalised.
const Set<String> placeholderReasons = <String>{
  '-',
  'na',
  'n/a',
  'none',
  'null',
  'todo',
  'tbd',
  'fixme',
  'unknown',
  'unimplemented',
  'not implemented',
  'no undo',
  'no undo implemented',
  'no undo written',
  'undo not implemented',
  'not reversible',
  'irreversible',
  'cannot be undone',
  'can not be undone',
  "can't be undone",
  'no rollback',
  'nothing to undo',
  'see above',
};

/// The three classes a step may extend, and the only ones allowed to extend `Step` itself.
const Set<String> theThreeKinds = <String>{'ReversibleStep', 'IrreversibleStep', 'ObservingStep'};

/// The check itself, over a tree and a registry it is given.
final class Reversibility {
  /// Judges [reading] against [tree].
  const Reversibility({required this.tree, required this.reading});

  /// The tree the classes are read from.
  final SourceTree tree;

  /// The registry as a running program sees it.
  final RegistryReading reading;

  /// Every irreversible entry, for the count a person reads beside the verdict.
  List<RegistryEntry> get irreversibleEntries => <RegistryEntry>[
    for (final RegistryEntry entry in reading.entries)
      if (entry.kind == StepKind.irreversible) entry,
  ];

  /// Every class in this tree extending `Step` itself.
  List<DeclaredStepClass> get directExtensions => classesExtendingStepItself(tree);

  /// Everything wrong with what the steps of this tree say about being taken back.
  List<Finding> get findings => <Finding>[
    ...reading.problems,
    ..._kindFindings,
    ..._reasonFindings,
    for (final DeclaredStepClass declared in directExtensions)
      Finding(
        declared.path,
        '${declared.className} extends Step itself, and the choice between reversible, irreversible '
        'and observing is what a dry run reads',
        line: declared.line,
      ),
  ];

  List<Finding> get _kindFindings => <Finding>[
    for (final RegistryEntry entry in reading.entries)
      if (entry.kind == StepKind.unknown)
        Finding(
          entry.name,
          '${entry.className} extends Step itself rather than ReversibleStep, IrreversibleStep or '
          'ObservingStep, so nothing says whether it can be taken back',
        ),
  ];

  List<Finding> get _reasonFindings => <Finding>[
    for (final RegistryEntry entry in irreversibleEntries)
      if (entry.irreversibleReason.trim().isEmpty)
        Finding(
          entry.name,
          'it cannot be taken back and its irreversibleReason is empty, so a dry run names the '
          'point of no return without saying what is lost',
        )
      else if (reasonIsAPlaceholder(entry.irreversibleReason))
        Finding(
          entry.name,
          'its irreversibleReason is "${entry.irreversibleReason}" — that says no undo was written, '
          'not what about the change cannot be reversed',
        ),
  ];
}

/// Whether [reason] tells an operator nothing.
///
/// A trailing full stop or exclamation mark is taken off first, so "cannot be undone." is the same
/// non-answer as "cannot be undone".
bool reasonIsAPlaceholder(String reason) {
  final String plain = reason.trim().toLowerCase().replaceAll(_trailingPunctuation, '');
  return plain.isEmpty || placeholderReasons.contains(plain);
}

/// Every class in [tree] extending `Step` itself, sorted by where it sits.
///
/// The three kinds are left out: they are what the private constructor exists to be extended
/// through. A class whose name begins with an underscore is INCLUDED — it cannot be registered, but
/// extending `Step` directly is a defect wherever it is written.
List<DeclaredStepClass> classesExtendingStepItself(SourceTree tree) {
  final List<DeclaredStepClass> found = <DeclaredStepClass>[];
  for (final String path in tree.dartFiles) {
    final String? text = tree.textOf(path);
    if (text == null) {
      continue;
    }
    final List<String> lines = linesOf(text);
    for (int i = 0; i < lines.length; i++) {
      if (_extendsStepItself.firstMatch(lines[i])?.group(1) case final String className) {
        if (theThreeKinds.contains(className)) {
          continue;
        }
        found.add(DeclaredStepClass(path: path, line: i + 1, className: className));
      }
    }
  }
  return found;
}

final RegExp _trailingPunctuation = RegExp(r'[.!]$');

final RegExp _extendsStepItself = RegExp(
  r'^\s*(?:abstract\s+)?(?:base|final|sealed)?\s*class\s+(_?[A-Za-z][A-Za-z0-9_]*)\s+extends\s+Step\s*(?:\{|$)',
);
