import 'package:ansiwise_core/ansiwise_core.dart';

/// Closes the password door, once the key door is known to work.
///
/// **This step is its own program on purpose.** The machine cannot prove that the operator's key
/// login works — the private half is on their laptop and never comes here. So the proof is theirs:
/// they connect with the key, and only then do they run this. A program that installed the key and
/// took the password away in one pass would be a program that locks somebody out of a machine they
/// can no longer reach, and no gate on this machine could catch it.
///
/// **The verdict comes from sshd's own resolved configuration, never from the file.** A drop-in in a
/// directory nothing includes changes nothing, and sshd says nothing about being ignored — the
/// password simply keeps working. Asking `sshd -T` afterwards is what turns that silence into a
/// failure.
final class DisablePasswordLogin extends ReversibleStep<String?> {
  /// Writes the setting into [dropIn].
  const DisablePasswordLogin({required this.dropIn, required this.reload, this.elevated = false});

  /// Builds the step from what the program gave it.
  factory DisablePasswordLogin.fromArguments(Arguments arguments) => DisablePasswordLogin(
    dropIn: arguments.text('drop_in'),
    reload: arguments.textList('reload'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // No default: the file's name is the product's choice, so the program row states it.
    ArgumentSpec(
      name: 'drop_in',
      kind: ArgumentKind.text,
      describes: 'the sshd configuration file this writes, inside the included directory',
    ),
    ArgumentSpec(
      name: 'reload',
      kind: ArgumentKind.textList,
      describes: 'how this machine is told to re-read the configuration',
      defaultValue: <String>['systemctl', 'reload', 'ssh'],
    ),
    // ASKED, never assumed. Whether the file this row points at belongs to root is a property of
    // that PATH, and this step is pointed at one by its row. A step deciding it for every caller
    // would be a tool package knowing something about the product that pointed it.
    ArgumentSpec(
      name: 'elevated',
      kind: ArgumentKind.flag,
      describes:
          'whether the file belongs to root, so reading and writing it need elevation. Leave it '
          'off for a path this account owns',
      required: false,
    ),
  ];

  /// The file this writes.
  ///
  /// A drop-in rather than an edit of `sshd_config`, so what this step owns is one file it can also
  /// remove — and so a machine's own configuration is left as its administrator wrote it.
  final String dropIn;

  /// The command that makes sshd re-read its configuration.
  final List<String> reload;

  /// What the file says.
  static const String content =
      '# Written by ansiwise. Password authentication is off; this machine is\n'
      '# reached by key. Remove this file and reload sshd to put it back.\n'
      'PasswordAuthentication no\n'
      'KbdInteractiveAuthentication no\n';

  /// Whether the drop-in belongs to root, so every read and write of it is elevated.
  final bool elevated;
  @override
  Future<CheckResult> check(StepContext context) async {
    final Map<String, String>? settings = await _effective(context);
    if (settings == null) {
      return const CheckResult.blocked(
        'sshd could not report its configuration, so nothing about a password login can be checked',
      );
    }

    final bool off =
        settings['passwordauthentication'] == 'no' &&
        settings['kbdinteractiveauthentication'] == 'no';
    return off
        ? const CheckResult.satisfied('sshd already refuses a password')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String before = await context.files.exists(dropIn, elevated: elevated)
        ? await context.files.read(dropIn, elevated: elevated)
        : '';
    return StepPlan.diff(dropIn, before: before, after: content);
  }

  @override
  Future<void> apply(StepContext context) async {
    await context.files.write(dropIn, content, mode: _configFile, elevated: elevated);

    final CommandResult reloaded = await context.shell.run(
      Command.detailed(reload.first, arguments: reload.sublist(1), elevated: true),
    );
    if (!reloaded.ok) {
      throw CommandFailed(
        argv: reload,
        exitCode: reloaded.exitCode,
        stdout: reloaded.stdout,
        stderr: reloaded.stderr,
      );
    }
  }

  /// What [dropIn] held before this step wrote it, or null when the file was not there.
  ///
  /// The apply writes over whatever stands at that path, so a machine whose administrator keeps
  /// their own settings in a file of this name has them replaced — and after that the captured text
  /// is the only copy left. Null is the file this step created, and that is the one case where
  /// taking it back means removing it rather than putting something back.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(dropIn, elevated: elevated)
      ? context.files.read(dropIn, elevated: elevated)
      : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      await context.files.delete(dropIn, elevated: elevated);
    } else {
      await context.files.write(dropIn, captured, mode: _configFile, elevated: elevated);
    }
    // Reloading is part of taking it back. A file removed while sshd still holds the old setting
    // leaves a machine that refuses a password for a reason nothing on disk explains any more.
    await context.shell.run(
      Command.detailed(reload.first, arguments: reload.sublist(1), elevated: true),
    );
  }

  /// The lines of `sshd -T`, which are `keyword value` in lower case.
  ///
  /// ELEVATED, and not from the row: resolving the configuration means reading the host keys and
  /// every file an Include names, and sshd refuses the whole answer to anybody but root. That is a
  /// property of sshd and not of the drop-in this row points at, so it is answered here the way the
  /// reload below is, and the same way `require_key_login_possible` asks the same question.
  ///
  /// Observing at the same time, which the two flags being independent is for: running as root does
  /// not make a command change anything, so a dry run still performs this.
  Future<Map<String, String>?> _effective(StepContext context) async {
    final CommandResult reported = await context.shell.run(
      const Command.observing('sshd', arguments: <String>['-T'], elevated: true),
    );
    if (!reported.ok) {
      return null;
    }
    final Map<String, String> settings = <String, String>{};
    for (final String line in reported.stdout.split('\n')) {
      final int space = line.indexOf(' ');
      if (space > 0) {
        settings[line.substring(0, space).toLowerCase()] = line.substring(space + 1).trim();
      }
    }
    return settings;
  }

  /// `0644` — sshd reads it, and there is nothing secret in it.
  static const int _configFile = 0x1a4;
}
