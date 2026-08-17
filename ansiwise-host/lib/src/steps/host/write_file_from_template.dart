import 'package:ansiwise_api/ansiwise_api.dart';

import 'fill_key_value_file.dart';

/// Writes a file from a template beside the programs, on every run.
///
/// **The sibling of the create-only writer, and the difference is the whole of it.** That one is
/// finished when the file EXISTS, whatever stands in it, because what stands in it is somebody
/// else's. This one is finished when the file holds what this run renders, so a file saying anything
/// else is rewritten. Use it where the file is a STATEMENT OF THIS RUN — where an answer that
/// changed has to reach the file, and where a hand edit is a difference to correct rather than work
/// to keep.
///
/// **What a rewrite would otherwise destroy is kept by the template, not by this step.** A file of
/// this kind often carries one value nothing here holds: something a later act put there, which a
/// rewrite from answers alone would take back out. The framework's CARRIED slot `<name!>` is that
/// mechanism — it takes its value from the file as it stands, so the rewrite hands the value back
/// untouched. The step needs to know nothing about which value that is, and a template author says
/// it in the one place the value appears.
///
/// **Every slot says which answer fills it.** A slot is spelled with hyphens and an answer with
/// underscores, so matching by name would reach only answers of a single word — and would fail in
/// silence, writing the literal `<slot-name>` into the file for whatever reads it next to take as a
/// value. The row binds them, and the framework refuses both directions: a slot nothing filled, and
/// a value the template has no slot for.
final class WriteFileFromTemplate extends ReversibleStep<String?> with FileStep, TemplateStep {
  /// Writes the file at [path] from the template at [templatePath].
  const WriteFileFromTemplate({
    required this.templatePath,
    required this.path,
    required this.fileMode,
    this.runAnswer,
    this.values = const <String, KeyBinding>{},
  });

  /// Builds the step from what the program gave it.
  factory WriteFileFromTemplate.fromArguments(Arguments arguments) => WriteFileFromTemplate(
    templatePath: arguments.text('template'),
    path: arguments.text('path'),
    fileMode: arguments.integer('file_mode'),
    runAnswer: arguments.optionalText('run_answer'),
    values: arguments.has('values')
        ? KeyBinding.readFrom(arguments.raw('values'))
        : const <String, KeyBinding>{},
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
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.text,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in the '
          'path — write "fqdn" here and every "<fqdn>" in the path is filled with this run\'s '
          'domain. Leave it off where there is no such axis',
      required: false,
    ),
    ArgumentSpec(
      name: 'values',
      kind: ArgumentKind.mapping,
      describes:
          'which answer fills each slot of the template, as `slot-name: {answer: name}` and '
          'optionally `join` where the answer holds several values',
      required: false,
    ),
  ];

  /// Where the template stands, as the row names it.
  @override
  final String templatePath;

  /// Where the file goes, before any slot in it is filled.
  final String path;

  /// The permissions the file ends up with.
  final int fileMode;

  /// The name of the answer whose value fills the slot of the same name in the PATH.
  final String? runAnswer;

  /// Which answer fills each slot of the template.
  final Map<String, KeyBinding> values;

  @override
  String pathFor(StepContext context) {
    if (runAnswer case final String name) {
      if (context.answers.optionalText(name) case final String value) {
        return filledSlots(path, <String, String>{name: value});
      }
    }
    return path;
  }

  @override
  int get mode => fileMode;

  @override
  Future<FileContent> contentFor(StepContext context) async {
    // An answer holding nothing is left out rather than filled in empty, so an OPTIONAL slot's line
    // is dropped by the framework instead of being written with nothing after it. That is the
    // difference between a key this installation has no value for and one it has an empty value
    // for, and only the second is a value.
    final Map<String, String> filled = <String, String>{
      for (final MapEntry<String, KeyBinding> each in values.entries)
        if (each.value.valueIn(context.answers) case final String value) each.key: value,
    };

    return FileContent.text(await renderedWith(context, filled));
  }

  /// What the file held before, or null when it was not there.
  @override
  Future<String?> capture(StepContext context) => contentBefore(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // There was no file, so taking this back means the path is gone again. Returning here would
      // leave this run's values standing while the record says the step was taken back.
      await context.files.delete(pathFor(context));
      return;
    }
    await context.files.write(pathFor(context), captured, mode: mode);
  }
}
