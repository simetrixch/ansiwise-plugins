import 'package:ansiwise_api/ansiwise_api.dart';

import 'key_value_file.dart';

/// Fills a `KEY=value` file from the template beside it, with the values this run was given.
///
/// **One capability, however many such files a tree has.** Two rows of one program make two of
/// them here — what the rest of an installation reads about itself, and what its secret store is
/// seeded from — and they differ only in the values on the row: which template, which file, which
/// permissions, which keys, and what the refusals call the subject. They were two classes carrying
/// the same mechanism twice.
///
/// **The key mapping is a named slot per key and never an expression.** A row writes
/// `KEY: {answer: name}`, and where the answer is a list rather than one value it writes
/// `KEY: {answer: name, join: ","}` — one named property of that one entry, because the file has
/// always carried those on one line and what reads it splits on the separator. Nothing here
/// evaluates: a row cannot compose two answers, cannot test one, and cannot write a key the
/// template does not declare.
///
/// **A key that already holds a value is never rewritten**, and a value still equal to the
/// template's own counts as no value at all. The first half is what lets an operator edit the file
/// and keep their edit through every later run; the second is what keeps a file somebody copied and
/// never filled from being read as an answered one.
///
/// **What the plan shows depends on what the row says the file holds.** A row marked as carrying
/// credentials plans the KEYS and never the values, because a plan is read out of the run record.
/// Any other row plans the whole file, because an operator reading it wants to see what they will
/// get. One plan for both would either hide the file or put a credential in a record.
final class FillKeyValueFile extends ReversibleStep<String?> {
  /// The template stands in a checkout that an earlier row of the same program makes, so before
  /// that row has run there is no template to read and nothing to fill.
  ///
  /// Without this, a dry run of a program that clones a tree and then fills its files stops here,
  /// on a machine where nothing has been cloned yet — which is exactly the machine a dry run is
  /// pointed at, and a real run is admitted only where a dry one came back green.
  @override
  bool get restsOnAnEarlierStep => true;

  /// Fills [path] from [templatePath] with [values].
  const FillKeyValueFile({
    required this.templatePath,
    required this.path,
    required this.fileMode,
    required this.subject,
    required this.values,
    required this.holdsCredentials,
  });

  /// Builds the step from what the program gave it.
  factory FillKeyValueFile.fromArguments(Arguments arguments) => FillKeyValueFile(
    templatePath: arguments.text('template_path'),
    path: arguments.text('path'),
    fileMode: arguments.integer('file_mode'),
    subject: arguments.text('subject'),
    values: KeyBinding.readFrom(arguments.raw('values')),
    holdsCredentials: arguments.flag('holds_credentials'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'template_path',
      kind: ArgumentKind.text,
      describes:
          'the file this one is made from, which declares every key it may carry and the '
          'explanation each key stands under',
    ),
    ArgumentSpec(name: 'path', kind: ArgumentKind.text, describes: 'the file that is written'),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      describes:
          'the permissions it is written with, as the number the machine stores — 420 is the '
          'world-readable mode a file holding no credential wants, 384 the owner-only mode one '
          'holding a credential wants',
    ),
    ArgumentSpec(
      name: 'subject',
      kind: ArgumentKind.text,
      describes:
          'what this file holds, in one word, as every refusal of this row will name it — a '
          'credential and a setting are not the same thing to whoever reads the refusal',
    ),
    ArgumentSpec(
      name: 'holds_credentials',
      kind: ArgumentKind.flag,
      required: false,
      defaultValue: false,
      describes:
          'whether a plan of this row shows the KEYS instead of the file, because a plan is read '
          'out of the run record and a record is not where a credential belongs',
    ),
    ArgumentSpec(
      name: 'values',
      kind: ArgumentKind.mapping,
      describes:
          'which answer fills which key, as KEY: {answer: name} — and where the answer holds '
          'several values and the file carries them on one line, KEY: {answer: name, join: ","}',
    ),
  ];

  /// The file this one is made from.
  final String templatePath;

  /// The file that is written.
  final String path;

  /// The permissions it is written with.
  final int fileMode;

  /// What this file holds, as every refusal of this row names it.
  final String subject;

  /// Whether a plan shows the keys instead of the file.
  final bool holdsCredentials;

  /// Which answer fills which key.
  final Map<String, KeyBinding> values;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(templatePath)) {
      return CheckResult.blocked(
        '$templatePath is not there, and it is what this $subject file is made from — every key '
        'stands under the paragraph explaining it, and nothing here writes one the template does '
        'not declare',
      );
    }

    final Map<String, String> wanted = _wanted(context);
    final List<String> unwritable = <String>[
      for (final MapEntry<String, String> each in wanted.entries)
        if (KeyValueFile.holdsQuote(each.value)) each.key,
    ];
    if (unwritable.isNotEmpty) {
      return CheckResult.blocked(
        'these answers hold a double quote or a line break, which this file cannot carry: '
        '${unwritable.join(', ')}',
      );
    }

    final KeyValueFile file = await _read(context);
    final List<String> undeclared = file.missingKeys(wanted.keys);
    if (undeclared.isNotEmpty) {
      return CheckResult.blocked(
        '$templatePath declares no ${undeclared.join(', ')}, so filling one in place would put a '
        'bare assignment at the end of a file whose whole value is that every key stands under its '
        'own explanation',
      );
    }

    // A key the TEMPLATE declares whose line is not in the FILE. Filling happens in place, so
    // there would be no line to rewrite: the write would leave the key out, the check afterwards
    // would say there is still work, and the row would report doing something it did not do. It is
    // refused instead, because a file missing a line its template declares is not a file this
    // template made.
    final List<String> lost = <String>[
      for (final String key in _toFill(file, wanted).keys)
        if (!file.declares(key)) key,
    ];
    if (lost.isNotEmpty) {
      return CheckResult.blocked(
        '$path carries no line for ${lost.join(', ')}, which $templatePath declares — filling '
        'happens in place, so there is nothing here to rewrite. Take the file away and let this '
        'row make it again from the template, or put the line back under its paragraph',
      );
    }

    return _toFill(file, wanted).isEmpty
        ? CheckResult.satisfied('$path states this $subject, and every value in it was answered')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    if (!await context.files.exists(templatePath)) {
      // The same state check refuses, said as a plan rather than thrown. A plan that throws leaves
      // a dry run with nothing to say about this row, and a dry run that cannot say what a row
      // would do is the one outcome the mode exists to prevent.
      return StepPlan.nothing(
        'would fill $path once $templatePath is there — the checkout it stands in is made by an '
        'earlier row',
      );
    }
    final KeyValueFile file = await _read(context);
    final Map<String, String> filling = _toFill(file, _wanted(context));
    if (filling.isEmpty) {
      return StepPlan.nothing('every $subject value this file declares was already answered');
    }
    // A plan is read out of the run record. Where the row says the file holds credentials, what
    // goes in is which keys would be filled — never what they would be filled with.
    return holdsCredentials
        ? StepPlan.nothing('would fill ${filling.keys.join(', ')} in $path')
        : StepPlan.diff(path, before: file.current, after: file.filled(filling));
  }

  @override
  Future<void> apply(StepContext context) async {
    final KeyValueFile file = await _read(context);
    final Map<String, String> filling = _toFill(file, _wanted(context));
    if (filling.isEmpty) {
      return;
    }
    await context.files.write(path, file.filled(filling), mode: fileMode);
  }

  /// The file as it stood, or null where there was none.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(path) ? context.files.read(path) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // There was no such file, so taking this back means the path is gone again. Writing the
      // template back instead would leave a file of empty values that reads as an installation
      // nobody answered for, and returning without touching anything would leave THIS
      // installation's answers standing while the record says the step was taken back.
      await context.files.delete(path);
      return;
    }
    await context.files.write(path, captured, mode: fileMode);
  }

  /// The template and the file as they stand, read as one.
  Future<KeyValueFile> _read(StepContext context) async => KeyValueFile(
    template: await context.files.read(templatePath),
    current: await context.files.exists(path)
        ? await context.files.read(path)
        : await context.files.read(templatePath),
  );

  /// What this run holds, by the key each value belongs under.
  ///
  /// **An answer holding nothing is not a value to write**, and leaving it out is the difference
  /// between a row that finishes and one that never does. These files count an empty value as
  /// unanswered — that is what stops a file somebody copied and never filled from reading as an
  /// answered one — so writing an empty one would leave the key unanswered by the file's own rule,
  /// the check would say there is still work, and the row would report work for ever.
  ///
  /// An answer that is REQUIRED cannot be empty; one that is optional is a value this installation
  /// does not have, and a key it does not have belongs in the file as the template left it.
  Map<String, String> _wanted(StepContext context) => <String, String>{
    for (final MapEntry<String, KeyBinding> each in values.entries)
      if (each.value.valueIn(context.answers) case final String value) each.key: value,
  };

  /// The keys that still need a value, which is every declared key nobody has answered.
  Map<String, String> _toFill(KeyValueFile file, Map<String, String> wanted) => <String, String>{
    for (final MapEntry<String, String> each in wanted.entries)
      if (file.isUnset(each.key)) each.key: each.value,
  };
}

/// Which answer fills one key, and how a list of values is written on one line.
///
/// A row says `KEY: {answer: name}`, or `KEY: {answer: name, join: ","}` where the answer holds
/// several values and the file has always carried them on one line. [join] is a named property of
/// one entry and not an expression: it says which character stands between the values and nothing
/// else. Without it, an answer holding several values is refused rather than written in whatever
/// shape a list happens to print as.
final class KeyBinding {
  /// Binds a key to [answer], written as one line separated by [join] where it holds several.
  const KeyBinding({required this.answer, this.join});

  /// The name of the answer this key is filled from.
  final String answer;

  /// What stands between the values where the answer holds several, or null where it holds one.
  final String? join;

  /// The value this binding puts in the file, or null where this run has nothing to put.
  ///
  /// Null covers BOTH an answer nobody gave and one given empty, because the two mean the same thing
  /// to a file: this installation has no such value. Reading an absent one as a value would throw
  /// where the answer is optional, and writing an empty one would put a key in the file that says
  /// "answered with nothing" — which reads to every later check as answered.
  String? valueIn(Arguments answers) {
    if (!answers.has(answer)) {
      return null;
    }
    final String value = join == null ? answers.text(answer) : answers.textList(answer).join(join!);
    return value.isEmpty ? null : value;
  }

  /// The bindings a row declares, refusing anything that is not one.
  static Map<String, KeyBinding> readFrom(Object? declared) {
    if (declared is! Map<String, Object?>) {
      throw ArgumentError.value(
        declared,
        'values',
        'is a mapping of KEY to {answer: name} and optionally join',
      );
    }
    return <String, KeyBinding>{
      for (final MapEntry<String, Object?> each in declared.entries) each.key: _one(each),
    };
  }

  static KeyBinding _one(MapEntry<String, Object?> entry) {
    final Object? body = entry.value;
    if (body is! Map<String, Object?> || body['answer'] is! String) {
      throw ArgumentError.value(
        body,
        entry.key,
        'names the answer it is filled from, as {answer: name} and optionally join',
      );
    }
    final Object? join = body['join'];
    if (join != null && join is! String) {
      throw ArgumentError.value(join, '${entry.key}.join', 'is the text between several values');
    }
    return KeyBinding(answer: body['answer']! as String, join: join as String?);
  }
}
