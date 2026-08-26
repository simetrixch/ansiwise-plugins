import 'package:ansiwise_core/ansiwise_core.dart';

/// Makes a directory at the path a program row names, and leaves it owned by the numbers that row
/// names at the mode it names.
///
/// **THE OWNER AND THE GROUP ARE NUMBERS, and that is the whole reason this step exists.** A file's
/// owner is stored as a number, and the process that writes into a directory like this one is very
/// often a container carrying the number its image runs as — that number lives in the image's own
/// account database and in no account on the machine, so there is no name to give. `create_group`
/// beside this file makes exactly this argument for a group.
///
/// **The tool that makes a directory cannot set such an owner, and it is why the two acts are two
/// commands.** `install -d -o <owner>` resolves an owner through the machine's account database and
/// refuses what it does not find there: measured, `install -d -o 65532 -g 65532 -m 0770` answers
/// `install: invalid user: '65532'` on a machine where a GROUP carrying 65532 is present and no
/// account carries that number. `chown` takes a number as a number. So the directory is made first
/// and `chown` sets the ownership afterwards, and both arguments are declared as whole numbers so
/// that a row writing a NAME is refused by `--mode test` before anything is touched, rather than by
/// a tool in the middle of a run.
///
/// **IT RE-APPLIES.** A directory found with the wrong owner, the wrong group or the wrong mode is
/// corrected rather than left alone. Something else on the machine reaches such a path before the
/// program does — a mount point made on demand is made owned by root at 0755 — and the workload
/// then starts against a directory it cannot write, while everything reports itself healthy.
/// Correcting is safe here precisely because this is an empty directory a workload is about to
/// fill.
///
/// **IT SITS BESIDE `create_storage_directory` AND REPLACES NOTHING.** That step differs in three
/// ways, each of them a difference in kind rather than in value: its path comes from an ANSWER,
/// because where a machine keeps its data is that machine's own fact, while a directory a workload
/// requires is the caller's constant and a program row writes it; it deliberately does NOT
/// re-apply, because the data of every volume the cluster handed out lives underneath it; and it
/// cannot be taken back at all, for the same reason. Six further steps in this tree make a
/// directory so that a file they are about to write has somewhere to go, and none of them takes an
/// owner.
///
/// **A DRY RUN NAMES THE ONE ACT THAT IS MISSING.** A plan is a single command and this step's act
/// is up to three — make it, own it, set its mode — so [plan] names the first of the three the
/// machine still needs, which on a re-run is the `chown` that says exactly what is wrong. A real
/// run records all three.
final class CreateDirectory extends ReversibleStep<DirectoryBefore> {
  /// Makes [path] owned by [owner] and [group] at [mode].
  const CreateDirectory({
    required this.path,
    required this.owner,
    required this.group,
    required this.mode,
    required this.elevated,
  });

  /// Builds the step from what the program gave it.
  factory CreateDirectory.fromArguments(Arguments arguments) => CreateDirectory(
    path: arguments.text('path'),
    owner: arguments.integer('owner'),
    group: arguments.integer('group'),
    mode: arguments.integer('mode'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'where the directory goes on this machine',
    ),
    ArgumentSpec(
      name: 'owner',
      kind: ArgumentKind.integer,
      describes:
          'the number that owns the directory. A number and never a name: what writes into a '
          'directory like this is usually a container carrying the number its image runs as, and '
          'the machine has no account for it',
    ),
    ArgumentSpec(
      name: 'group',
      kind: ArgumentKind.integer,
      describes:
          'the number of the group the directory belongs to, given the same way and for the same '
          'reason as the owner above',
    ),
    ArgumentSpec(
      name: 'mode',
      kind: ArgumentKind.integer,
      describes:
          'the permission bits the directory is left with, as the number the machine stores — 504 '
          'is 0770, which lets the owner and the group read, write and enter it and nobody else, '
          'and 493 is 0755',
    ),
    elevationArgument,
  ];

  /// Where the directory goes.
  final String path;

  /// The number that owns it.
  final int owner;

  /// The number of the group it belongs to.
  final int group;

  /// The permission bits it is left with.
  final int mode;

  /// Whether the path is reachable only as root, so every read and write of it is elevated.
  final bool elevated;

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({int? group, int? owner, int? raw, String? refusal}) found = await _found(context);
    if (found.refusal != null) {
      // A reading that was not taken leads to WORK and never to a done. The apply makes the
      // directory and sets all three, and the same reading afterwards is what decides whether the
      // machine really ended up that way.
      return const CheckResult.ready();
    }
    final int raw = found.raw!;
    if (raw & _typeBits != _directoryBits) {
      return CheckResult.blocked(
        '$path is already on this machine and is ${_kindOf(raw)} rather than a directory. Nothing '
        'here takes away what somebody else put there, and handing it over instead would change '
        'the wrong thing while whatever needs a directory at this path still has none',
      );
    }
    if (found.owner == owner && found.group == group && raw & _modeBits == mode) {
      return CheckResult.satisfied(
        '$path is a directory owned by $owner:$group at ${_octal(mode)}',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final ({int? group, int? owner, int? raw, String? refusal}) found = await _found(context);
    if (found.refusal != null) {
      return StepPlan.argv(<String>['mkdir', '-p', path]);
    }
    if (found.owner != owner || found.group != group) {
      return StepPlan.argv(<String>['chown', _ownership, path]);
    }
    return StepPlan.argv(<String>['chmod', _octal(mode), path]);
  }

  @override
  Future<void> apply(StepContext context) async {
    await context.files.createDirectory(path, mode: mode, elevated: elevated);
    await _mustRun(context, <String>['chown', _ownership, path]);
    // THE MODE IS SET AGAIN, AND ON PURPOSE. The call above applies the mode to a directory it
    // MAKES; whether it also changes the mode of one that was already there is a property of the
    // tool it reaches for, and this step's postcondition does not rest on it. `chmod` on a
    // directory that already carries these bits changes nothing.
    await _mustRun(context, <String>['chmod', _octal(mode), path]);
  }

  /// What stood at the path before this step ran.
  ///
  /// The reading is taken TWICE where the first one does not answer, and the second question is the
  /// one that has a single meaning. `stat` exits non-zero both for a path that is not there and for
  /// one this run may not look at, and that difference is the whole of what the undo below acts on:
  /// a refusal read as an absence is an undo removing a directory this run did not make, while the
  /// engine is cleaning up after some OTHER step failed.
  @override
  Future<DirectoryBefore> capture(StepContext context) async {
    final ({int? group, int? owner, int? raw, String? refusal}) found = await _found(context);
    if (found.refusal == null) {
      return DirectoryBefore.carrying(
        owner: found.owner!,
        group: found.group!,
        mode: found.raw! & _modeBits,
      );
    }
    final ({List<String>? names, String? refusal}) parent = await _namesInParent(context);
    if (parent.refusal case final String refusal) {
      return DirectoryBefore.unread(refusal);
    }
    if (parent.names case final List<String> names when names.contains(_name)) {
      return DirectoryBefore.unread(found.refusal!);
    }
    // Either the parent holds no such name, or the parent itself is not there. Both say nothing
    // stands at the path, so whatever this run puts there is this run's to remove.
    return const DirectoryBefore.nothing();
  }

  @override
  Future<void> undo(StepContext context, DirectoryBefore captured) async {
    if (captured.refusal case final String refusal) {
      throw StateError(
        '$path is left exactly as it stands, because whether this run made it was never measured: '
        '$refusal',
      );
    }
    if (captured.absent) {
      // `rmdir` AND NEVER `rm -r`. This directory is one a workload writes into, and between the
      // apply and this undo it can already hold what that workload put there. `rmdir` refuses a
      // directory that is not empty and says so, which is what keeps a clean-up after some other
      // step's failure from taking a workload's data with it.
      await _mustRun(context, <String>['rmdir', path]);
      return;
    }
    await _mustRun(context, <String>['chown', '${captured.owner}:${captured.group}', path]);
    await _mustRun(context, <String>['chmod', _octal(captured.mode!), path]);
  }

  /// The owner, the group and the raw mode of whatever stands at the path, or why none of them was
  /// read.
  ///
  /// `%f` and not `%a`, because it carries BOTH facts in one reading and neither of them is
  /// translated: it is the mode exactly as the machine stores it, whose high bits say what kind of
  /// thing this is and whose low bits are the permissions. `%F` spells the kind out in words, and
  /// those words are in the language the machine was set to.
  Future<({int? group, int? owner, int? raw, String? refusal})> _found(StepContext context) async {
    final CommandResult stat = await context.shell.run(
      Command.observing('stat', arguments: <String>['-c', '%u %g %f', path], elevated: elevated),
    );
    if (!stat.ok) {
      return (
        owner: null,
        group: null,
        raw: null,
        refusal: 'stat did not answer about $path${_said(stat)}',
      );
    }
    final List<String> fields = stat.trimmed.split(RegExp(r'\s+'));
    final int? owner = fields.length == 3 ? int.tryParse(fields[0]) : null;
    final int? group = fields.length == 3 ? int.tryParse(fields[1]) : null;
    final int? raw = fields.length == 3 ? int.tryParse(fields[2], radix: 16) : null;
    if (owner == null || group == null || raw == null) {
      return (
        owner: null,
        group: null,
        raw: null,
        refusal:
            'stat answered "${stat.trimmed}" about $path, which is not the owner, the group and '
            'the raw mode it was asked for',
      );
    }
    return (owner: owner, group: group, raw: raw, refusal: null);
  }

  /// The names in the directory the path sits in, null where that directory is not there itself, or
  /// why it could not be read.
  ///
  /// `ls` and not [Files.list]: the files port answers the same for a directory that is not there
  /// and one this run may not enter, and which of the two it was is exactly the question here. The
  /// exit code of `ls` carries it — it names what is in a directory it may read and refuses one it
  /// may not — and the files port then says which of the two a refusal was.
  Future<({List<String>? names, String? refusal})> _namesInParent(StepContext context) async {
    final CommandResult listed = await context.shell.run(
      Command.observing('ls', arguments: <String>['-A', '--', _parent], elevated: elevated),
    );
    if (listed.ok) {
      return (
        names: <String>[
          for (final String line in listed.stdout.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ],
        refusal: null,
      );
    }
    if (!await context.files.exists(_parent, elevated: elevated)) {
      return (names: null, refusal: null);
    }
    return (
      names: null,
      refusal:
          '$_parent is there and could not be read, so whether $path was already on this machine '
          'was not measured${_said(listed)}',
    );
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(argv.first, arguments: argv.sublist(1), elevated: elevated),
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

  /// What `chown` is handed, which is the pair of numbers and never a pair of names.
  String get _ownership => '$owner:$group';

  /// The directory the path sits in.
  String get _parent {
    final String named = _withoutTrailingSeparator;
    final int cut = named.lastIndexOf('/');
    if (cut < 0) {
      return '.';
    }
    return cut == 0 ? '/' : named.substring(0, cut);
  }

  /// The name the path carries inside [_parent].
  String get _name => _withoutTrailingSeparator.split('/').last;

  /// The path with a trailing separator taken off, because `/a/b/` and `/a/b` name the same
  /// directory and only the second one splits into a parent and a name.
  String get _withoutTrailingSeparator =>
      path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  /// What the tool itself said about a reading that could not be taken, or nothing where it was
  /// silent.
  ///
  /// The machine's own sentence is what an operator acts on: "Permission denied" sends them to the
  /// elevation this row grants and "No such file or directory" sends them to whatever should have
  /// made the path, and one wording covering both would send them to neither.
  static String _said(CommandResult answer) =>
      answer.stderr.trim().isEmpty ? '' : ': ${answer.stderr.trim()}';

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

/// What stood at the path before [CreateDirectory] ran, which is what its undo puts back.
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
