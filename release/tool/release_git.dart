/// git, as something the release program asks rather than a process it starts inline.
///
/// What the release program DECIDES is one thing and starting a program on this operating system is
/// another. The split is what lets the deciding half be driven by a check — including the half that
/// pushes — on a machine that starts no git and reaches no remote, and what was asked for is then a
/// list of argument lists in the order it was asked. That list is the evidence for the two claims of
/// this program: the screen writes nothing, and a version that is typed pushes exactly one tag.
///
/// IT IS RUN AT THE REPOSITORY ROOT AND NOT WHERE THE PERSON STOOD. This program lives in a package
/// beside the twelve it releases, so the shell it is started from is one directory down. `git add`
/// is then given paths, and a path is read relative to the working directory: the same argument list
/// would stage two different files depending on where somebody typed it.
///
/// Every answer carries both streams. git writes what happened to stderr as readily as to stdout,
/// and a refusal quoting one of them would drop the sentence a person needs.
library;

import 'dart:io';

/// What one git command answered.
final class GitAnswer {
  /// git exited with [status], having written [output].
  const GitAnswer({required this.status, required this.output});

  /// What it exited with.
  final int status;

  /// Both of its streams, in the order they were read.
  final String output;

  /// Whether it did what it was asked.
  bool get isGreen => status == 0;

  /// [output] without its empty lines, so a refusal can quote it without quoting blank space.
  List<String> get lines => output
      .split('\n')
      .map((String line) => line.trimRight())
      .where((String line) => line.isNotEmpty)
      .toList(growable: false);
}

/// A git that can be asked to run a command.
abstract interface class Git {
  /// Runs git with [arguments] and answers what it exited with and wrote.
  Future<GitAnswer> run(List<String> arguments);
}

/// git, started as a program of the machine the release program is running on.
final class GitOnThisMachine implements Git {
  /// The git on the PATH, run in [workingDirectory].
  const GitOnThisMachine({required this.workingDirectory});

  /// Where every command is run, which is the root of the repository being released.
  final String workingDirectory;

  @override
  Future<GitAnswer> run(List<String> arguments) async {
    try {
      final ProcessResult result = await Process.run(
        'git',
        arguments,
        workingDirectory: workingDirectory,
      );
      return GitAnswer(
        status: result.exitCode,
        output: '${result.stdout as String}\n${result.stderr as String}',
      );
    } on ProcessException catch (refused) {
      // A machine with no git is not a machine where nothing has been released. The status is made
      // non-zero here so the caller refuses instead of reading an empty answer as an empty remote.
      return GitAnswer(status: 1, output: 'no git could be started: ${refused.message}');
    }
  }
}

/// The tag names in what `git ls-remote --tags <remote>` wrote.
///
/// Each line is an object name, a tab and a ref — `refs/tags/0.1.0`. An ANNOTATED tag is listed
/// twice, the second line naming the commit it points at with `^{}` appended, so the suffix is cut
/// and the names are collected into a set: a tag that was annotated must not read as two releases.
Set<String> tagNamesIn(String output) => <String>{
  for (final String line in output.split('\n'))
    if (line.trim().split(RegExp(r'\s+')).last case final String ref)
      if (ref.startsWith(_tagRef)) ref.substring(_tagRef.length).replaceAll(_peeled, ''),
};

const String _tagRef = 'refs/tags/';

final RegExp _peeled = RegExp(r'\^\{\}$');
