import 'package:ansiwise_core/ansiwise_core.dart';

import '../declaration.dart';
import '../stamping.dart';
import '../trees.dart';

/// Writes every pin of one declaration into every file the declaration says carries it.
///
/// The declaration is the ONE place a version is decided; without this step, changing it there
/// changes nothing, and a person carries the value by hand into every chart, manifest and build
/// argument that states it. This step is that carrying, made mechanical: each component's version
/// is written into each of its declared stamp sites, surgically, so comments and formatting stay
/// and `diff` afterwards shows exactly the version tokens that moved.
///
/// **Every site must be found, or the run stops.** A stamper that skips what it cannot find
/// reports success over a pin that went nowhere — measured on a chart dependency, and on a build
/// argument in a sibling repository whose miss would have frozen an image's clients at whatever the
/// file said that day. So an anchor that is missing, a file that
/// is not there, and a tree label the row did not map are each a refusal naming everything wrong
/// at once, before anything is written.
///
/// **The trees are the row's to map.** The declaration names its trees by label; where those
/// checkouts stand on this machine is answered per run or stated by the row, never known here.
/// One of the trees usually is a SIBLING repository — the declaration decides a version whose
/// build lives elsewhere and cannot read across the boundary — and stamping it from here is what
/// keeps that file from becoming a second source for a version that must have exactly one.
///
/// **What this step does not do is deliver.** It leaves the checkouts changed and nothing more:
/// reviewing the diff and committing it is the operator's, in each repository's own workflow. That
/// is also what the undo restores — the files as they were, read before the first write.
final class StampVersionPins extends ReversibleStep<Map<String, String>> {
  /// Stamps the pins of the declaration at [declarationPath] in tree [declarationTree].
  const StampVersionPins({
    required this.declarationTree,
    required this.declarationPath,
    required this.trees,
    required this.fileMode,
  });

  /// Builds the step from what the program gave it.
  factory StampVersionPins.fromArguments(Arguments arguments) => StampVersionPins(
    declarationTree: arguments.text('declaration_tree'),
    declarationPath: arguments.text('declaration_path'),
    trees: TreeBinding.readFrom(arguments.raw('trees')),
    fileMode: arguments.integer('file_mode'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'declaration_tree',
      kind: ArgumentKind.text,
      describes:
          'the label of the tree the declaration file lives in — a label the trees mapping below '
          'binds, because the declaration is a file of one of the checkouts like any other',
    ),
    ArgumentSpec(
      name: 'declaration_path',
      kind: ArgumentKind.text,
      describes: 'the declaration file inside that tree, which decides every version this stamps',
    ),
    ArgumentSpec(
      name: 'trees',
      kind: ArgumentKind.mapping,
      describes:
          'where each tree label the declaration writes stands on this machine, as '
          'LABEL: {answer: name} where the operator answers per run, or LABEL: {path: /srv/tree} '
          'where an installation keeps the checkout in one known place',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 0,
        most: 4095,
        because:
            'a permission mode is twelve bits, so 4095 is 0o7777 and nothing outside it is a mode',
      ),
      required: false,
      defaultValue: 420,
      describes:
          'the permissions a stamped file is written back with, as the number the machine '
          'stores — 420 is the world-readable mode a tracked source file wants',
    ),
  ];

  /// The label of the tree the declaration lives in.
  final String declarationTree;

  /// The declaration file inside that tree.
  final String declarationPath;

  /// Where each tree label stands, by path or by the name of the answer that holds it.
  final Map<String, TreeBinding> trees;

  /// The permissions a stamped file is written back with.
  final int fileMode;

  @override
  Future<Map<String, String>> capture(StepContext context) async {
    final _Survey survey = await _survey(context);
    return <String, String>{
      for (final MapEntry<String, _FileEdit> each in survey.edits.entries)
        each.key: each.value.original,
    };
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Survey survey = await _survey(context);
    if (survey.problems.isNotEmpty) {
      return CheckResult.blocked(
        'the declaration and the trees disagree, and nothing was written:\n'
        '  ${survey.problems.join('\n  ')}',
      );
    }
    for (final String stands in survey.already) {
      context.log.debug('already stamped: $stands');
    }
    if (survey.edits.isEmpty) {
      return CheckResult.satisfied(
        'every pin of $declarationPath already stands in every file its stamps name '
        '(${survey.already.length} site(s))',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final _Survey survey = await _survey(context);
    final List<String> was = <String>[];
    final List<String> becomes = <String>[];
    for (final MapEntry<String, _FileEdit> each in survey.edits.entries) {
      for (final String line in each.value.was) {
        was.add('${each.key}: $line');
      }
      for (final String line in each.value.becomes) {
        becomes.add('${each.key}: $line');
      }
    }
    // One step here rewrites several files and a plan carries one path, so the path is the
    // declaration that decides the values, and the difference is the set of lines that change —
    // which is what an operator reads a plan for.
    return StepPlan.diff(declarationPath, before: was.join('\n'), after: becomes.join('\n'));
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Survey survey = await _survey(context);
    if (survey.problems.isNotEmpty) {
      // The engine applies a step only after its check answered ready, and that check refuses
      // these by name — so reaching here is a call out of order, and writing anyway would stamp
      // half a declaration.
      throw StateError(survey.problems.join('; '));
    }
    for (final MapEntry<String, _FileEdit> each in survey.edits.entries) {
      await context.files.write(each.key, each.value.content, mode: fileMode);
      for (int i = 0; i < each.value.was.length; i++) {
        context.log.info('${each.key}: "${each.value.was[i]}" is now "${each.value.becomes[i]}"');
      }
    }
  }

  @override
  Future<void> undo(StepContext context, Map<String, String> captured) async {
    for (final MapEntry<String, String> each in captured.entries) {
      await context.files.write(each.key, each.value, mode: fileMode);
      context.log.info('${each.key}: put back as it was before the stamp');
    }
  }

  /// Every stamp of the declaration held against the trees as this run reaches them.
  ///
  /// Several stamps may write into ONE file — a build file carries three of these pins, a program
  /// file five — so the survey threads each file's content through its stamps in declaration
  /// order, and the file is read once and written once.
  Future<_Survey> _survey(StepContext context) async {
    final List<String> problems = <String>[];
    final List<String> already = <String>[];
    final Map<String, _FileEdit> edits = <String, _FileEdit>{};

    final ({Map<String, String>? roots, List<String> problems}) resolved = resolveTrees(
      trees,
      context.answers,
    );
    final Map<String, String>? roots = resolved.roots;
    if (roots == null) {
      return _Survey(problems: resolved.problems, already: already, edits: edits);
    }

    final String? declarationRoot = roots[declarationTree];
    if (declarationRoot == null) {
      problems.add(
        'the declaration lives in tree "$declarationTree", and the trees mapping of this row '
        'binds no such label',
      );
      return _Survey(problems: problems, already: already, edits: edits);
    }
    final String source = underTree(declarationRoot, declarationPath);
    if (!await context.files.exists(source)) {
      problems.add('$source is not there, and it is the declaration everything here stamps from');
      return _Survey(problems: problems, already: already, edits: edits);
    }
    final VersionsDeclaration declaration;
    try {
      declaration = parseDeclaration(await context.files.read(source), where: source);
    } on DeclarationInvalid catch (broken) {
      problems.add(broken.toString());
      return _Survey(problems: problems, already: already, edits: edits);
    }

    for (final PinnedComponent component in declaration.components) {
      for (final PinStamp stamp in component.stamps) {
        final String? root = roots[stamp.tree];
        if (root == null) {
          problems.add(
            '${component.label} is stamped into tree "${stamp.tree}", and the trees mapping of '
            'this row binds no such label',
          );
          continue;
        }
        final String path = underTree(root, stamp.file);
        _FileEdit? edit = edits[path];
        if (edit == null) {
          if (!await context.files.exists(path)) {
            problems.add(
              '$path is not there, and ${component.label} says its pin is written in it',
            );
            continue;
          }
          final String original = await context.files.read(path);
          edit = _FileEdit(original);
        }
        switch (stampInto(edit.content, stamp, stamp.valueOf(component.version))) {
          case StampStands(:final String at):
            already.add('$path: $at');
            if (edit.was.isNotEmpty) {
              edits[path] = edit;
            }
          case StampReady(:final String content, :final String was, :final String becomes):
            edit.content = content;
            edit.was.add(was);
            edit.becomes.add(becomes);
            edits[path] = edit;
          case StampRefused(:final String reason):
            problems.add('${component.label}: $path $reason');
        }
      }
    }
    return _Survey(problems: problems, already: already, edits: edits);
  }
}

/// One file's pass through every stamp that names it.
final class _FileEdit {
  _FileEdit(this.original) : content = original;

  /// What the file held before the first stamp.
  final String original;

  /// What it holds after the stamps so far.
  String content;

  /// The lines that change, as they stand.
  final List<String> was = <String>[];

  /// The same lines, as they will stand.
  final List<String> becomes = <String>[];
}

final class _Survey {
  const _Survey({required this.problems, required this.already, required this.edits});

  /// Everything that keeps this stamp from being carried out, all at once.
  final List<String> problems;

  /// The sites that already carry their pin.
  final List<String> already;

  /// The files that do not, each with its rewritten content.
  final Map<String, _FileEdit> edits;
}
