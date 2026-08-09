import 'package:ansiwise_api/ansiwise_api.dart';

/// Puts the operator's public key where sshd will look for it.
///
/// This is the first half of turning a machine reached with a password into one reached with a key.
/// The second half — switching the password off — must not happen until this one has been proven,
/// and the program is what keeps them in that order.
///
/// **The key is appended, never written over the file.** A machine may already carry keys that
/// somebody else depends on, and replacing the file would take away access nobody asked to lose.
/// That also makes the undo narrow: it removes the one line it added and leaves the rest.
final class InstallAuthorizedKey extends ReversibleStep {
  /// Installs the operator's key for the account the run names.
  const InstallAuthorizedKey();

  /// Builds the step from what the program gave it.
  factory InstallAuthorizedKey.fromArguments(Arguments arguments) => const InstallAuthorizedKey();

  /// What this step accepts, which is nothing.
  ///
  /// Both the account and the key belong to one installation — the account is what the machine's
  /// provider made, the key is the operator's own — so they are answered by whoever runs this and
  /// never written into a program file that ships to everybody.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The key is not answered as a secret: a public key is what one hands out. The private half
  /// never reaches this machine at all — it stays in the operator's keychain, which is why the
  /// proof that the login works cannot be performed here.
  static const List<String> answers = <String>[userAnswer, keyAnswer];

  /// The name the account is answered under.
  static const String userAnswer = 'operator_user';

  /// The name the key is answered under.
  static const String keyAnswer = 'operator_public_key';

  /// The account whose `authorized_keys` this writes, as [context] was answered.
  static String userIn(StepContext context) => context.answers.text(userAnswer);

  /// The key this installs, as one line.
  static String keyIn(StepContext context) => context.answers.text(keyAnswer).trim();

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? home = await _home(context);
    if (home == null) {
      return CheckResult.blocked('there is no account called "${userIn(context)}" on this machine');
    }

    final String path = '$home/.ssh/authorized_keys';
    if (!await context.files.exists(path)) {
      return const CheckResult.ready();
    }

    final String present = await context.files.read(path);
    return _lines(present).contains(keyIn(context))
        ? CheckResult.satisfied('the key is already in $path')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? home = await _home(context);
    if (home == null) {
      return StepPlan.nothing('there is no account called "${userIn(context)}"');
    }
    final String path = '$home/.ssh/authorized_keys';
    final String before = await context.files.exists(path) ? await context.files.read(path) : '';
    return StepPlan.diff(path, before: before, after: _appendedTo(before, keyIn(context)));
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? home = await _home(context);
    if (home == null) {
      throw CommandFailed(
        argv: <String>['getent', 'passwd', userIn(context)],
        exitCode: 2,
        stderr: 'there is no account called "${userIn(context)}"',
      );
    }

    // The directory before the file, and both before the content — sshd refuses to read a key file
    // it considers too open, and it says nothing about why. That silence is the failure this whole
    // ordering exists to avoid, so the modes are set as part of writing rather than afterwards.
    await context.files.createDirectory('$home/.ssh', mode: _sshDirectory);

    final String path = '$home/.ssh/authorized_keys';
    final String before = await context.files.exists(path) ? await context.files.read(path) : '';
    await context.files.write(path, _appendedTo(before, keyIn(context)), mode: _keyFile);

    await _own(context, '$home/.ssh');
    await _own(context, path);
  }

  @override
  Future<void> undo(StepContext context) async {
    final String? home = await _home(context);
    if (home == null) {
      return;
    }
    final String path = '$home/.ssh/authorized_keys';
    if (!await context.files.exists(path)) {
      return;
    }

    // Only the line this step added. Another key in the same file belongs to somebody else, and an
    // undo runs while cleaning up after a failure — the worst moment to take away an access nobody
    // asked to lose.
    final List<String> kept = _lines(
      await context.files.read(path),
    ).where((String line) => line != keyIn(context)).toList();
    await context.files.write(path, kept.isEmpty ? '' : '${kept.join('\n')}\n', mode: _keyFile);
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
  static Future<String?> _home(StepContext context) async {
    final CommandResult entry = await context.shell.run(
      Command.observing('getent', <String>['passwd', userIn(context)]),
    );
    if (!entry.ok) {
      return null;
    }
    final List<String> fields = entry.trimmed.split(':');
    return fields.length < 6 || fields[5].isEmpty ? null : fields[5];
  }

  static Future<void> _own(StepContext context, String path) async {
    final CommandResult owned = await context.shell.run(
      Command('chown', <String>['${userIn(context)}:${userIn(context)}', path]),
    );
    if (!owned.ok) {
      throw CommandFailed(
        argv: <String>['chown', '${userIn(context)}:${userIn(context)}', path],
        exitCode: owned.exitCode,
        stderr: owned.stderr,
      );
    }
  }

  /// `0700` — sshd refuses a key directory anybody else can enter.
  static const int _sshDirectory = 0x1c0;

  /// `0600` — and a key file anybody else can read.
  static const int _keyFile = 0x180;
}
