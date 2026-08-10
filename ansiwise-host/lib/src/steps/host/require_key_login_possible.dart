import 'package:ansiwise_api/ansiwise_api.dart';

import 'install_authorized_key.dart';

/// Refuses to go on unless everything that has to be true for a key login is true.
///
/// **This is the gate between installing the key and switching the password off**, and it exists
/// because the failure it prevents is the worst one this program can produce: an operator locked out
/// of a machine they can no longer reach.
///
/// **What it cannot do, stated first so nobody mistakes what it proves.** The operator's private key
/// is on their laptop and never comes here, so this machine cannot perform the login. The last
/// step of the proof — actually connecting with the key — belongs to whoever holds the private half,
/// and the program that disables the password must not run until they have done it.
///
/// **What it can do covers the failure that actually happens.** sshd refuses to read a key file it
/// considers too open, and it says nothing at all about why: the login simply falls back to a
/// password, which still works, so nothing looks wrong until the password is gone. Every check here
/// is a way that silence can arise.
final class RequireKeyLoginPossible extends ObservingStep {
  /// Refuses unless the account this run names could be reached by key.
  const RequireKeyLoginPossible();

  /// Builds the step from what the program gave it.
  factory RequireKeyLoginPossible.fromArguments(Arguments arguments) =>
      const RequireKeyLoginPossible();

  /// What this step accepts, which is nothing.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The same two the key was installed under, by the same names — this step proves what that one
  /// did, so a second pair of values here would let it pass on a key nobody installed.
  static const List<String> answers = InstallAuthorizedKey.answers;

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String> wrong = <String>[];

    // sshd's own effective configuration, not the file — an Include, a Match block or a package
    // default can say something the file does not, and what decides a login is what sshd resolved.
    final CommandResult effective = await context.shell.run(
      const Command.observing('sshd', <String>['-T']),
    );
    if (!effective.ok) {
      return CheckResult.blocked(
        'sshd could not report its configuration, so nothing about a key login can be checked: '
        '${effective.stderr.trim()}',
      );
    }
    final Map<String, String> settings = _settings(effective.stdout);

    if (settings['pubkeyauthentication'] != 'yes') {
      wrong.add('sshd has public key authentication switched off');
    }

    final String? home = await _home(context);
    if (home == null) {
      return CheckResult.blocked(
        'there is no account called "${InstallAuthorizedKey.userIn(context)}" on this machine',
      );
    }
    final String path = '$home/.ssh/authorized_keys';

    if (!await context.files.exists(path)) {
      wrong.add('$path is not there');
    } else {
      final List<String> lines = (await context.files.read(
        path,
      )).split('\n').map((String l) => l.trim()).toList();
      if (!lines.contains(InstallAuthorizedKey.keyIn(context))) {
        wrong.add('$path does not carry this key');
      }
      wrong.addAll(await _tooOpen(context, path, _keyFile));
    }

    wrong.addAll(await _tooOpen(context, '$home/.ssh', _sshDirectory));
    // A home directory anybody else can write to is refused by sshd as well, and this is the one
    // people are most surprised by: the key file's own permissions look right, and the login still
    // falls through to a password.
    wrong.addAll(await _groupOrWorldWritable(context, home));

    if (wrong.isEmpty) {
      return CheckResult.satisfied(
        'sshd would accept this key for ${InstallAuthorizedKey.userIn(context)}',
      );
    }
    // Every reason at once. An operator who fixes one permission, runs again and is told about the
    // next has paid for two runs to learn what one could have said.
    return CheckResult.blocked('a key login would not work: ${wrong.join('; ')}');
  }

  /// The lines of `sshd -T`, which are `keyword value` in lower case.
  static Map<String, String> _settings(String output) {
    final Map<String, String> settings = <String, String>{};
    for (final String line in output.split('\n')) {
      final int space = line.indexOf(' ');
      if (space <= 0) {
        continue;
      }
      settings[line.substring(0, space).toLowerCase()] = line.substring(space + 1).trim();
    }
    return settings;
  }

  Future<String?> _home(StepContext context) async {
    final CommandResult entry = await context.shell.run(
      Command.observing('getent', <String>['passwd', InstallAuthorizedKey.userIn(context)]),
    );
    if (!entry.ok) {
      return null;
    }
    final List<String> fields = entry.trimmed.split(':');
    return fields.length < 6 || fields[5].isEmpty ? null : fields[5];
  }

  Future<List<String>> _tooOpen(StepContext context, String path, int most) async {
    final int? mode = await _mode(context, path);
    if (mode == null) {
      return <String>['the permissions of $path could not be read'];
    }
    return mode & ~most == 0
        ? const <String>[]
        : <String>['$path is ${_octal(mode)} and sshd needs at most ${_octal(most)}'];
  }

  Future<List<String>> _groupOrWorldWritable(StepContext context, String path) async {
    final int? mode = await _mode(context, path);
    if (mode == null) {
      return <String>['the permissions of $path could not be read'];
    }
    return mode & 0x12 == 0
        ? const <String>[]
        : <String>['$path is ${_octal(mode)}, and sshd refuses a home anybody else can write to'];
  }

  Future<int?> _mode(StepContext context, String path) async {
    final CommandResult stat = await context.shell.run(
      Command.observing('stat', <String>['-c', '%a', path]),
    );
    return stat.ok ? int.tryParse(stat.trimmed, radix: 8) : null;
  }

  static String _octal(int mode) => mode.toRadixString(8).padLeft(3, '0');

  /// `0700`.
  static const int _sshDirectory = 0x1c0;

  /// `0600`.
  static const int _keyFile = 0x180;
}
