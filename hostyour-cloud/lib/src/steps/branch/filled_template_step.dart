import 'package:ansiwise_api/ansiwise_api.dart';

import 'filled_template.dart';

/// A step that fills a `KEY=value` file from the template beside it, and never resets an answered
/// key.
///
/// **Two files on an install branch are made this way** — the configuration the rest of the
/// installation reads, and the credentials its secret store is seeded from. They are the same act
/// on different files, and they were two classes carrying the same mechanism twice: read the
/// template and the file into one [FilledTemplate], work out which keys still need an answer, write
/// the file with those filled and every other byte untouched.
///
/// **What is here is the mechanism. What is not here is the words.** Each step says in its own
/// language what a missing template costs it, what its keys are called and what an operator has
/// filled in when it is satisfied — because a configuration key and a credential are not the same
/// thing to the person reading the refusal, and a shared sentence would have to be vague enough to
/// cover both.
///
/// **Nor is the plan here**, and that is not an oversight. The configuration's plan carries the
/// whole file, because an operator reading it wants to see the file they will get. The credential
/// file's plan carries the KEYS and never the values, because a plan is read out of the run record.
/// One plan for both would either hide the configuration or put a credential in a record.
abstract base class FilledTemplateStep extends ReversibleStep<String?> {
  /// Creates a step that fills one such file.
  const FilledTemplateStep();

  /// The template this file is made from, which declares every key it may carry.
  String get templatePath;

  /// Where the filled file goes.
  String pathFor(StepContext context);

  /// The permission bits it ends up with.
  int get mode;

  /// What this run was given, by the key each value belongs under.
  Map<String, String> valuesFrom(StepContext context);

  /// The template and the file as they stand, read as one.
  ///
  /// The file is the template itself where the branch carries none yet, which is what makes
  /// creating and re-filling the same operation.
  Future<FilledTemplate> read(StepContext context) async {
    final String template = await context.files.read(templatePath);
    final String path = pathFor(context);
    return FilledTemplate(
      template: template,
      current: await context.files.exists(path) ? await context.files.read(path) : template,
    );
  }

  /// Which of [wanted] this run would write, which is also the step's postcondition.
  ///
  /// TWO reasons a key is left alone, and both are needed:
  ///
  /// - **It carries anything other than the template's own value**, so it is live — a credential
  ///   rotated by hand, or one of the values a later phase writes back into this file. A re-run that
  ///   rewrote those would take the keys to a running secret store away.
  /// - **It already carries exactly what this run would write.** Not a curiosity: `DEPLOY_ENV` reads
  ///   `prod` in the template and `prod` is a stage an installation really runs, so an answer equal
  ///   to the template's value is a real answer. Without this the step would write on every run and
  ///   report having changed something each time.
  List<String> toFill(FilledTemplate file, Map<String, String> wanted) => <String>[
    for (final MapEntry<String, String> value in wanted.entries)
      if (file.isUnset(value.key) && file.valueOf(value.key) != value.value) value.key,
  ];

  /// Which of [wanted] hold a character this file cannot carry.
  ///
  /// A `KEY="value"` file ends a value at the closing quote, so a value holding one of its own
  /// would cut the line in half and leave the rest of it as syntax. It is refused rather than
  /// escaped: an operator who typed a quote meant something by it, and a file that quietly changed
  /// their value would be answering a question they did not ask.
  ///
  /// The detection is here; the sentence is each step's own, because what an operator has to do
  /// about a configuration value and about a credential are different things to be told.
  List<String> unwritableIn(Map<String, String> wanted) => <String>[
    for (final MapEntry<String, String> value in wanted.entries)
      if (FilledTemplate.holdsQuote(value.value)) value.key,
  ];

  @override
  Future<void> apply(StepContext context) async {
    final FilledTemplate file = await read(context);
    final Map<String, String> wanted = valuesFrom(context);
    await context.files.write(
      pathFor(context),
      file.filled(<String, String>{
        for (final String key in toFill(file, wanted)) key: wanted[key] ?? '',
      }),
      mode: mode,
    );
  }

  /// What the file held before this run filled it, which is what [undo] writes back.
  ///
  /// The whole file rather than the keys this step fills, because every other line of it is the
  /// operator's or the product's and putting the captured bytes back keeps all of them exactly as
  /// they stood. It also settles the one question the file cannot answer afterwards: a key the
  /// operator had already answered with the same value this run was given reads identically to one
  /// this run wrote, and only the bytes from before can tell them apart.
  @override
  Future<String?> capture(StepContext context) async {
    final String path = pathFor(context);
    return await context.files.exists(path) ? context.files.read(path) : null;
  }

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      await context.files.delete(pathFor(context));
      return;
    }
    await context.files.write(pathFor(context), captured, mode: mode);
  }
}
