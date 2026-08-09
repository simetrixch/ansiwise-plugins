/// One thing a check decided is wrong, as a value rather than as a sentence.
///
/// A check that answered with formatted text would make every assertion about it a match on prose:
/// reword the message and the counter-probe that proves the check can go red stops proving it,
/// silently. So a check returns these, a test asserts on [Finding.subject], and the wording is free
/// to be written for the person who has to fix the thing.
library;

/// One finding: what it is about, where in it, and what is wrong.
final class Finding {
  /// Records a finding about [subject], optionally at [line] of it.
  const Finding(this.subject, this.what, {this.line});

  /// What the finding is about — a repository-relative path, or the name a program file writes.
  ///
  /// This is what a test matches on, so it is the identity of the finding and never a sentence.
  final String subject;

  /// The line of [subject] the finding sits on, where it has one.
  ///
  /// A finding about a whole file, or about a registered step rather than a place in a file, has
  /// none.
  final int? line;

  /// What is wrong, in the words the person fixing it reads.
  final String what;

  @override
  String toString() => switch (line) {
    final int at => '$subject:$at — $what',
    null => '$subject — $what',
  };
}

/// The findings of [findings] that are about [subject], for an assertion that names one place.
Iterable<Finding> about(Iterable<Finding> findings, String subject) =>
    findings.where((Finding finding) => finding.subject == subject);
