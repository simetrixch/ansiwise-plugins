import 'package:ansiwise_core/ansiwise_core.dart';

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
/// **A key an ANSWER names is written from that answer whenever the two differ; a key no answer
/// names is never touched.** So an operator's hand edit survives every later run — unless they
/// edited a key the run is also told, which was never a place to edit it: the next run was always
/// going to be told the answer and not read the file. A value still equal to the template's own
/// counts as no value at all, which keeps a file somebody copied and never filled from being read
/// as an answered one.
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
    this.runAnswer,
    required this.fileMode,
    required this.subject,
    required this.values,
    required this.holdsCredentials,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory FillKeyValueFile.fromArguments(Arguments arguments) => FillKeyValueFile(
    templatePath: arguments.text('template_path'),
    path: arguments.text('path'),
    runAnswer: arguments.optionalText('run_answer'),
    fileMode: arguments.integer('file_mode'),
    subject: arguments.text('subject'),
    values: KeyBinding.readFrom(arguments.raw('values')),
    holdsCredentials: arguments.flag('holds_credentials'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in '
          'the path — write "stage" here and a "<stage>" in the path is filled with the '
          'stage this run holds. Leave it off where the file is named the same on every '
          'installation',
    ),
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
          'where each key\'s value comes from: KEY: {answer: name} for a value this run holds, or '
          'KEY: {file: path, key: name} for one a settings file on this machine records — and '
          'where the source holds several values and the file carries them on one line, '
          'join: "," beside it. A file named per installation carries a slot and names the answer '
          'that fills it: {file: "configs/config.<stage>", key: name, run_answer: stage}',
    ),
    elevationArgument,
  ];

  /// The file this one is made from.
  final String templatePath;

  /// The file that is written.
  final String path;

  /// WHICH answer fills the slot spelled the same way in [path], or null where it carries none.
  ///
  /// **The file an installation states itself in is named for its stage, and the stage is a suffix
  /// and never a folder.** A row pointed at `configs/config.dev` writes the right file on exactly
  /// one installation; pointed at `configs/config.<stage>` with this naming `stage`, it writes the
  /// right one on all of them. The mechanism is the one the template writers in this package
  /// already carry, under the same argument name.
  final String? runAnswer;

  /// [path] with the slot filled from this run, or [path] itself where this row names no answer.
  String pathFor(StepContext context) {
    if (runAnswer case final String name) {
      if (context.answers.optionalText(name) case final String value) {
        return filledSlots(path, <String, String>{name: value});
      }
    }
    return path;
  }

  /// The permissions it is written with.
  final int fileMode;

  /// What this file holds, as every refusal of this row names it.
  final String subject;

  /// Whether a plan shows the keys instead of the file.
  final bool holdsCredentials;

  /// Which answer fills which key.
  final Map<String, KeyBinding> values;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  Future<CheckResult> check(StepContext context) async {
    final String path = pathFor(context);
    if (!await context.files.exists(templatePath, elevated: elevated)) {
      return CheckResult.blocked(
        '$templatePath is not there, and it is what this $subject file is made from — every key '
        'stands under the paragraph explaining it, and nothing here writes one the template does '
        'not declare',
      );
    }

    final Map<String, String> wanted = await _wanted(context);
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

    // A KEY THE TEMPLATE GAINED AFTER THIS FILE WAS MADE. Keys are added as the product is built,
    // and the file of an installation made before one was added simply has no line for it. Nothing
    // reported that: the refusal above only ever looked at keys THIS RUN fills, and the keys an
    // operator fills by hand — most of this file — went unexamined. Whatever needed one read
    // nothing, and every step on the way said it was finished.
    if (file.keysTheTemplateGained.isNotEmpty) {
      return const CheckResult.ready();
    }

    return _toFill(file, wanted).isEmpty
        ? CheckResult.satisfied('$path states this $subject, and every value in it was answered')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String path = pathFor(context);
    if (!await context.files.exists(templatePath, elevated: elevated)) {
      // The same state check refuses, said as a plan rather than thrown. A plan that throws leaves
      // a dry run with nothing to say about this row, and a dry run that cannot say what a row
      // would do is the one outcome the mode exists to prevent.
      return StepPlan.nothing(
        'would fill $path once $templatePath is there — the checkout it stands in is made by an '
        'earlier row',
      );
    }
    final KeyValueFile file = await _read(context);
    final Map<String, String> filling = _toFill(file, await _wanted(context));
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
    final String path = pathFor(context);
    final KeyValueFile read = await _read(context);

    // GROWN FIRST, THEN FILLED, and both against the same reading. A key the template gained is
    // added with the paragraph that explains it, because that paragraph is the only documentation an
    // operator opening this file ever gets. It is added rather than the file being remade: the file
    // holds values somebody typed and values something minted once and keeps nowhere else, so the
    // repair for a missing key must never be "take the file away".
    final List<String> gained = read.keysTheTemplateGained;
    final KeyValueFile file = gained.isEmpty
        ? read
        : KeyValueFile(template: read.template, current: read.grownWith(gained));
    if (gained.isNotEmpty) {
      context.log.info(
        '$path gained ${gained.join(', ')} from $templatePath, each under its own paragraph',
      );
    }

    final Map<String, String> filling = _toFill(file, await _wanted(context));

    // SAID OUT LOUD WHERE A VALUE IS REPLACED RATHER THAN SUPPLIED, and the keys are named because
    // the values cannot be: a row holding credentials must reach no record. Filling an empty key is
    // the ordinary act and says nothing; taking back a value that disagreed with what this run was
    // told is the act somebody has to be able to see afterwards.
    final List<String> replaced = <String>[
      for (final String key in filling.keys)
        if (!file.isUnset(key)) key,
    ];
    if (replaced.isNotEmpty) {
      context.log.info(
        '$path held a different value for ${replaced.join(', ')}, and this run was told another — '
        'the answer is what an installation is described by, so it is what stands there now',
      );
    }

    if (filling.isEmpty && gained.isEmpty) {
      return;
    }
    await context.files.write(path, file.filled(filling), mode: fileMode, elevated: elevated);
  }

  /// The file as it stood, or null where there was none.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(pathFor(context), elevated: elevated)
      ? context.files.read(pathFor(context), elevated: elevated)
      : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    final String path = pathFor(context);
    if (captured == null) {
      // There was no such file, so taking this back means the path is gone again. Writing the
      // template back instead would leave a file of empty values that reads as an installation
      // nobody answered for, and returning without touching anything would leave THIS
      // installation's answers standing while the record says the step was taken back.
      await context.files.delete(path, elevated: elevated);
      return;
    }
    await context.files.write(path, captured, mode: fileMode, elevated: elevated);
  }

  /// The template and the file as they stand, read as one.
  Future<KeyValueFile> _read(StepContext context) async => KeyValueFile(
    template: await context.files.read(templatePath, elevated: elevated),
    current: await context.files.exists(pathFor(context), elevated: elevated)
        ? await context.files.read(pathFor(context), elevated: elevated)
        : await context.files.read(templatePath, elevated: elevated),
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
  Future<Map<String, String>> _wanted(StepContext context) async {
    final Map<String, String> wanted = <String, String>{};
    for (final MapEntry<String, KeyBinding> each in values.entries) {
      if (await each.value.resolveIn(context, elevated: elevated) case final String value) {
        wanted[each.key] = value;
      }
    }
    return wanted;
  }

  /// The keys this run writes: every one nobody has answered, and every one answered DIFFERENTLY.
  ///
  /// THE SECOND HALF IS WHAT MAKES A CREDENTIAL REPLACEABLE. Without it a key holding any value at
  /// all counts as done, whatever the run had been told — so an operator who rotated a token, put
  /// the new one in the answers and ran the programs again got every step green and an installation
  /// still using the old one. Measured on a machine carrying five GitHub tokens that answered 401,
  /// where correcting the answers would have changed nothing and the row would have reported
  /// "nothing to do: every value in it was answered".
  ///
  /// The answer wins, and it can only ever win over a key it HAS an answer for: [_wanted] leaves out
  /// what this run was not told, so a value an operator filled by hand under a key no answer names
  /// is never touched. What is given up is editing a key IN THE FILE that an answer also names —
  /// which was never a place to edit it, because the next run was always going to be told the
  /// answer and not the file.
  Map<String, String> _toFill(KeyValueFile file, Map<String, String> wanted) => <String, String>{
    for (final MapEntry<String, String> each in wanted.entries)
      if (file.isUnset(each.key) || file.valueOf(each.key) != each.value) each.key: each.value,
  };
}

/// Where one key's value comes from, and how several values are written on one line.
///
/// **Two sources, one per binding, and the row says which.** `KEY: {answer: name}` fills the key
/// from what THIS run was told — the ordinary case. `KEY: {file: <path>, key: <k>}` fills it from
/// what a settings file on this machine RECORDS, read off a line of the shape `key: value` or
/// `KEY=value` — the inheritance case, where another installation already decided the value and
/// asking for it again invites an answer that contradicts what stands written. Naming both in one
/// binding is refused where the row is read: two statements of one value is a pair that can
/// disagree.
///
/// **The file source may be named per installation, and `run_answer` says how.** A settings file
/// carrying a slot — `configs/config.<stage>` — is read with that slot filled from the answer of
/// that name, exactly as the step's own `run_answer` fills the path it WRITES. The two are separate
/// because the file read and the file written are two files, each named for whatever its
/// installation names it for.
///
/// **[join] and [split] are named properties of one entry and never expressions.** `join` says
/// which text stands between several values written on one line — an answer holding a list is
/// refused without it rather than written in whatever shape a list happens to print as. `split`
/// belongs to the file source alone, because a file records several values AS one line and the
/// separator they were recorded with is a fact of that file: the value is split there, and `join`
/// then says how this file writes them. An answer needs no split — it holds its values apart
/// already.
final class KeyBinding {
  /// Binds a key to one source, written as one line separated by [join] where it holds several.
  const KeyBinding({
    this.answer,
    this.file,
    this.key,
    this.literal,
    this.measured,
    this.split,
    this.join,
    this.runAnswer,
  });

  /// The name of the measurement that will fill this key, while it has not yet.
  ///
  /// A STEP IS BUILT TWICE AND ONLY THE SECOND TIME HAS A VALUE. Everything that examines a program
  /// before it runs builds every step — the registry holds a factory, and only an instance says
  /// whether a run can be taken back — and at that moment no row has measured anything. So a
  /// `{measured: <name>}` body is a value that DOES NOT EXIST YET and never an error: at execution
  /// the engine replaces the whole body with the text the measurement published
  /// (`ansiwise-core/lib/src/engine/step_execution.dart`), and this class sees [literal] instead.
  ///
  /// It resolves to nothing while it stands, which is the same silence an unanswered answer keeps.
  /// Nothing is lost by it: a row naming a measurement no step of the program publishes is refused
  /// by the resolver before the run starts, so the only way this survives to a real write is a
  /// program that could not have run at all.
  final String? measured;

  /// The value written out by the row itself, or by the engine in place of a measurement.
  ///
  /// THE ENGINE FILLS A MEASURED ENTRY BEFORE THE STEP EVER SEES IT. A row writing
  /// `values: {node-cidrs: {measured: host_addresses}}` reaches this class as the TEXT that
  /// measurement published — the substitution happens in
  /// `ansiwise-core/lib/src/engine/step_execution.dart`, which replaces the whole body with the
  /// value. So a body that is plain text is either a constant the row wrote out or a machine fact an
  /// observing row of this same run read, and nothing here can or needs to tell those apart: both
  /// are already the value.
  ///
  /// [split] and [join] do NOT apply to it, and cannot: the substitution keeps no room for them.
  /// Where several values have to reach one line, the measuring step publishes them in the shape the
  /// file writes them, which is the only place that still holds the whole list.
  final String? literal;

  /// The name of the answer this key is filled from, or null where a file records it.
  final String? answer;

  /// The settings file the value is recorded in, or null where an answer holds it.
  ///
  /// It may carry a slot, and [runAnswer] says which answer fills it.
  final String? file;

  /// WHICH answer fills the slot spelled with that name in [file], or null where it carries none.
  ///
  /// **A source file is named per installation as often as the file being written is.** A binding
  /// pointed at `configs/config.dev` reads the right file on exactly one installation and reads
  /// nothing on the next — and reading nothing here is silent: the key is simply not written, which
  /// every later reader takes for "this installation has no such value". Pointed at
  /// `configs/config.<stage>` with this naming `stage`, it reads the right file on all of them.
  ///
  /// It stands on the BINDING and not on the step, because the file a binding reads and the file
  /// the step writes are two files and each is named for whatever the installation names it for.
  final String? runAnswer;

  /// The key inside [file] whose value is taken.
  final String? key;

  /// What stands between the recorded values in [file], where it records several on one line.
  final String? split;

  /// What stands between the values where the source holds several, or null where it holds one.
  final String? join;

  /// The value this binding puts in the file, or null where this run has nothing to put.
  ///
  /// Null covers an answer nobody gave, one given empty, a source file that is not there, and a key
  /// it records nothing under — because all of them mean the same thing to the file being written:
  /// this installation has no such value. Writing an empty one instead would put a key in the file
  /// that says "answered with nothing", which reads to every later check as answered; and for an
  /// optional slot the absent line IS the statement.
  ///
  /// [elevated] is the step's own: whether this machine's files need root is a property of the row
  /// that pointed the step at them, and the source file stands on the same machine.
  Future<String?> resolveIn(StepContext context, {bool elevated = false}) async {
    if (literal case final String written) {
      return written.isEmpty ? null : written;
    }
    if (measured != null) {
      return null;
    }
    if (file != null) {
      return _recorded(context, elevated: elevated);
    }
    if (!context.answers.has(answer!)) {
      return null;
    }
    final String value = join == null
        ? context.answers.text(answer!)
        : context.answers.textList(answer!).join(join!);
    return value.isEmpty ? null : value;
  }

  /// The file this binding reads, with the slot filled from this run.
  ///
  /// A path still carrying a slot after the filling names no file, and is answered exactly like a
  /// file that is not there: this installation has no such value. It is not refused here, because
  /// every other way this binding can find nothing is the same silence and a single loud case among
  /// them would stop the run that was going to fill the file.
  String fileIn(StepContext context) {
    if (runAnswer case final String name) {
      if (context.answers.optionalText(name) case final String value) {
        return filledSlots(file!, <String, String>{name: value});
      }
    }
    return file!;
  }

  /// The value the named file records under the named key, or null where it records none.
  Future<String?> _recorded(StepContext context, {required bool elevated}) async {
    final String file = fileIn(context);
    if (leftoverSlotIn(file) != null) {
      return null;
    }
    if (!await context.files.exists(file, elevated: elevated)) {
      return null;
    }
    final String content = await context.files.read(file, elevated: elevated);
    final RegExp line = RegExp('^[ \\t]*${RegExp.escape(key!)}[ \\t]*[:=][ \\t]*(.*)\$');
    for (final String each in content.split('\n')) {
      final RegExpMatch? match = line.firstMatch(each.trimRight());
      if (match == null) {
        continue;
      }
      String value = match.group(1)!.trim();
      if (value.length >= 2 &&
          (value.startsWith('"') && value.endsWith('"') ||
              value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isEmpty) {
        return null;
      }
      if (split case final String separator) {
        final List<String> parts = <String>[
          for (final String part in value.split(separator))
            if (part.trim().isNotEmpty) part.trim(),
        ];
        return parts.isEmpty ? null : parts.join(join!);
      }
      return value;
    }
    return null;
  }

  /// The bindings a row declares, refusing anything that is not one.
  static Map<String, KeyBinding> readFrom(Object? declared) {
    if (declared is! Map<String, Object?>) {
      throw ArgumentError.value(
        declared,
        'values',
        'is a mapping of KEY to {answer: name}, {measured: name} or {file: path, key: name, '
            'run_answer: name}, each optionally joined',
      );
    }
    return <String, KeyBinding>{
      for (final MapEntry<String, Object?> each in declared.entries) each.key: _one(each),
    };
  }

  static KeyBinding _one(MapEntry<String, Object?> entry) {
    final Object? body = entry.value;
    // TEXT IS ALREADY THE VALUE. A row may write one out, and the engine writes one here in place of
    // a `{measured: <name>}` body before this step is built — so by the time a mapping reaches this
    // class, a measured entry is indistinguishable from a constant and both are simply the value.
    if (body is String) {
      return KeyBinding(literal: body);
    }
    if (body is! Map<String, Object?>) {
      throw ArgumentError.value(
        body,
        entry.key,
        'names its source, as {answer: name}, {measured: name} or {file: path, key: name}',
      );
    }
    if (body['measured'] case final String measured) {
      // NOT AN ERROR, AND THIS IS THE ONE PLACE THAT DECIDES IT. Everything examining a program
      // before it runs builds every step, and at that moment nothing has measured anything — so a
      // body still naming a measurement is a value that does not exist yet. At execution the engine
      // hands this same entry the published text and the branch above takes it.
      if (!MeasurementName.isValid(measured)) {
        throw ArgumentError.value(
          measured,
          '${entry.key}.measured',
          'is not a measurement name — lower case letters, digits and underscores, in parts '
              'separated by dots',
        );
      }
      return KeyBinding(measured: measured);
    }
    final Object? answer = body['answer'];
    final Object? file = body['file'];
    final Object? key = body['key'];
    final Object? split = body['split'];
    final Object? join = body['join'];
    final Object? runAnswer = body['run_answer'];
    if ((answer is! String) == (file is! String)) {
      // Neither source, or both: either way nothing says where the one value comes from.
      throw ArgumentError.value(
        body,
        entry.key,
        'names exactly one source — {answer: name} for a value this run holds, or '
        '{file: path, key: name} for one a file on this machine records',
      );
    }
    if (file is String && key is! String) {
      throw ArgumentError.value(
        body,
        entry.key,
        'reads a file and names no key, so nothing says which line of it holds the value',
      );
    }
    if (answer is String && (key != null || split != null || runAnswer != null)) {
      throw ArgumentError.value(
        body,
        entry.key,
        'is filled from an answer, and "key", "split" and "run_answer" belong to the file source '
        'alone',
      );
    }
    if (runAnswer != null && runAnswer is! String) {
      throw ArgumentError.value(
        runAnswer,
        '${entry.key}.run_answer',
        'is the name of the answer that fills the slot in the path',
      );
    }
    if (join != null && join is! String) {
      throw ArgumentError.value(join, '${entry.key}.join', 'is the text between several values');
    }
    if (split != null && split is! String) {
      throw ArgumentError.value(
        split,
        '${entry.key}.split',
        'is the text between the recorded values',
      );
    }
    if (split is String && join is! String) {
      throw ArgumentError.value(
        body,
        entry.key,
        'splits the recorded value and says nothing about how this file writes the parts — '
        'name "join" beside "split"',
      );
    }
    return KeyBinding(
      answer: answer as String?,
      file: file as String?,
      key: key as String?,
      split: split as String?,
      join: join as String?,
      runAnswer: runAnswer as String?,
    );
  }
}
