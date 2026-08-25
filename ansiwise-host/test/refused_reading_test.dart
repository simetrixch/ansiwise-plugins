import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

/// A reading that was REFUSED is not an answer, measured on the two steps that stand between a
/// machine reached with a password and one reached with a key: the step that installs the key, and
/// the gate that proves sshd would accept it.
///
/// **What the gate decides on.** sshd refuses a key file, a key directory or a home directory it
/// considers too open, and it says nothing at all about why — the login falls back to a password,
/// which still works, so nothing looks wrong until the password is gone. The permission bits are
/// therefore the whole of what this gate measures, and `stat -c %a` is what reads them.
///
/// **What can happen to those readings.** The key file sits inside `.ssh`, which is `0700`, so to a
/// run that is neither that account nor root the operating system refuses every lookup under it —
/// and refuses it in the one way that looks exactly like an answer: `stat` writes nothing, and a
/// file test answers false because the lookup was refused rather than because the file is absent.
/// Two different states of the machine come back as the same bytes, and only the step can keep them
/// apart.
///
/// **Which readings are refused is a property of the PATH, and that is what the machine below
/// models.** Reading the metadata of `.ssh` needs the traverse bit on the HOME, which is `0755`, so
/// it answers to everybody and says nothing about whether this run may look inside. Only the
/// readings UNDER `.ssh` are refused. A listing of `.ssh` needs the same bit the file test needs and
/// fails where the file test answers false, which is what makes it the reading these steps decide
/// on.
///
/// **The row is built through [hostRegistry] from the KEYS the shipped programs write.** Both
/// programs that carry this step name one argument and leave `elevated` out, so that absence is what
/// the cases below run against — the step as an installation really runs it, not a shape invented to
/// make the case convenient. A row that grants root stands beside it, as the state that makes the
/// same machine answerable.
void main() {
  /// The account this run is preparing the machine for, and whose home everything below sits in.
  const String user = 'operator';

  /// The account a run that is neither that one nor root was started as.
  const String somebodyElse = 'installer';

  const String home = '/home/$user';
  const String directory = '$home/.ssh';
  const String keyFile = '$directory/authorized_keys';
  const String key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyForThisTest operator';

  /// A key somebody else already depends on, standing in the same file.
  const String colleague = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAnotherPersonsKey colleague';

  /// What sshd reports once it is allowed to resolve its configuration.
  const String sshdReports =
      'port 22\n'
      'pubkeyauthentication yes\n'
      'passwordauthentication yes';

  /// The row deploy-host writes one line above the gate: the same answer, and no `elevated` either.
  Step shippedInstallRow() => hostRegistry
      .step(const StepName('install_authorized_key'))!
      .create(const Arguments(<String, Object>{'public_key_answer': 'operator_public_key'}));

  /// The same step under a row that says the paths it writes are root's to read and write.
  Step installRowGrantingRoot() => hostRegistry
      .step(const StepName('install_authorized_key'))!
      .create(
        const Arguments(<String, Object>{
          'public_key_answer': 'operator_public_key',
          'elevated': true,
        }),
      );

  /// The row both shipped programs write: the answer holding the key, and nothing else.
  Step shippedRow() => hostRegistry
      .step(const StepName('require_key_login_possible'))!
      .create(const Arguments(<String, Object>{'public_key_answer': 'operator_public_key'}));

  /// The same step under a row that says the paths it reads are read as root.
  Step rowGrantingRoot() => hostRegistry
      .step(const StepName('require_key_login_possible'))!
      .create(
        const Arguments(<String, Object>{
          'public_key_answer': 'operator_public_key',
          'elevated': true,
        }),
      );

  /// A machine where everything INSIDE [directory] belongs to [user] and to nobody else.
  ///
  /// **WHICH READINGS ARE REFUSED IS A PROPERTY OF THE PATH, and getting it wrong measures a machine
  /// nobody has.** Reading the metadata of a path needs the traverse bit on every directory ABOVE
  /// it and nothing on the path itself. The home is `0755`, so `stat -c %a` on the home and on
  /// `.ssh` is answered to every account — it is the readings UNDER `.ssh` that are refused, because
  /// `.ssh` is `0700`. So the key file's own permissions and the listing of the directory holding it
  /// stand under [onlyTheOwnerMay], and the two readings above them do not.
  ///
  /// [modes] is what `stat` answers to a command that is allowed to ask, and [startedAs] is the
  /// account the run itself is. `sshd -T` is root's for a reason of its own — it reads every file
  /// its configuration includes — and `getent passwd` is answered to anybody, which is what makes it
  /// the innocent neighbour inside the machine itself.
  _Session machine({
    Map<String, String> modes = const <String, String>{},
    String startedAs = somebodyElse,
    List<String> keyDirectoryHolds = const <String>['authorized_keys'],
  }) => _Session(
    startedAs: startedAs,
    owner: user,
    onlyTheOwnerMay: <String, String>{
      'stat -c %a $keyFile': modes[keyFile] ?? '600',
      'ls -A -- $directory': keyDirectoryHolds.join('\n'),
    },
    onlyRootMay: const <String, String>{'sshd -T': sshdReports},
    answeredToAnybody: <String, String>{
      'getent passwd $user': '$user:x:1000:1000::$home:/bin/bash',
      'stat -c %a $home': modes[home] ?? '755',
      'stat -c %a $directory': modes[directory] ?? '700',
    },
  );

  StepContext contextOn(
    _Session session,
    _Lookups files, {
    StepName step = const StepName('require_key_login_possible'),
    Logger log = const _SilentLog(),
  }) => StepContext(
    shell: session,
    files: files,
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: log,
    step: step,
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'operator_user': user, 'operator_public_key': key}),
    facts: Facts.none,
    measurements: const _DiscardedMeasurements(),
  );

  StepContext installingOn(_Session session, _Lookups files, {Logger log = const _SilentLog()}) =>
      contextOn(session, files, step: const StepName('install_authorized_key'), log: log);

  /// A file system holding the key file, with everything under [directory] refused to a run that is
  /// neither its owner nor root.
  ///
  /// The home and the key directory are in it as paths of their own. A file system that held only
  /// the key file would answer "there is no .ssh" to a lookup of the directory, which is the state
  /// a first installation is in and not the one these cases are about.
  _Lookups holdingTheKey({String startedAs = somebodyElse, String content = '$key\n'}) => _Lookups(
    <String, String>{home: '', directory: '', keyFile: content},
    refusedUnder: startedAs == user ? null : directory,
  );

  test('THE PLANTED DEFECT: readings that were refused are not a verdict about the login', () async {
    // The row ships without `elevated`, so every `stat` arrives as the account the run was started
    // as and every one of them is refused. What the step must NOT do is compose a verdict out of
    // that: asked first, the file test answered false for a key file that is really there, and the
    // gate between installing a key and taking the password away reported it missing.
    final _Session session = machine();
    final _Lookups files = holdingTheKey();

    final CheckResult answer = await shippedRow().check(contextOn(session, files));

    expect(answer, isA<Blocked>(), reason: answer is Blocked ? answer.reason : '$answer');
    expect(
      (answer as Blocked).reason,
      isNot(contains('$keyFile is not there')),
      reason:
          'the key file is really there, and a gate that could not look at it must not state its '
          'absence as a finding about the machine',
    );
    expect(
      files.lookedFor,
      isNot(contains(keyFile)),
      reason:
          'the files port was asked about a path under a directory this run could not read, and '
          'its answer would have been an absence nobody measured',
    );
    expect(session.refused, isNotEmpty, reason: 'the readings this case is about were refused');
  });

  test('THE INNOCENT CASE: the same machine under a row that grants root is satisfied', () async {
    // The one thing that changed is the row. Same machine, same key, same paths — and every reading
    // answers, so the gate says what it exists to say.
    final _Session session = machine();
    final _Lookups files = holdingTheKey();

    final CheckResult answer = await rowGrantingRoot().check(contextOn(session, files));

    expect(answer, isA<Satisfied>(), reason: answer is Blocked ? answer.reason : '$answer');
    expect(session.refused, isEmpty);
    expect(files.lookedFor, contains(keyFile));
  });

  test(
    'THE INNOCENT CASE: a run that IS the account reads its own home under the shipped row',
    () async {
      // The shipped row is not wrong everywhere, and this is where it is right: the paths belong to
      // the account the run was started as, so nothing needs raising and nothing is refused. A red
      // result above therefore says the reading was refused, not that this row can never work.
      final _Session session = machine(startedAs: user);

      final CheckResult answer = await shippedRow().check(
        contextOn(session, holdingTheKey(startedAs: user)),
      );

      expect(answer, isA<Satisfied>(), reason: answer is Blocked ? answer.reason : '$answer');
      expect(session.refused, isEmpty);
    },
  );

  test('THE INNOCENT CASE: a key file that is really absent is still reported absent', () async {
    // The state this refusal must not swallow. The readings answer, the directory is there and is
    // 0700, and the file simply is not in it — which is a measurement of the machine and is reported
    // as one.
    final _Session session = machine(keyDirectoryHolds: const <String>[]);
    final _Lookups files = _Lookups(const <String, String>{directory: ''}, refusedUnder: null);

    final CheckResult answer = await rowGrantingRoot().check(contextOn(session, files));

    expect(answer, isA<Blocked>());
    expect(
      (answer as Blocked).reason,
      contains('$keyFile is not there'),
      reason: 'the listing answered and named nothing, which IS a measurement of the machine',
    );
    expect(session.carriedOut, contains('ls -A -- $directory'));
    expect(session.refused, isEmpty);
  });

  test('THE INNOCENT CASE: a permission that really is too open is reported as that', () async {
    // The other measurement this gate exists for, kept beside the refusals so a red result above
    // cannot mean the step blocks whatever it finds.
    final _Session session = machine(modes: const <String, String>{directory: '755'});

    final CheckResult answer = await rowGrantingRoot().check(contextOn(session, holdingTheKey()));

    expect(answer, isA<Blocked>());
    expect(session.refused, isEmpty);
  });

  test('THE PLANTED DEFECT: a key file that could not be looked at is not an absent one', () async {
    // The row one line above the gate, on the same machine, under the same missing elevation. The
    // file test is refused in the one way that looks like an answer, and the step read that as "the
    // account has no authorized_keys yet" - so it answered ready over a file it never saw.
    final _Session session = machine();
    final _Lookups files = holdingTheKey();

    final CheckResult answer = await shippedInstallRow().check(installingOn(session, files));

    expect(answer, isA<Blocked>(), reason: answer is Blocked ? answer.reason : '$answer');
    expect(
      files.lookedFor,
      isNot(contains(keyFile)),
      reason:
          'the key file was looked for under a directory this run could not read, and its answer '
          'would have been an absence nobody measured',
    );
  });

  test('THE PLANTED DEFECT: a dry run shows no file it could not read', () async {
    // The half that goes wrong with no elevation involved and nothing thrown to correct it. A plan
    // is what an operator reads to decide, and `before` used to be the empty text for a file
    // holding a colleague's key - the one sentence in the mode whose whole purpose is to say what
    // is there.
    final _Session session = machine();
    final _Lookups files = holdingTheKey(content: '$key\n$colleague\n');

    final StepPlan plan = await shippedInstallRow().plan(installingOn(session, files));

    expect(plan, isA<NothingPlan>(), reason: '$plan');
  });

  test('THE PLANTED DEFECT: an undo leaves a key file it could not read alone', () async {
    // capture answers the question "did the file already carry this key", and its false half is
    // what tells undo to strip the line. Answered false out of a refused lookup, the clean-up after
    // an unrelated failure takes away an access this run never granted.
    final _Session session = machine();
    final _Lookups files = holdingTheKey(content: '$key\n$colleague\n');
    final _NotedLog log = _NotedLog();
    final ReversibleStep<Object?> step = shippedInstallRow() as ReversibleStep<Object?>;

    final Object? captured = await step.capture(installingOn(session, files, log: log));
    await step.undo(installingOn(session, files, log: log), captured);

    expect(captured, isTrue, reason: 'a reading nobody took must not read as "it was not there"');
    expect(
      files.written,
      isEmpty,
      reason:
          'the file really carries two keys, and an undo over a reading it could not take would '
          'write one of them away',
    );
    expect(log.warned, isNotEmpty, reason: 'a capture that is not a measurement says so');
  });

  test('THE INNOCENT CASE: the same machine under a row that grants root reads the key', () async {
    // Every reading answers, the file really carries the key, and the step says so rather than
    // appending it a second time.
    final _Session session = machine();
    final _Lookups files = holdingTheKey();

    final CheckResult answer = await installRowGrantingRoot().check(installingOn(session, files));

    expect(answer, isA<Satisfied>(), reason: answer is Blocked ? answer.reason : '$answer');
    expect(files.lookedFor, contains(keyFile));
  });

  test('THE INNOCENT CASE: an account with no .ssh yet is ready to have one made', () async {
    // The first installation of a bare machine, which is the primary path of this step and the
    // state a refusal must never swallow: the home is there, `.ssh` is not, and there is nothing
    // to read.
    final _Session session = machine();
    final _Lookups files = _Lookups(const <String, String>{home: ''}, refusedUnder: directory);

    final CheckResult answer = await shippedInstallRow().check(installingOn(session, files));

    expect(answer, isA<Ready>(), reason: answer is Blocked ? answer.reason : '$answer');
  });

  test('THE INNOCENT CASE: a run that IS the account reads its own key file', () async {
    // The shipped row is right here, so a red result above says the reading was refused rather
    // than that this row can never work.
    final _Session session = machine(startedAs: user);

    final CheckResult answer = await shippedInstallRow().check(
      installingOn(session, holdingTheKey(startedAs: user)),
    );

    expect(answer, isA<Satisfied>(), reason: answer is Blocked ? answer.reason : '$answer');
  });

  test(
    'THE PLANTED DEFECT: an account database that could not be asked is not an absent account',
    () async {
      // `getent` exits 2 for a name it does not carry and something else for a question it could
      // not answer - a name service that is not running, a directory server that did not reply.
      // Read as the first, the second became "there is no account called operator on this
      // machine": a statement about the machine composed out of a reading nobody took.
      final _Session session = machine()..exits('getent passwd $user', 3);

      final CheckResult answer = await shippedInstallRow().check(
        installingOn(session, holdingTheKey()),
      );

      expect(answer, isA<Blocked>());
      expect(
        (answer as Blocked).reason,
        isNot(contains('there is no account')),
        reason: 'a database that would not answer is not a machine without the account',
      );
    },
  );

  test(
    'THE INNOCENT CASE: an account the database really does not carry is still reported absent',
    () async {
      // The state the refusal above must not swallow, in getent's own documented exit code for it.
      final _Session session = machine()..exits('getent passwd $user', 2);

      final CheckResult answer = await shippedInstallRow().check(
        installingOn(session, holdingTheKey()),
      );

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('there is no account'));
    },
  );

  test('THE INNOCENT NEIGHBOUR: what any account may read is read under either row', () async {
    // `getent passwd` reads the account database every account on the machine may read, so it comes
    // back whichever row is running. Without it, a red result above could mean this session refuses
    // everything rather than that an elevation was missing.
    for (final Step row in <Step>[shippedRow(), rowGrantingRoot()]) {
      final _Session session = machine();

      await row.check(contextOn(session, holdingTheKey()));

      expect(session.carriedOut, contains('getent passwd $user'));
    }
  });
}

/// A file system that records every path a step looked for, and answers as the operating system does
/// for anything under a directory this run may not enter.
///
/// **The refusing is the point and it is not a convenience.** A file test answers false when the
/// operating system refuses the lookup, exactly as it does when the file is not there, and that pair
/// is what this whole file is about. A fake that answered truthfully for a path inside a `0700`
/// directory would measure a machine nobody has.
final class _Lookups implements Files {
  /// Holds [contents], with everything under [refusedUnder] answered as a refused lookup — or
  /// nothing refused, where the run may read the whole tree.
  _Lookups(Map<String, String> contents, {required this.refusedUnder})
    : _contents = <String, String>{...contents};

  final Map<String, String> _contents;

  /// The directory this run may not look into, or null where it may read the whole tree.
  final String? refusedUnder;

  /// Every path this port was asked about, in the order it was asked.
  final List<String> lookedFor = <String>[];

  /// Every path this port was asked to write, in the order it was asked.
  final List<String> written = <String>[];

  /// Whether the operating system would refuse this run the lookup of [path].
  bool _refuses(String path, {required bool elevated}) =>
      !elevated && refusedUnder != null && path.startsWith('$refusedUnder/');

  @override
  Future<bool> exists(String path, {bool elevated = false}) async {
    lookedFor.add(path);
    return !_refuses(path, elevated: elevated) && _contents.containsKey(path);
  }

  @override
  Future<String> read(String path, {bool elevated = false}) async {
    lookedFor.add(path);
    final String? content = _refuses(path, elevated: elevated) ? null : _contents[path];
    if (content == null) {
      throw StateError('no such file: $path');
    }
    return content;
  }

  @override
  Future<List<String>> list(String path, {bool elevated = false}) async => const <String>[];

  @override
  Future<void> write(
    String path,
    String content, {
    required int mode,
    bool elevated = false,
  }) async {
    written.add(path);
    _contents[path] = content;
  }

  @override
  Future<void> delete(String path, {bool elevated = false}) async => _contents.remove(path);

  @override
  Future<void> createDirectory(String path, {required int mode, bool elevated = false}) async {}
}

/// A session on a machine, answering as the account the run was started as.
///
/// Three kinds of command, and the difference between them is what these cases turn on. What only
/// the OWNER of a home may have comes back to a run started as that account and to a command that
/// arrives as root, and to nobody else. What only ROOT may have comes back to an elevated command
/// alone, whoever the session is. What is answered to ANYBODY comes back every time, and is what
/// says a red result is about an elevation rather than about a session that refuses everything.
final class _Session implements Shell {
  /// Opens the session of [startedAs] on a machine whose guarded paths belong to [owner].
  _Session({
    required this.startedAs,
    required this.owner,
    required Map<String, String> onlyTheOwnerMay,
    required Map<String, String> onlyRootMay,
    required Map<String, String> answeredToAnybody,
  }) : _onlyTheOwnerMay = <String, String>{...onlyTheOwnerMay},
       _onlyRootMay = <String, String>{...onlyRootMay},
       _answeredToAnybody = <String, String>{...answeredToAnybody};

  /// The account the run itself is.
  final String startedAs;

  /// The account the guarded paths belong to.
  final String owner;

  final Map<String, String> _onlyTheOwnerMay;
  final Map<String, String> _onlyRootMay;
  final Map<String, String> _answeredToAnybody;

  /// The commands this session carried out.
  final Set<String> carriedOut = <String>{};

  /// The commands it refused, in the order it refused them.
  final List<String> refused = <String>[];

  /// The commands whose exit code this machine is made to answer with, whoever asks.
  final Map<String, int> _exits = <String, int>{};

  /// Makes [argv] answer [exitCode], for a tool whose exit code is what tells its states apart.
  void exits(String argv, int exitCode) => _exits[argv] = exitCode;

  @override
  Future<CommandResult> run(Command command) async {
    final String argv = command.argv.join(' ');
    if (_exits[argv] case final int exitCode) {
      refused.add(argv);
      return CommandResult(exitCode: exitCode, stdout: '', stderr: '', elapsed: Duration.zero);
    }
    if (_onlyTheOwnerMay[argv] case final String answer) {
      return command.elevated || startedAs == owner
          ? _answering(argv, answer)
          : _refusing(argv, 'stat: cannot statx: Permission denied');
    }
    if (_onlyRootMay[argv] case final String answer) {
      return command.elevated
          ? _answering(argv, answer)
          : _refusing(argv, 'sshd: no hostkeys available -- exiting.');
    }
    return _answering(argv, _answeredToAnybody[argv] ?? '');
  }

  CommandResult _answering(String argv, String stdout) {
    carriedOut.add(argv);
    return CommandResult(
      exitCode: 0,
      stdout: stdout.isEmpty ? '' : '$stdout\n',
      stderr: '',
      elapsed: Duration.zero,
    );
  }

  CommandResult _refusing(String argv, String said) {
    refused.add(argv);
    return CommandResult(exitCode: 1, stdout: '', stderr: '$said\n', elapsed: Duration.zero);
  }
}

/// A log that keeps what it was warned about, for the case where saying so IS the behaviour.
final class _NotedLog implements Logger {
  /// Every warning this log was given, in order.
  final List<String> warned = <String>[];

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) => warned.add(message);

  @override
  void error(String message) {}
}

/// A log that keeps nothing, so a step's own notes do not land in the middle of a test run.
final class _SilentLog implements Logger {
  const _SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}

/// A sink that keeps nothing: what these cases measure is the machine, not what was published.
final class _DiscardedMeasurements implements MeasurementSink {
  const _DiscardedMeasurements();

  @override
  void publish(MeasurementName name, String value) {}
}
