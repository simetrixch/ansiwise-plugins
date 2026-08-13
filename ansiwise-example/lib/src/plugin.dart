import 'package:ansiwise_api/ansiwise_api.dart';
import 'registry.dart';

/// The Example Plugin.
///
/// It teaches the framework how to say hello, serving as a reference.
final class ExamplePlugin implements Plugin {
  /// Creates the ExamplePlugin.
  const ExamplePlugin();

  @override
  String get name => 'ansiwise-example';

  @override
  Registry get registry => exampleRegistry;
}
