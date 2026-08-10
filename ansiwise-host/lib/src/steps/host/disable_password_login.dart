import 'package:ansiwise_api/ansiwise_api.dart';

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
  const DisablePasswordLogin({required this.dropIn, required this.reload});

  /// Builds the step from what the program gave it.
  factory DisablePasswordLogin.fromArguments(Arguments arguments) =>
      DisablePasswordLogin(dropIn: arguments.text('drop_in'), reload: arguments.textList('reload'));

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
    final String before = await context.files.exists(dropIn)
        ? await context.files.read(dropIn)
        : '';
    return StepPlan.diff(dropIn, before: before, after: content);
  }

  @override
  Future<void> apply(StepContext context) async {
    await context.files.write(dropIn, content, mode: _configFile);

    final CommandResult reloaded = await context.shell.run(
      Command(reload.first, reload.sublist(1)),
    );
    if (!reloaded.ok) {
      throw CommandFailed(argv: reload, exitCode: reloaded.exitCode, stderr: reloaded.stderr);
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
      await context.files.exists(dropIn) ? context.files.read(dropIn) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      await context.files.delete(dropIn);
    } else {
      await context.files.write(dropIn, captured, mode: _configFile);
    }
    // Reloading is part of taking it back. A file removed while sshd still holds the old setting
    // leaves a machine that refuses a password for a reason nothing on disk explains any more.
    await context.shell.run(Command(reload.first, reload.sublist(1)));
  }

  /// The lines of `sshd -T`, which are `keyword value` in lower case.
  Future<Map<String, String>?> _effective(StepContext context) async {
    final CommandResult reported = await context.shell.run(
      const Command.observing('sshd', <String>['-T']),
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
