import 'package:ansiwise_api/ansiwise_api.dart';
import 'fill_key_value_file.dart';

/// Puts a file on the machine from a template beside the programs, and never overrules one that is
/// already there.
///
/// **Create-only is the whole of what tells this apart from the writers beside it.** They are
/// finished when the file holds what this run would render, so a file saying anything else is
/// rewritten. This one is finished when the file EXISTS, whatever stands in it. It is the step for a
/// file whose first version comes from whoever deploys and whose later versions come from whoever
/// operates the machine: the rows somebody added afterwards are the whole value of such a file, they
/// are nowhere else, and a step comparing content against what it renders reads them as a difference
/// to correct.
///
/// **What the file HOLDS is therefore not looked at.** That is not an omission, it is the
/// postcondition: the file being there, and the operator not having been overruled.
///
/// **The path may be named per run.** A machine can want one such file per stage, per region or per
/// customer, and what that axis is CALLED belongs to whoever runs this — so the path may carry a
/// marked slot and the row says which answer fills it. Where there is no such axis the row leaves
/// that off and the path stands as written. A slot nothing filled is refused rather than sent: a
/// path still carrying angle brackets would put a file on the machine under a name no reader of it
/// ever looks for.
final class CreateFileFromTemplate extends ReversibleStep<bool> with FileStep, TemplateStep {
  /// Creates the file at [path] from the template at [templatePath], where there is none.
  const CreateFileFromTemplate({
    required this.templatePath,
    required this.path,
    required this.fileMode,
    this.runAnswer,
    this.values = const <String, KeyBinding>{},
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory CreateFileFromTemplate.fromArguments(Arguments arguments) => CreateFileFromTemplate(
    templatePath: arguments.text('template'),
    path: arguments.text('path'),
    fileMode: arguments.integer('file_mode'),
    runAnswer: arguments.optionalText('run_answer'),
    values: arguments.has('values')
        ? KeyBinding.readFrom(arguments.raw('values'))
        : const <String, KeyBinding>{},
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'template',
      kind: ArgumentKind.text,
      describes:
          'the file as text, beside the programs of this installation. It may carry a marked slot '
          'wherever a value belongs that only a run holds',
    ),
    // No default for any of the three below. Where such a file goes, and what may read it, is
    // decided by whatever the file is for — a default here would be this package deciding it for
    // every product that ever calls the step.
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'where the file goes on this machine, which may carry the slot named by run_answer so '
          'that one row makes one such file per run',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      describes:
          'the permissions the file is written with, as the number the machine stores — 420 is the '
          'mode of a file anyone on the machine may read, 384 of one only its owner may',
    ),
    // The one axis a caller may want one such file per run along, and the reason it is NAMED rather
    // than known: a file system has no such axis. A product with three environments wants one file
    // per environment, one with three regions wants one per region, and one with neither wants a
    // single file — so what the axis is called is the caller's, and a name written into this
    // package would make every vendor carry that one.
    //
    // Absent is a first-class case and not a mistake: with nothing here, no part of the path is
    // filled from an answer, and a path still carrying angle brackets is refused rather than used.
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.text,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in the '
          'path — write "stage" here and every "<stage>" in the path is filled with this run\'s '
          'stage. Leave it off where there is no such axis',
      required: false,
    ),
    // WHY A SLOT IS BOUND AND NEVER MATCHED BY NAME. A slot is spelled with hyphens
    // (`<build-plane>`) and an answer with underscores (`build_plane`), and the grammar forbids the
    // underscore on purpose so that no name has two spellings. Looking an answer up by the slot's
    // own name therefore reaches only answers of a single word, and the failure is silent: the
    // template names a slot, nothing fills it, and the seven literal characters go into the file
    // for whatever reads it next to take as a value. Saying which answer fills which slot is one
    // named slot standing for exactly one value, which is a mechanism and not an expression.
    ArgumentSpec(
      name: 'values',
      kind: ArgumentKind.mapping,
      describes:
          'which answer fills each slot of the template, as `slot-name: {answer: name}` and '
          'optionally `join` where the answer holds several values',
      required: false,
    ),
    // ASKED, never assumed. Whether the file this row points at belongs to root is a property of
    // that PATH, and this step is pointed at one by its row. A step deciding it for every caller
    // would be a tool package knowing something about the product that pointed it.
    ArgumentSpec(
      name: 'elevated',
      kind: ArgumentKind.flag,
      describes:
          'whether the file belongs to root, so reading and writing it need elevation. Leave it '
          'off for a path this account owns',
      required: false,
    ),
  ];

  /// Where the template stands, as the row names it.

  /// Whether the file belongs to root, so every read and write of it is elevated.
  @override
  final bool elevated;
  @override
  final String templatePath;

  /// Where the file goes, before any slot in it is filled.
  final String path;

  /// The permissions the file ends up with.
  final int fileMode;

  /// The name of the answer whose value fills the slot of the same name, or null where there is
  /// none.
  ///
  /// The PATH and not the content, and matched by name rather than bound, because a path carries at
  /// most this one axis and the row names the answer outright.
  final String? runAnswer;

  /// Which answer fills each slot of the template.
  final Map<String, KeyBinding> values;

  @override
  String pathFor(StepContext context) {
    if (runAnswer case final String name) {
      // Read as optional and left unfilled where the run holds no such answer, so ONE refusal
      // covers both a misspelled slot and an answer nobody gave — and it names what is still open
      // instead of throwing about a name the reader has to go and look up.
      if (context.answers.optionalText(name) case final String value) {
        return filledSlots(path, <String, String>{name: value});
      }
    }
    return path;
  }

  @override
  int get mode => fileMode;

  /// The rendered file, on a machine that does not have one yet.
  ///
  /// A machine that already carries the file needs nothing written, and it needs no template read
  /// either — which is why the two questions are answered together here rather than the template
  /// being read first and then discarded.
  @override
  Future<FileContent> contentFor(StepContext context) async {
    final String where = pathFor(context);
    if (await context.files.exists(where)) {
      return FileContent.nothing(
        '$where is on this machine, and what stands in it is not this '
        'step\'s to decide',
      );
    }
    if (!await context.files.exists(templatePath)) {
      throw TemplateRefused(
        '$templatePath is not where this run was started, and it is the text this step writes — a '
        'template travels with the programs of its installation, and nothing here composes the '
        'file without one',
      );
    }
    // An answer holding nothing is left out rather than filled in empty, so an OPTIONAL slot's line
    // is dropped by the framework instead of being written with nothing after it. A REQUIRED slot
    // nobody answered is refused there by name, which is the whole reason the two kinds differ.
    final Map<String, String> filled = <String, String>{
      for (final MapEntry<String, KeyBinding> each in values.entries)
        if (each.value.valueIn(context.answers) case final String value) each.key: value,
    };

    return FileContent.text(await renderedWith(context, filled));
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    if (leftoverSlotIn(pathFor(context)) case final String left) {
      return CheckResult.blocked(_unfilled(left));
    }
    return super.check(context);
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    // Answered rather than thrown. A plan is what an operator reads to decide whether to let the
    // run happen, and a plan that failed to be produced tells them nothing about what would be done
    // — including that the thing standing in the way is a name nothing filled.
    if (leftoverSlotIn(pathFor(context)) case final String left) {
      return StepPlan.nothing(_unfilled(left));
    }
    return super.plan(context);
  }

  /// Whether the machine already carried this file before the run.
  ///
  /// The whole of what a create-only step's undo needs: a file that was already there is somebody
  /// else's, whatever it holds, and this step wrote nothing over it. Reading the content afterwards
  /// cannot answer that — a file an earlier run created holds exactly what this step renders, and
  /// taking a run back is not a licence to delete a file it did not create.
  @override
  Future<bool> capture(StepContext context) => context.files.exists(pathFor(context));

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.files.delete(pathFor(context));
  }

  /// What is said about a path that still names something nothing filled.
  String _unfilled(String left) =>
      'the path "$path" still carries $left, and nothing this run holds fills it — a file written '
      'under that name is a file no reader of it ever looks for';
}
