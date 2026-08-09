/// Building one registered step, and running it outside a run.
///
/// A check asks a step a question the engine would ask it — what would you plan, are you already
/// satisfied — without a runner, a record or a machine. What it needs for that is the same three
/// things every time: values for the arguments the step declares, somewhere for the step to say
/// things, and a [StepContext] holding a set of ports the check chose.
library;

import 'package:ansiwise_api/ansiwise_api.dart';

import 'finding.dart';

/// A value for every argument [specs] declares.
///
/// A default wins wherever there is one, because that is the value a program that says nothing about
/// the argument would run with — the case worth probing. Where the declaration names the values it
/// may hold, the first of them is taken: a step that DECIDES on such a value refuses anything
/// outside the set, correctly, and handing it the generic 'x' would measure the probe rather than
/// the step. Everything else gets the simplest value of its kind. No step may read an argument it
/// did not declare, so this is enough to build any of them that keeps to its own declaration; one
/// that does not fails to build, and a check reports that rather than passing over the step.
Arguments plausibleArguments(List<ArgumentSpec> specs) {
  final Map<String, Object> values = <String, Object>{};
  for (final ArgumentSpec spec in specs) {
    values[spec.name] =
        spec.defaultValue ??
        (spec.allowed.isNotEmpty ? spec.allowed.first : null) ??
        switch (spec.kind) {
          ArgumentKind.text => 'x',
          ArgumentKind.integer => 1,
          ArgumentKind.flag => false,
          ArgumentKind.textList => const <String>['x'],
        };
  }
  return Arguments(values);
}

/// A value for every answer any program under [directory] declares.
///
/// A step reads its answers BY NAME out of the run, and the kinds are declared by the program file
/// rather than by the registry — so the only place a check can learn that `alert_recipients` is a
/// list of text and `fqdn` is text is the program files themselves. They are read here rather than
/// listed, so a check never has to be edited when a program gains a question.
///
/// The union of every program's declarations, because a check runs each registered step once and
/// does not know which program will name it. Two programs declaring one name with different kinds
/// would make this ambiguous; the resolver would refuse such a pair anyway, and until then the first
/// one read wins.
Future<Arguments> plausibleAnswers(Files files, String directory) async {
  final List<ArgumentSpec> declared = <ArgumentSpec>[];
  final Set<String> seen = <String>{};
  final List<String> names = <String>[
    for (final String name in await files.list(directory))
      if (name.endsWith('.yaml')) name,
  ]..sort();

  for (final String name in names) {
    final Program program = loadProgram(await files.read('$directory/$name'), where: name);
    for (final ArgumentSpec spec in program.answers.specs) {
      if (seen.add(spec.name)) {
        declared.add(spec);
      }
    }
  }
  return plausibleArguments(declared);
}

/// The step [entry] builds from [plausibleArguments], or null when it cannot be built that way.
///
/// [onFailure] is given a finding naming the step and the reason. Every throwable is caught,
/// including an [Error]: a step that reads an argument it never declared throws [ArgumentError], and
/// that is precisely the defect worth reporting rather than letting one entry end the walk and say
/// nothing about the rest.
Step? buildStep(RegisteredStep entry, void Function(Finding failure) onFailure) {
  try {
    return entry.create(plausibleArguments(entry.arguments));
  } on Object catch (failure) {
    onFailure(
      Finding(
        entry.name.value,
        'could not be built from the arguments it declares itself, so nothing about it was '
        'measured — $failure',
      ),
    );
    return null;
  }
}

/// What a step said while a check was running it.
///
/// Kept rather than printed: a step's own notes would otherwise land in the middle of a test run's
/// output and be read as its own.
final class CollectedLog implements StepLog {
  /// Everything the step said, in order.
  final List<String> said = <String>[];

  @override
  void info(String message) {
    said.add(message);
  }

  @override
  void warn(String message) {
    said.add(message);
  }
}

/// The context a check hands [step], carrying the ports it chose.
///
/// [Facts.none] because no predicate is evaluated here: a step that asks about one it did not have
/// evaluated throws, which is a defect in the step and is reported as such.
StepContext probeContext({
  required StepName step,
  required Arguments arguments,
  required Arguments answers,
  required Shell shell,
  required Files files,
  required Http http,
  required Clock clock,
  required Entropy entropy,
  required StepLog log,
}) => StepContext(
  shell: shell,
  files: files,
  http: http,
  clock: clock,
  entropy: entropy,
  log: log,
  step: step,
  arguments: arguments,
  answers: answers,
  facts: Facts.none,
);

/// What a [CheckResult] answered, as one line, so two answers can be compared and reported.
String describeCheck(CheckResult result) => switch (result) {
  Ready() => 'ready',
  Satisfied(:final String because) => 'satisfied: $because',
  Blocked(:final String reason) => 'blocked: $reason',
};
