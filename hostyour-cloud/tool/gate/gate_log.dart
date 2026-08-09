/// Where the gate says what it is about to do.
///
/// The classes that decide something return it; they never print. A person watching a gate run still
/// needs to know which package is being resolved and which suite is running, and that is what this
/// is for — so a test can drive the same run and read what it announced instead of watching a
/// terminal.
library;

import 'dart:io';

/// Somewhere for the gate to say what it is doing.
abstract interface class GateLog {
  /// Announces the next thing, on its own line.
  void heading(String what);

  /// Says something that is not a step of its own.
  void note(String what);
}

/// The terminal a developer is watching.
final class StdoutGateLog implements GateLog {
  /// Creates a log that writes to standard output.
  const StdoutGateLog();

  @override
  void heading(String what) => stdout.writeln('\n########## $what ##########');

  @override
  void note(String what) => stdout.writeln(what);
}

/// A log that keeps what it was told, for a test that has to read it.
final class CollectedGateLog implements GateLog {
  /// Everything the gate said, in order.
  final List<String> said = <String>[];

  @override
  void heading(String what) => said.add(what);

  @override
  void note(String what) => said.add(what);
}
