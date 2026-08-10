import 'package:ansiwise_api/ansiwise_api.dart';

/// The text of a file this plugin writes, kept beside the plugin instead of composed in Dart.
///
/// **A template is the file itself with each per-installation value taken out and a marked slot left
/// where it stood.** A slot is written `<name>`, which is the notation this plugin already uses
/// everywhere a value cannot be written down in advance: a program file writes `<cluster>` and
/// `<stage>` where the run's own names belong, and a release url writes `<version>` where the pin
/// belongs. A slot is a NAME and nothing else — no expression, no condition, no loop — so what a
/// reader has in front of them is the file that will land on the machine rather than a language for
/// producing files.
///
/// **What that rules out is deliberate.** A file whose line is present on one machine and absent on
/// another cannot be written this way: leaving a slot empty writes the key with no value, and a key
/// with no value is what a reader downstream resolves to nothing. Such a file keeps composing its
/// text in Dart, where the condition can be stated.
///
/// **The template and the values a run holds must fit each other exactly, and neither side may be
/// silent about a gap.** A slot nothing fills would reach the machine in angle brackets, where the
/// tool reading the file either refuses it or — worse — accepts it. A value with no slot to go into
/// would be dropped, and the file would be missing what this run was told to put in it.
/// [Template.filledWith] reports both at once.
final class Template {
  /// The template that was read from [path].
  const Template({required this.path, required this.text});

  /// Where it stands.
  final String path;

  /// What it holds, slots and all.
  final String text;

  /// The slot names it carries, each named once, in the order they first appear.
  List<String> get slots {
    final List<String> found = <String>[];
    for (final RegExpMatch match in _slot.allMatches(text)) {
      if (match.group(1) case final String name) {
        if (!found.contains(name)) {
          found.add(name);
        }
      }
    }
    return found;
  }

  /// [text] with the slot named by each entry of [values] holding that entry's value.
  ///
  /// Throws [TemplateRefused] naming everything the two disagree about, all of it at once — a
  /// caller correcting one name per run is a caller running it five times.
  String filledWith(Map<String, String> values) {
    final List<String> named = slots;
    final List<String> unfilled = <String>[
      for (final String name in named)
        if (!values.containsKey(name)) name,
    ];
    final List<String> unplaced = <String>[
      for (final String name in values.keys)
        if (!named.contains(name)) name,
    ];
    if (unfilled.isNotEmpty || unplaced.isNotEmpty) {
      throw TemplateRefused(
        <String>[
          '$path and the values this run holds do not fit each other',
          if (unfilled.isNotEmpty)
            'it names ${_asSlots(unfilled)} and this run holds no value under that name',
          if (unplaced.isNotEmpty)
            'this run holds ${_asSlots(unplaced)} and the template names no such slot, so the '
                'value would not reach the file',
        ].join('; '),
      );
    }

    String written = text;
    for (final MapEntry<String, String> value in values.entries) {
      written = written.replaceAll('<${value.key}>', value.value);
    }
    return written;
  }

  static String _asSlots(List<String> names) => names.map((String name) => '<$name>').join(', ');
}

/// Nothing can be rendered from a template, and this says what stands in the way.
///
/// Two conditions, one type, because a step does the same thing with both: the template is not on
/// this machine at all, or it and the run name different things. Neither can be worked around and
/// neither may be passed over in silence.
///
/// An exception rather than an error, so it can be caught where it becomes a refusal an operator
/// reads. [TemplateStep] catches it in the two places a run asks a step what it would do, and
/// nowhere else — inside an apply it stays thrown, and the engine records the step as failed.
final class TemplateRefused implements Exception {
  /// Records that nothing can be rendered, because [message].
  const TemplateRefused(this.message);

  /// What stands in the way, written for whoever has to correct it.
  final String message;

  @override
  String toString() => message;
}

/// A file step whose text is a template beside the plugin rather than a string composed in Dart.
///
/// The step still says which file it writes, which permission bits it ends up with and which value
/// goes in which slot. What is here is the reading of the template and the two answers a run gives
/// when there is none to read.
///
/// **A template that cannot be rendered is BLOCKED and never satisfied.** The two look alike from
/// the outside and are opposites: a satisfied check says this machine needs no such file, and a
/// machine whose template did not travel with it needs the file as much as any other. Reporting the
/// first for the second would leave a machine with no rule set, no service and no manifest, and a
/// run that said every step was fine.
///
/// **The step is asked whether it needs the file BEFORE the template is read**, which is what the
/// order of these two methods produces: the step's own [FileStep.contentFor] answers
/// [FileContent.nothing] on a machine that has no business with the file, and reaches the template
/// only when there is something to render. A machine that steers nothing therefore still says it
/// has nothing to do, whatever it carries.
base mixin TemplateStep on FileStep {
  /// Where the template stands, as the program file names it.
  ///
  /// Relative to the directory the run was started in, which is the same place the program files
  /// are read from — so a template travels with the programs of the installation it belongs to.
  String get templatePath;

  /// The template at [templatePath] with [values] in its slots.
  ///
  /// Throws [TemplateRefused] where there is no template at that path, and where it and [values]
  /// name different things.
  Future<String> renderedWith(StepContext context, Map<String, String> values) async {
    if (!await context.files.exists(templatePath)) {
      throw TemplateRefused(
        '$templatePath is not where this run was started, and it is the text this step writes — a '
        'template travels with the programs of its installation, and nothing here composes the '
        'file without one',
      );
    }
    return Template(
      path: templatePath,
      text: await context.files.read(templatePath),
    ).filledWith(values);
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    try {
      return await super.check(context);
    } on TemplateRefused catch (refused) {
      return CheckResult.blocked(refused.message);
    }
  }

  /// What would be done, which where nothing can be rendered is nothing.
  ///
  /// Answered rather than left to throw. A plan is what an operator reads to decide whether to let
  /// the run happen, and a plan that failed to be produced tells them nothing about what would be
  /// done — including that the thing standing in the way is a file this installation is missing.
  @override
  Future<StepPlan> plan(StepContext context) async {
    try {
      return await super.plan(context);
    } on TemplateRefused catch (refused) {
      return StepPlan.nothing(refused.message);
    }
  }
}

/// A marked slot: a name in angle brackets, and nothing that could be an expression.
final RegExp _slot = RegExp('<([a-z][a-z0-9-]*)>');
