import 'package:ansiwise_api/ansiwise_api.dart';
import 'steps/say_hello.dart';

/// The registry mapping step names to their implementations in this plugin.
const Registry exampleRegistry = Registry(
  steps: <StepName, RegisteredStep>{
    StepName('say_hello'): RegisteredStep(
      name: StepName('say_hello'),
      source: 'lib/src/steps/say_hello.dart:18',
      create: SayHello.fromArguments,
      arguments: SayHello.arguments,
      answers: SayHello.answers,
    ),
  },
  predicates: <PredicateName, RegisteredPredicate>{},
);
