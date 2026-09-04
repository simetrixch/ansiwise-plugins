import 'package:ansiwise_core/ansiwise_core.dart';

/// Makes a directory at the path a program row names and leaves it belonging to an ACCOUNT this
/// machine carries, at the mode the row names.
///
/// **THE ACCOUNT IS A NAME, AND THE NUMBERS ARE READ OFF THE MACHINE.** Which number an
/// installation gave its operator is that machine's own fact, and a program file that wrote one
/// would be right on one machine and silently wrong on the next.
///
/// **WHAT ASKED FOR IT.** A machine's platform state is made by programs that run as root and is
/// then driven by a Manager that reaches the machine as the operator, and every place those two
/// meet without a hand-over is a refusal — a repository git will not open, a directory a run cannot
/// write its record into. The hand-over is the answer, and it needs a step that speaks in accounts.
///
/// **THE COMMANDS ARE ELEVATED WHATEVER THE ROW SAYS.** A directory under a path only root may write
/// cannot be made by the account that has to use it, and handing it over is `chown`, which is root's
/// either way. So this step carries no elevation flag: there is no shape of it that is not elevated,
/// and a flag that only ever takes one value is a question nobody should be asked.
///
/// **IT RE-APPLIES.** A directory another party reached first — a mount made on demand, an earlier
/// program that ran as root — carries the wrong owner, and the account then starts against a
/// directory it cannot write while everything reports itself healthy. Correcting it is safe because
/// what stands here is a directory, not the data underneath one.
///
/// **AN ACCOUNT THIS MACHINE DOES NOT CARRY IS A REFUSAL, never a guess.** A directory handed to a
/// number nobody has is a directory nobody can write, and a run that did it would report it done.
final class HandDirectoryToAccount extends ReversibleStep<DirectoryBefore> {
  /// Hands the directory at [path] to the account the answer [accountAnswer] names, at [mode].
  const HandDirectoryToAccount({
    required this.path,
    required this.accountAnswer,
    required this.mode,
  });

  /// Builds the step from what the program gave it.
  factory HandDirectoryToAccount.fromArguments(Arguments arguments) => HandDirectoryToAccount(
    path: arguments.text('path'),
    accountAnswer: arguments.text('account_answer'),
    mode: arguments.integer('mode'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'where the directory goes on this machine',
    ),
    ArgumentSpec(
      name: 'account_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the account the directory is handed to. An account and '
          'not a number: which number an installation gave it is read off this machine',
    ),
    ArgumentSpec(
      name: 'mode',
      kind: ArgumentKind.integer,
      describes:
          'the permission bits it ends up with, as a decimal number — 493 is 0755, the mode of a '
          'directory anyone on the machine may read and its owner may write',
    ),
  ];

  /// Where the directory goes.
  final String path;

  /// The name of the answer holding the account it is handed to.
  final String accountAnswer;

  /// The permission bits it ends up with.
  final int mode;

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({int? owner, int? group, String? refusal}) wanted = await _wanted(context);
    if (wanted.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ({int? owner, int? group, int? raw, String? refusal}) found = await _found(context);
    if (found.refusal != null) {
      return const CheckResult.ready();
    }
    final int raw = found.raw!;
    if (raw & _typeBits != _directoryBits) {
      return CheckResult.blocked(
        '$path is ${_kindOf(raw)} and not a directory. Nothing here takes away what somebody else '
        'put there, and handing that over instead would change the wrong thing while whatever '
        'needs a directory at this path still has none',
      );
    }
    if (found.owner == wanted.owner && found.group == wanted.group && raw & _modeBits == mode) {
      return CheckResult.satisfied(
        '$path is a directory belonging to ${context.answers.text(accountAnswer)} '
        '(${wanted.owner}:${wanted.group}) at ${_octal(mode)}',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final ({int? owner, int? group, String? refusal}) wanted = await _wanted(context);
    if (wanted.refusal case final String refusal) {
      return StepPlan.notKnownYet(refusal);
    }
    final ({int? owner, int? group, int? raw, String? refusal}) found = await _found(context);
    if (found.refusal != null) {
      return StepPlan.argv(<String>['mkdir', '-p', path]);
    }
    if (found.owner != wanted.owner || found.group != wanted.group) {
      return StepPlan.argv(<String>['chown', '${wanted.owner}:${wanted.group}', path]);
    }
    return StepPlan.argv(<String>['chmod', _octal(mode), path]);
  }

  @override
  Future<DirectoryBefore> capture(StepContext context) async {
    final ({int? owner, int? group, int? raw, String? refusal}) found = await _found(context);
    if (found.refusal == null) {
      return DirectoryBefore.carrying(
        owner: found.owner!,
        group: found.group!,
        mode: found.raw! & _modeBits,
      );
    }
    if (await context.files.exists(path, elevated: true)) {
      return DirectoryBefore.unread(found.refusal!);
    }
    return const DirectoryBefore.nothing();
  }

  @override
  Future<void> apply(StepContext context) async {
    final ({int? owner, int? group, String? refusal}) wanted = await _wanted(context);
    if (wanted.refusal case final String refusal) {
      throw StateError(refusal);
    }
    await context.files.createDirectory(path, mode: mode, elevated: true);
    await _mustRun(context, <String>['chown', '${wanted.owner}:${wanted.group}', path]);
    // THE MODE IS SET AGAIN, AND ON PURPOSE. The call above applies the mode to a directory it
    // MAKES; whether it also changes the mode of one that was already there is a property of the
    // tool it reaches for, and this step's postcondition does not rest on it.
    await _mustRun(context, <String>['chmod', _octal(mode), path]);
  }

  @override
  Future<void> undo(StepContext context, DirectoryBefore captured) async {
    if (captured.refusal case final String refusal) {
      throw StateError(
        '$path is left exactly as it stands, because what it belonged to before was never '
        'measured: $refusal',
      );
    }
    if (captured.absent) {
      // `rmdir` AND NEVER `rm -r`. Between the apply and this undo the account may already have
      // written into it, and a clean-up after some other step's failure must not take that away.
      await _mustRun(context, <String>['rmdir', path]);
      return;
    }
    await _mustRun(context, <String>['chown', '${captured.owner}:${captured.group}', path]);
    await _mustRun(context, <String>['chmod', _octal(captured.mode!), path]);
  }

  /// The numbers this machine gives the account the row names, or why they could not be read.
  Future<({int? owner, int? group, String? refusal})> _wanted(StepContext context) async {
    final String account = context.answers.text(accountAnswer);
    if (account.isEmpty) {
      return (
        owner: null,
        group: null,
        refusal:
            'the answer "$accountAnswer" names no account, so there is nobody to hand $path to',
      );
    }
    final CommandResult uid = await context.shell.run(
      Command.observing('id', arguments: <String>['-u', account], elevated: true),
    );
    final CommandResult gid = await context.shell.run(
      Command.observing('id', arguments: <String>['-g', account], elevated: true),
    );
    final int? u = uid.ok ? int.tryParse(uid.trimmed) : null;
    final int? g = gid.ok ? int.tryParse(gid.trimmed) : null;
    if (u == null || g == null) {
      return (
        owner: null,
        group: null,
        refusal:
            'this machine carries no account "$account", so the numbers to hand $path to cannot be '
            'read — and a directory handed to a number nobody has is one nobody can write: '
            '${uid.stderr.trim().isEmpty ? gid.stderr.trim() : uid.stderr.trim()}',
      );
    }
    return (owner: u, group: g, refusal: null);
  }

  /// What stands at [path] today, as three numbers, or why nothing could be read.
  Future<({int? owner, int? group, int? raw, String? refusal})> _found(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('stat', arguments: <String>['-c', '%u %g %f', path], elevated: true),
    );
    if (!answer.ok) {
      return (owner: null, group: null, raw: null, refusal: answer.stderr.trim());
    }
    final List<String> fields = answer.trimmed.split(RegExp(r'\s+'));
    if (fields.length != 3) {
      return (owner: null, group: null, raw: null, refusal: 'stat answered "${answer.trimmed}"');
    }
    final int? owner = int.tryParse(fields[0]);
    final int? group = int.tryParse(fields[1]);
    final int? raw = int.tryParse(fields[2], radix: 16);
    if (owner == null || group == null || raw == null) {
      return (owner: null, group: null, raw: null, refusal: 'stat answered "${answer.trimmed}"');
    }
    return (owner: owner, group: group, raw: raw, refusal: null);
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(argv.first, arguments: argv.sublist(1), elevated: true),
    );
    if (!answer.ok) {
      throw CommandFailed(
        argv: argv,
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }

  /// What the kind bits of [raw] say is standing there, for the refusal an operator reads.
  static String _kindOf(int raw) => switch (raw & _typeBits) {
    _regularFileBits => 'a regular file',
    _symbolicLinkBits => 'a symbolic link',
    _ => 'of kind 0x${(raw & _typeBits).toRadixString(16)}',
  };

  /// [mode] as `chmod` is handed it: four octal digits, so the leading one is stated rather than
  /// left to be inferred.
  static String _octal(int mode) => mode.toRadixString(8).padLeft(4, '0');

  /// The bits of `stat -c %f` that say what kind of thing the path is.
  static const int _typeBits = 0xf000;

  /// See [_typeBits]: the value those bits carry for a directory, for a regular file and for a
  /// symbolic link.
  static const int _directoryBits = 0x4000;

  /// See [_typeBits].
  static const int _regularFileBits = 0x8000;

  /// See [_typeBits].
  static const int _symbolicLinkBits = 0xa000;

  /// The bits of `stat -c %f` that are the permissions, which is what `chmod` sets and what the
  /// mode argument states.
  static const int _modeBits = 0xfff;
}

/// What stood at the path before [HandDirectoryToAccount] ran, which is what its undo puts back.
///
/// Three states and not two, because "the reading was not taken" is neither of the other two and
/// must never be mistaken for one of them. Every value here is an instruction to an undo: one of
/// them removes a directory, one of them re-owns it, and the third one refuses to do either.
final class DirectoryBefore {
  /// Records that nothing stood at the path, so what the run makes is the run's to remove.
  const DirectoryBefore.nothing()
    : owner = null,
      group = null,
      mode = null,
      refusal = null,
      absent = true;

  /// Records the [owner], the [group] and the [mode] a directory already standing there carried.
  const DirectoryBefore.carrying({
    required int this.owner,
    required int this.group,
    required int this.mode,
  }) : refusal = null,
       absent = false;

  /// Records that the machine could not be read, so the undo puts nothing back and says why.
  const DirectoryBefore.unread(String this.refusal)
    : owner = null,
      group = null,
      mode = null,
      absent = false;

  /// The number that owned it, or null where nothing stood there or nothing was read.
  final int? owner;

  /// The number of the group it belonged to, under the same condition as [owner].
  final int? group;

  /// The permission bits it carried, under the same condition as [owner].
  final int? mode;

  /// Why the machine could not be read, or null where it was.
  final String? refusal;

  /// Whether nothing stood at the path.
  final bool absent;
}
