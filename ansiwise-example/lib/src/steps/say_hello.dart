import 'package:ansiwise_core/ansiwise_core.dart';

/// A simple example step that logs a greeting.
final class SayHello extends ReversibleStep<void> {
  /// Creates a SayHello step.
  const SayHello({required this.subject});

  /// Constructs a SayHello from parsed arguments.
  factory SayHello.fromArguments(Arguments arguments) =>
      SayHello(subject: arguments.text('subject'));

  /// The arguments this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'subject',
      kind: ArgumentKind.text,
      describes: 'the name of the entity to greet',
    ),
  ];

  /// The answers this step reads.
  static const List<String> answers = <String>[];

  /// The entity to greet.
  final String subject;

  @override
  Future<void> capture(StepContext context) async {
    // No previous state to capture.
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    return StepPlan.nothing('Saying hello to $subject does not change the machine');
  }

  @override
  Future<void> apply(StepContext context) async {
    context.log.info('Hello, $subject!');
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    return const Satisfied('Always satisfied');
  }

  @override
  Future<void> undo(StepContext context, void previous) async {
    context.log.info('Goodbye, $subject!');
  }
}
