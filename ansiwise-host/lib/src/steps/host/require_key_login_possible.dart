import 'package:ansiwise_core/ansiwise_core.dart';

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
  /// Refuses unless the account this run names could be reached with the key [key] names.
  const RequireKeyLoginPossible({required this.key, this.elevated = false});

  /// Builds the step from what the program gave it.
  factory RequireKeyLoginPossible.fromArguments(Arguments arguments) => RequireKeyLoginPossible(
    key: AuthorizedKeySource.fromArguments(arguments),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  ///
  /// The same way of naming a key as the step that installs one, spread from the same list — this
  /// step proves what that one did, so a second way of saying which key is meant would let it pass
  /// on a key nobody installed.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ...AuthorizedKeySource.arguments,
    elevationArgument,
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The account, by the same name the installing step reads it under. The key is not here for the
  /// reason it is not there: which answer holds it is the row's to name.
  static const List<String> answers = InstallAuthorizedKey.answers;

  /// Which key this row proves, and where its value comes from.
  final AuthorizedKeySource key;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;

  @override
  bool get restsOnAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final AuthorizedKey proving = key.keyIn(context);
    if (proving.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final List<String> wrong = <String>[];

    // sshd's own effective configuration, not the file — an Include, a Match block or a package
    // default can say something the file does not, and what decides a login is what sshd resolved.
    //
    // ELEVATED, and observing at the same time. Resolving the configuration means READING every file
    // it includes, and an installer that drops one in with root-only permissions makes `sshd -T`
    // refuse the whole answer rather than skip that file. Measured on a machine: it reported
    // "50-cloud-init.conf: Permission denied" and this check could say nothing about a login it had
    // every other means to judge.
    //
    // The two flags are independent by design and this is the case they were made independent for:
    // running as root does not make a command change anything, so this stays something a dry run may
    // perform.
    final CommandResult effective = await context.shell.run(
      const Command.detailed('sshd', arguments: <String>['-T'], observes: true, elevated: true),
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
    final String directory = '$home/.ssh';
    final String path = '$directory/authorized_keys';

    // THE DIRECTORY IS READ BEFORE THE FILE IS LOOKED FOR, and that order is the whole of it.
    // `.ssh` is 0700, so to a run that is neither its account nor root every question asked under it
    // answers exactly as it would about a path that is not there: `stat` writes nothing, and the
    // files port answers false because the operating system refused the lookup rather than because
    // the file is absent. Asked first, the file test put "$path is not there" among the findings —
    // an absence nobody measured, standing in the sentence that says whether a key login would work.
    //
    // A home directory anybody else can write to is refused by sshd as well, and this is the one
    // people are most surprised by: the key file's own permissions look right, and the login still
    // falls through to a password.
    final List<({String? tooOpen, String? unread})> permissions =
        <({String? tooOpen, String? unread})>[
          await _tooOpen(context, directory, _sshDirectory),
          await _groupOrWorldWritable(context, home),
        ];
    if (_unreadIn(permissions).isEmpty) {
      if (!await context.files.exists(path, elevated: elevated)) {
        wrong.add('$path is not there');
      } else {
        final List<String> lines = (await context.files.read(
          path,
          elevated: elevated,
        )).split('\n').map((String l) => l.trim()).toList();
        if (!lines.contains(proving.line)) {
          wrong.add('$path does not carry this key');
        }
        permissions.add(await _tooOpen(context, path, _keyFile));
      }
    }

    wrong.addAll(<String>[
      for (final ({String? tooOpen, String? unread}) reading in permissions)
        if (reading.tooOpen case final String said) said,
    ]);
    final List<String> unread = _unreadIn(permissions);

    // A READING THAT COULD NOT BE TAKEN IS NOT A VERDICT ABOUT THE MACHINE. These permissions are
    // what sshd decides a key login on, so a run that could not read them has measured nothing about
    // the login — and this sentence used to stand inside "a key login would not work", which is a
    // statement about the machine made out of a look nobody managed to take.
    if (unread.isNotEmpty) {
      return CheckResult.blocked(
        'whether a key login would work could not be judged: ${unread.join('; ')}. sshd decides a '
        'key login on exactly those permissions, and they are inside the home of '
        '"${InstallAuthorizedKey.userIn(context)}" — a run that is neither that account nor root '
        'reads none of them, and the elevated argument of this row is what says whether they are '
        'read as root'
        '${wrong.isEmpty ? '' : '. What could be read is already wrong: ${wrong.join('; ')}'}',
      );
    }

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

  /// Where the account this run names lives, or null where there is no such account.
  ///
  /// NOT ELEVATED, and that is an answer rather than a silence: `getent passwd` reads the account
  /// database every account on the machine may read, so root sees exactly what the operator sees.
  /// Raising it would ask for the elevation password on a machine that never needed one, and turn a
  /// run whose installation configured none into a refusal over a lookup anybody may make.
  Future<String?> _home(StepContext context) async {
    final CommandResult entry = await context.shell.run(
      Command.observing(
        'getent',
        arguments: <String>['passwd', InstallAuthorizedKey.userIn(context)],
        elevated: false,
      ),
    );
    if (!entry.ok) {
      return null;
    }
    final List<String> fields = entry.trimmed.split(':');
    return fields.length < 6 || fields[5].isEmpty ? null : fields[5];
  }

  /// What is too open about [path], or that its permissions could not be read at all.
  ///
  /// The two are kept apart all the way to the verdict: the first is a measurement of the machine
  /// and the second is a statement about this check, and one list holding both is what let the gate
  /// answer "a key login would not work" over a reading nobody took.
  Future<({String? tooOpen, String? unread})> _tooOpen(
    StepContext context,
    String path,
    int most,
  ) async {
    final CommandResult stat = await _stat(context, path);
    final int? mode = _bitsIn(stat);
    if (mode == null) {
      return (tooOpen: null, unread: _unreadable(path, stat));
    }
    return mode & ~most == 0
        ? (tooOpen: null, unread: null)
        : (
            tooOpen: '$path is ${_octal(mode)} and sshd needs at most ${_octal(most)}',
            unread: null,
          );
  }

  /// See [_tooOpen]: the same pair, for the one bit sshd refuses a home directory over.
  Future<({String? tooOpen, String? unread})> _groupOrWorldWritable(
    StepContext context,
    String path,
  ) async {
    final CommandResult stat = await _stat(context, path);
    final int? mode = _bitsIn(stat);
    if (mode == null) {
      return (tooOpen: null, unread: _unreadable(path, stat));
    }
    return mode & 0x12 == 0
        ? (tooOpen: null, unread: null)
        : (
            tooOpen: '$path is ${_octal(mode)}, and sshd refuses a home anybody else can write to',
            unread: null,
          );
  }

  /// Why any of [readings] did not answer, in the order they were taken.
  static List<String> _unreadIn(List<({String? tooOpen, String? unread})> readings) => <String>[
    for (final ({String? tooOpen, String? unread}) reading in readings)
      if (reading.unread case final String why) why,
  ];

  /// What `stat` answers when it is asked for the permission bits of [path].
  ///
  /// AT THIS ROW'S ELEVATION, like the reads of the same path through the files port above. The
  /// paths asked about are inside the account's home and `.ssh` is `0700`, so a run that is neither
  /// that account nor root is answered "Permission denied". The RESULT is handed back rather than a
  /// number, because what the callers do with a reading that did not answer is the whole point: they
  /// report it as a reading that was not taken, never as a permission that is wrong, and the check
  /// refuses to answer at all rather than answer about a machine it could not look at.
  Future<CommandResult> _stat(StepContext context, String path) => context.shell.run(
    Command.observing('stat', arguments: <String>['-c', '%a', path], elevated: elevated),
  );

  /// The permission bits [stat] answered with, or null where it answered none.
  static int? _bitsIn(CommandResult stat) => stat.ok ? int.tryParse(stat.trimmed, radix: 8) : null;

  /// That the permissions of [path] were not read, in the tool's own words.
  ///
  /// The machine's own sentence is what an operator acts on: "Permission denied" sends them to the
  /// elevation this row grants, and "No such file or directory" sends them to the step that installs
  /// the key. One wording covering both would send them to neither.
  static String _unreadable(String path, CommandResult stat) =>
      'the permissions of $path were not read: '
      '${stat.stderr.trim().isEmpty ? 'stat exited ${stat.exitCode} and wrote nothing' : stat.stderr.trim()}';

  static String _octal(int mode) => mode.toRadixString(8).padLeft(3, '0');

  /// `0700`.
  static const int _sshDirectory = 0x1c0;

  /// `0600`.
  static const int _keyFile = 0x180;
}
