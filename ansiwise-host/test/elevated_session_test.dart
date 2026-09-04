import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

/// What a step grants a command has to reach the SESSION it runs in, and this measures that.
///
/// **Why the session and not the field.** A test that reads `Command.elevated` back off the command
/// a step composed proves the step wrote a value down; it says nothing about the account the command
/// then runs as. The failure this whole audit exists for is exactly that gap: the value was written
/// in one place, dropped one call later, and the run went out as the operator with the record saying
/// root had been granted.
///
/// So the machine here is a SESSION. [_Session] answers as the account a run was started as, its
/// supplementary groups fixed when it was constructed — a process reads its groups once, when the
/// session begins, so a row that puts the account into a group grants the next session and never
/// this one. Nothing but a command arriving elevated widens what this session may reach, and what it
/// refuses it refuses in the tool's own words.
void main() {
  const String user = 'operator';
  const String home = '/home/$user';
  const String keyFile = '$home/.ssh/authorized_keys';
  const String key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyForThisTest operator';
  const String dropIn = '/etc/ssh/sshd_config.d/50-no-password.conf';
  const String askSshd = 'sshd -T';
  const String readPasswdEntry = 'getent passwd $user';
  const String dataFilesystem = '/mnt/data';
  const String askMountpoint = 'mountpoint -q $dataFilesystem';

  /// The group whose members may read the account database, which every account is in.
  const String everybody = 'users';

  /// What sshd reports once it is allowed to resolve its configuration.
  const String sshdReports =
      'port 22\n'
      'pubkeyauthentication yes\n'
      'passwordauthentication yes\n'
      'kbdinteractiveauthentication yes\n';

  /// A machine whose sshd, whose home directories and whose account database answer as a real one.
  ///
  /// `sshd -T` and `stat` are root's to have — sshd resolves its configuration out of the host keys
  /// and every file an Include names, and the operator's `.ssh` is `0700`. `getent passwd` and
  /// `mountpoint` are not: both read something every account on the machine may read, which is
  /// what makes them the innocent neighbours here.
  _Session machine() => _Session(
    <String, _RootOnly>{
      askSshd: const _RootOnly(
        answersRoot: sshdReports,
        refusal: 'sshd: no hostkeys available -- exiting.',
        refusedExitCode: 255,
      ),
      'stat -c %a $keyFile': const _RootOnly(
        answersRoot: '600\n',
        refusal: "stat: cannot statx '$keyFile': Permission denied",
        refusedExitCode: 1,
      ),
      // The gate reads the key directory by LISTING it, which needs the same traverse bit any
      // reading under it needs — so this is refused to the operator exactly as the key file's own
      // permissions are.
      'ls -A -- $home/.ssh': const _RootOnly(
        answersRoot: 'authorized_keys\n',
        refusal: "ls: cannot open directory '$home/.ssh': Permission denied",
        refusedExitCode: 2,
      ),
      'stat -c %a $home/.ssh': const _RootOnly(
        answersRoot: '700\n',
        refusal: "stat: cannot statx '$home/.ssh': Permission denied",
        refusedExitCode: 1,
      ),
      'stat -c %a $home': const _RootOnly(
        answersRoot: '750\n',
        refusal: "stat: cannot statx '$home': Permission denied",
        refusedExitCode: 1,
      ),
    },
    answeredToAnybody: <String, String>{readPasswdEntry: '$user:x:1000:1000::$home:/bin/bash\n'},
  );

  /// The step as the registry builds it from a row, so the answer travels the path a row travels.
  ///
  /// Built through [hostRegistry] rather than by calling the constructor: what a row grants reaches
  /// a step through its factory, and a factory that dropped the value would be invisible to a test
  /// that put the field in by hand.
  Step rowFor(String step, Map<String, Object> values) =>
      hostRegistry.step(StepName(step))!.create(Arguments(values));

  StepContext contextFor(String step, _Session session, FakeFiles files) => StepContext(
    shell: session,
    files: files,
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: StepName(step),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{
      'operator_user': user,
      'operator_public_key': key,
      'storage_mount': dataFilesystem,
    }),
    facts: Facts.none,
    measurements: const _DiscardedMeasurements(),
  );

  test('the sshd this step decides from answers it, because the command arrives as root', () async {
    // The most severe of the set. Unelevated, sshd refuses the whole answer, the step reads that as
    // "sshd could not report its configuration", and a machine that still takes a password is
    // reported as one nothing can be said about.
    final _Session session = machine();
    final Step step = rowFor('disable_password_login', <String, Object>{
      'drop_in': dropIn,
      'reload': <String>['systemctl', 'reload', 'ssh'],
      'elevated': true,
    });

    final CheckResult answer = await step.check(
      contextFor('disable_password_login', session, FakeFiles()),
    );

    expect(
      answer,
      isA<Ready>(),
      reason: answer is Blocked ? answer.reason : 'this machine still accepts a password',
    );
    expect(session.refused, isEmpty);
    expect(session.carriedOut, contains(askSshd));
  });

  test('the permissions the key gate decides from are read, not reported as unreadable', () async {
    // `stat` on another account's `.ssh` is refused to the operator, `_mode` answers null, and the
    // gate between installing a key and taking the password away blocks with a sentence about
    // itself — "the permissions of ... could not be read" — rather than about the machine.
    final _Session session = machine();
    final FakeFiles files = FakeFiles(<String, String>{keyFile: '$key\n'});
    final Step step = rowFor('require_key_login_possible', <String, Object>{
      'public_key_answer': 'operator_public_key',
      'elevated': true,
    });

    final CheckResult answer = await step.check(
      contextFor('require_key_login_possible', session, files),
    );

    // The refusal itself is what a reader has to see when this goes red — a sentence about the
    // permissions not being readable is the whole defect, and "Instance of Blocked" hides it.
    expect(answer, isA<Satisfied>(), reason: answer is Blocked ? answer.reason : '$answer');
    expect(session.refused, isEmpty);
    expect(
      session.carriedOut,
      containsAll(<String>['stat -c %a $keyFile', 'stat -c %a $home/.ssh', 'stat -c %a $home']),
    );
  });

  test('THE INNOCENT NEIGHBOUR: what any account may read is read under either answer', () async {
    // The sites answered `elevated: false`. `mountpoint` asks the machine's own mount table,
    // which every account may read, so the session hands the command over whichever account
    // asks, and neither row's answer changes what comes back. A red result above therefore
    // means an elevation was dropped, not that this session refuses everything.
    for (final bool granted in <bool>[false, true]) {
      final _Session session = machine();
      final Step step = rowFor('require_storage_mount', <String, Object>{'elevated': granted});

      final CheckResult answer = await step.check(
        contextFor('require_storage_mount', session, FakeFiles()..directories.add(dataFilesystem)),
      );

      expect(answer, isA<Satisfied>(), reason: 'under elevated: $granted, $answer');
      expect(session.refused, isEmpty);
      expect(session.carriedOut, contains(askMountpoint));
    }
  });

  test(
    'THE SESSION AND NOT THE FLAG: a session in the granting group needs no elevation',
    () async {
      // What makes this machine a session rather than a reading of `Command.elevated`. The account
      // database is answered to the operator here because the session began in the group that may
      // read it, and it would be answered on a real machine for the same reason. A shell that only
      // read the flag could not tell an unelevated command that is allowed from one that is not.
      final _Session session = machine();

      await rowFor('require_key_login_possible', <String, Object>{
        'public_key_answer': 'operator_public_key',
        'elevated': true,
      }).check(
        contextFor(
          'require_key_login_possible',
          session,
          // The machine's listing names this file, so the file system it is read out of holds it.
          // A fixture where the two disagree measures a machine nobody has.
          FakeFiles(<String, String>{keyFile: '$key\n'}),
        ),
      );

      expect(session.groupsAtLogin, contains(everybody));
      expect(session.carriedOut, contains(readPasswdEntry));
    },
  );
}

/// One command whose answer only root may have, and how the tool itself refuses everybody else.
final class _RootOnly {
  /// Records what root is answered and what anybody else is told.
  const _RootOnly({
    required this.answersRoot,
    required this.refusal,
    required this.refusedExitCode,
  });

  /// What the command writes on its output when it is allowed to run.
  final String answersRoot;

  /// What the tool writes on its error output when it is not, in the tool's own words.
  final String refusal;

  /// What the tool returns when it refuses, which differs per tool and is what a step reads.
  final int refusedExitCode;
}

/// A session on a machine, answering as the account the run was started as.
///
/// **The supplementary groups are fixed at construction, and nothing here can widen them.** A
/// process reads its groups when its session begins, so a step that adds the account to a group
/// grants the NEXT session and not this one. That is what makes the elevation of the command itself
/// the only thing that decides for a command in [_onlyRootMay], and it is why a step is measured
/// here rather than by reading back the field it composed.
final class _Session implements Shell {
  /// Opens a session on a machine where [_onlyRootMay] names what the operator may not have and
  /// [_answeredToAnybody] what any account may.
  _Session(this._onlyRootMay, {required Map<String, String> answeredToAnybody})
    : _answeredToAnybody = <String, String>{...answeredToAnybody};

  final Map<String, _RootOnly> _onlyRootMay;
  final Map<String, String> _answeredToAnybody;

  /// The groups this account stood in when the session began.
  ///
  /// Every account on a machine is in the group that may read the account database, which is what
  /// makes `getent passwd` answer without root — a fact about the session and not about the flag on
  /// the command.
  final Set<String> groupsAtLogin = <String>{'users'};

  /// Every command this session was asked to run, in order.
  final List<String> ran = <String>[];

  /// The commands it actually carried out.
  final Set<String> carriedOut = <String>{};

  /// The commands it refused, which are the ones that arrived as the operator.
  final List<String> refused = <String>[];

  @override
  Future<CommandResult> run(Command command) async {
    final String argv = command.argv.join(' ');
    ran.add(argv);
    if (_onlyRootMay[argv] case final _RootOnly guarded) {
      if (!command.elevated) {
        refused.add(argv);
        return CommandResult(
          exitCode: guarded.refusedExitCode,
          stdout: '',
          stderr: '${guarded.refusal}\n',
          elapsed: Duration.zero,
        );
      }
      carriedOut.add(argv);
      return CommandResult(
        exitCode: 0,
        stdout: guarded.answersRoot,
        stderr: '',
        elapsed: Duration.zero,
      );
    }
    carriedOut.add(argv);
    return CommandResult(
      exitCode: 0,
      stdout: _answeredToAnybody[argv] ?? '',
      stderr: '',
      elapsed: Duration.zero,
    );
  }
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
