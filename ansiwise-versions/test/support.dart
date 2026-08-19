import 'package:ansiwise_core/ansiwise_core.dart';

/// A logger that keeps every line, so a test can assert on what a step SAID.
///
/// The report step's whole product is its log lines — nothing else leaves it — so a test that
/// dropped them would be asserting that a report ran, not that it reported.
final class CollectedLog implements Logger {
  /// Every line, whatever its level, in order.
  final List<String> lines = <String>[];

  @override
  void debug(String message) => lines.add(message);

  @override
  void info(String message) => lines.add(message);

  @override
  void warn(String message) => lines.add(message);

  @override
  void error(String message) => lines.add(message);
}
