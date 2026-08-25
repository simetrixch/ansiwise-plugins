import 'package:ansiwise_core/ansiwise_core.dart';

/// Which key a row means, and by which of the two routes a key reaches an `authorized_keys` file.
///
/// **There are two routes and a row names exactly one, because the two kinds of key are told apart
/// by where they come from rather than by what they look like.** A PERSON's key is answered: the
/// private half is in their keychain and never comes to this machine, so somebody types the public
/// half when the run is started. A key MINTED DURING THE RUN cannot be answered by anybody — it did
/// not exist when the run was started — so it reaches this row as a measurement the step that minted
/// it published.
///
/// **Neither is a fixed answer name in this package.** Which answer holds a person's key is a fact
/// of the program, so the row names it and the resolver holds that program to declaring it. A name
/// written here instead would force every program that installs a minted key to declare an answer
/// nobody is asked for and nothing reads.
///
/// **A public key is not a secret.** It is what one hands out, so nothing here is redacted and the
/// value may stand in a plan an operator reads.
final class AuthorizedKeySource {
  /// Names the key as a row names it: as a value, as an answer, or — wrongly — as neither or both.
  const AuthorizedKeySource({required this.key, required this.answer});

  /// Builds the source from what the program gave the step carrying it.
  factory AuthorizedKeySource.fromArguments(Arguments arguments) => AuthorizedKeySource(
    key: arguments.optionalText('public_key'),
    answer: arguments.optionalText('public_key_answer'),
  );

  /// The arguments every step that installs or proves one key declares.
  ///
  /// Declared ONCE and spread into both, so the step that writes the key and the gate that proves
  /// it was written cannot come to mean different keys.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'public_key',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the key, as the one line an authorized_keys file carries — for a row that takes it from '
          'a measurement of this run, which is the only way a key minted while the run was going '
          'can reach here. Leave it off where a person supplies the key',
    ),
    ArgumentSpec(
      name: 'public_key_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer holding the key — for the key a person supplies, whose private '
          'half stays in their keychain and never comes to this machine. Leave it off where the '
          'key is taken from a measurement instead',
    ),
  ];

  /// The key written into the row, or null where the row names an answer instead.
  final String? key;

  /// The name of the answer holding the key, or null where the row writes the key itself.
  final String? answer;

  /// The key this row means, or why it means none.
  AuthorizedKey keyIn(StepContext context) {
    if (key != null && answer != null) {
      return const AuthorizedKey.unnamed(
        'this row names both public_key and public_key_answer, and one file line holds one key — '
        'write the key where the run measured it, or name the answer a person fills, never both',
      );
    }
    if (key case final String written) {
      return written.trim().isEmpty
          ? const AuthorizedKey.unnamed(
              'public_key of this row is empty. Where it is filled from a measurement, the row that '
              'publishes that value has not run or published nothing',
            )
          : AuthorizedKey.of(written.trim());
    }
    if (answer case final String named) {
      final String? held = context.answers.optionalText(named);
      return held == null || held.trim().isEmpty
          ? AuthorizedKey.unnamed('this run holds no answer "$named", and the key is read from it')
          : AuthorizedKey.of(held.trim());
    }
    return const AuthorizedKey.unnamed(
      'this row says nothing about which key it means: name public_key to take one a row of this '
      'run measured, or public_key_answer to take the one a person answered',
    );
  }
}

/// The one key a row means, or why it means none.
final class AuthorizedKey {
  /// Records the key, as the one line a file carries it on.
  const AuthorizedKey.of(String this.line) : refusal = null;

  /// Records that the row names no key, because [refusal].
  const AuthorizedKey.unnamed(String this.refusal) : line = null;

  /// The key, or null when there is none to be had.
  final String? line;

  /// Why there is none, or null when there is.
  final String? refusal;
}

/// Puts a public key where sshd will look for it, for the account the run names.
///
/// This is the first half of turning a machine reached with a password into one reached with a key.
/// The second half — switching the password off — must not happen until this one has been proven,
/// and the program is what keeps them in that order.
///
/// **The key is appended, never written over the file.** A machine may already carry keys that
/// somebody else depends on, and replacing the file would take away access nobody asked to lose.
/// That also makes the undo narrow: it removes the one line it added and leaves the rest.
final class InstallAuthorizedKey extends ReversibleStep<bool> {
  /// Installs the key [key] names, for the account the run names.
  const InstallAuthorizedKey({required this.key, this.elevated = false});

  /// Builds the step from what the program gave it.
  factory InstallAuthorizedKey.fromArguments(Arguments arguments) => InstallAuthorizedKey(
    key: AuthorizedKeySource.fromArguments(arguments),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  ///
  /// The ACCOUNT is not among them: it is what the machine's provider made, so it is answered by
  /// whoever runs this and never written into a program file that ships to everybody. Which key is
  /// installed is the row's to say, and [AuthorizedKeySource] carries the two ways of saying it.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ...AuthorizedKeySource.arguments,
    elevationArgument,
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The account alone. The KEY is not here even where a row takes it from an answer: which answer
  /// that is, is the row's to name, so it is declared as an argument of kind
  /// [ArgumentKind.answerName] and the program is held to declaring the name it writes there. A
  /// fixed name here would make every program that installs a MINTED key declare an answer nobody
  /// is ever asked for and nothing ever reads.
  static const List<String> answers = <String>[userAnswer];

  /// The name the account is answered under.
  static const String userAnswer = 'operator_user';

  /// The account whose `authorized_keys` this writes, as [context] was answered.
  static String userIn(StepContext context) => context.answers.text(userAnswer);

  /// Which key this row installs, and where its value comes from.
  final AuthorizedKeySource key;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;

  @override
  Future<CheckResult> check(StepContext context) async {
    final AuthorizedKey installing = key.keyIn(context);
    if (installing.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String? home = await _home(context);
    if (home == null) {
      return CheckResult.blocked('there is no account called "${userIn(context)}" on this machine');
    }

    final String path = '$home/.ssh/authorized_keys';
    if (!await context.files.exists(path, elevated: elevated)) {
      return const CheckResult.ready();
    }

    final String present = await context.files.read(path, elevated: elevated);
    return _lines(present).contains(installing.line)
        ? CheckResult.satisfied('the key is already in $path')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final AuthorizedKey installing = key.keyIn(context);
    if (installing.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final String? home = await _home(context);
    if (home == null) {
      return StepPlan.nothing('there is no account called "${userIn(context)}"');
    }
    final String path = '$home/.ssh/authorized_keys';
    final String before = await context.files.exists(path, elevated: elevated)
        ? await context.files.read(path, elevated: elevated)
        : '';
    return StepPlan.diff(path, before: before, after: _appendedTo(before, installing.line ?? ''));
  }

  @override
  Future<void> apply(StepContext context) async {
    final AuthorizedKey installing = key.keyIn(context);
    if (installing.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final String? home = await _home(context);
    if (home == null) {
      throw CommandFailed(
        argv: <String>['getent', 'passwd', userIn(context)],
        exitCode: 2,
        stdout: '',
        stderr: 'there is no account called "${userIn(context)}"',
      );
    }

    // The directory before the file, and both before the content — sshd refuses to read a key file
    // it considers too open, and it says nothing about why. That silence is the failure this whole
    // ordering exists to avoid, so the modes are set as part of writing rather than afterwards.
    await context.files.createDirectory('$home/.ssh', mode: _sshDirectory, elevated: elevated);

    final String path = '$home/.ssh/authorized_keys';
    final String before = await context.files.exists(path, elevated: elevated)
        ? await context.files.read(path, elevated: elevated)
        : '';
    await context.files.write(
      path,
      _appendedTo(before, installing.line ?? ''),
      mode: _keyFile,
      elevated: elevated,
    );

    await _own(context, '$home/.ssh');
    await _own(context, path);
  }

  /// Whether the account's `authorized_keys` already carried this key before the run.
  ///
  /// The line is identical whoever put it there, so once the apply has appended it the file cannot
  /// say any more which of the two it was. A key that was already in the file is somebody's working
  /// access, and taking it out while cleaning up after a failure would lock them out of a machine
  /// this run never let them into.
  @override
  Future<bool> capture(StepContext context) async {
    final AuthorizedKey installing = key.keyIn(context);
    if (installing.line == null) {
      return false;
    }
    final String? home = await _home(context);
    if (home == null) {
      return false;
    }
    final String path = '$home/.ssh/authorized_keys';
    if (!await context.files.exists(path, elevated: elevated)) {
      return false;
    }
    return _lines(await context.files.read(path, elevated: elevated)).contains(installing.line);
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    final AuthorizedKey installing = key.keyIn(context);
    if (installing.line == null) {
      return;
    }
    final String? home = await _home(context);
    if (home == null) {
      return;
    }
    final String path = '$home/.ssh/authorized_keys';
    if (!await context.files.exists(path, elevated: elevated)) {
      return;
    }

    // Only the line this step added. Another key in the same file belongs to somebody else, and an
    // undo runs while cleaning up after a failure — the worst moment to take away an access nobody
    // asked to lose.
    final List<String> kept = _lines(
      await context.files.read(path, elevated: elevated),
    ).where((String line) => line != installing.line).toList();
    await context.files.write(
      path,
      kept.isEmpty ? '' : '${kept.join('\n')}\n',
      mode: _keyFile,
      elevated: elevated,
    );
  }

  static List<String> _lines(String content) =>
      content.split('\n').map((String l) => l.trim()).where((String l) => l.isNotEmpty).toList();

  static String _appendedTo(String before, String line) {
    final List<String> lines = _lines(before);
    if (!lines.contains(line)) {
      lines.add(line);
    }
    return '${lines.join('\n')}\n';
  }

  /// The account's home directory, read from the machine rather than guessed.
  ///
  /// `~` is not a path, it is something a shell expands, and this framework never goes through a
  /// shell. The sixth field of a passwd entry is where the account actually lives, which is also
  /// where it lives when it is not under `/home`.
  ///
  /// NOT ELEVATED, and that is an answer rather than a silence: `getent passwd` reads the account
  /// database every account on the machine may read, so root sees exactly what the operator sees.
  /// The row's elevation is about the key file under the home this returns, and it is passed to
  /// every read and write of that.
  static Future<String?> _home(StepContext context) async {
    final CommandResult entry = await context.shell.run(
      Command.observing('getent', arguments: <String>['passwd', userIn(context)], elevated: false),
    );
    if (!entry.ok) {
      return null;
    }
    final List<String> fields = entry.trimmed.split(':');
    return fields.length < 6 || fields[5].isEmpty ? null : fields[5];
  }

  static Future<void> _own(StepContext context, String path) async {
    final CommandResult owned = await context.shell.run(
      Command.detailed(
        'chown',
        arguments: <String>['${userIn(context)}:${userIn(context)}', path],
        elevated: true,
      ),
    );
    if (!owned.ok) {
      throw CommandFailed(
        argv: <String>['chown', '${userIn(context)}:${userIn(context)}', path],
        exitCode: owned.exitCode,
        stdout: '',
        stderr: owned.stderr,
      );
    }
  }

  /// `0700` — sshd refuses a key directory anybody else can enter.
  static const int _sshDirectory = 0x1c0;

  /// `0600` — and a key file anybody else can read.
  static const int _keyFile = 0x180;
}
