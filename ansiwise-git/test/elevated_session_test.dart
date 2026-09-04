import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// What a row grants has to reach the SESSION the command runs in, and this measures that.
///
/// **Why the session and not the field.** A test that reads `Command.elevated` back off the command
/// a step composed proves the step wrote a value down; it says nothing about the account the command
/// then runs as. The failure this whole audit exists for is exactly that gap: the value was written
/// in one place, dropped one call later, and the run went out as the operator with the record saying
/// the row had granted root.
///
/// So the machine here is a SESSION. [_Session] answers as the account a run was started as, its
/// supplementary groups fixed when it was constructed — a process reads its groups once, when the
/// session begins, so a row that puts the account into a group grants the next session and never
/// this one. Nothing but a command arriving elevated widens what this session may reach, and what it
/// refuses it refuses in the tool's own words.
void main() {
  const String sourcePath = 'rendered/values.yaml';
  const String destination = '/srv/records/values.yaml';
  const String committed = 'name: one';
  const String readBranch = 'git -C $repository rev-parse --abbrev-ref HEAD';
  const String readCommitted = 'git -C $repository show HEAD:$sourcePath';

  /// The account this run was started as, and the group the checkout belongs to.
  const String recordsGroup = 'records';

  /// The step as the registry builds it from a row, so the answer travels the path a row travels.
  ///
  /// Built through [gitRegistry] rather than by calling the constructor: what a row grants reaches a
  /// step through its factory, and a factory that dropped the value would be invisible to a test
  /// that put the field in by hand.
  Step rowSaying({required bool elevated}) => gitRegistry
      .step(const StepName('copy_branch_file'))!
      .create(
        Arguments(<String, Object>{
          'repository': repository,
          'path': sourcePath,
          'destination': destination,
          'file_mode': 420,
          'elevated': elevated,
        }),
      );

  /// A machine where the checkout belongs to root, so git refuses anybody else both questions.
  _Session machine({Set<String> groupsAtLogin = const <String>{}}) =>
      _Session(const <String, _RootOnly>{
        readBranch: _RootOnly(
          answersRoot: '$base\n',
          refusal: "fatal: detected dubious ownership in repository at '$repository'",
          refusedExitCode: 128,
          orTheGroup: recordsGroup,
        ),
        readCommitted: _RootOnly(
          answersRoot: committed,
          refusal: "fatal: cannot change to '$repository': Permission denied",
          refusedExitCode: 128,
          orTheGroup: recordsGroup,
        ),
      }, groupsAtLogin: groupsAtLogin);

  StepContext contextFor(_Session session, FakeFiles files) => StepContext(
    shell: session,
    files: files,
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const SilentLog(),
    step: const StepName('copy_branch_file'),
    arguments: Arguments.none,
    answers: Arguments.none,
    facts: Facts.none,
  );

  test('the reading a row granted root reaches the machine as root', () async {
    final _Session session = machine();
    final FakeFiles files = FakeFiles();
    final Step step = rowSaying(elevated: true);

    expect(await step.check(contextFor(session, files)), isA<Ready>());
    await step.apply(contextFor(session, files));

    expect(
      session.refused,
      isEmpty,
      reason: 'a command this session refused is one that ran as the operator',
    );
    expect(session.carriedOut, contains(readCommitted));
    expect(files.contents[destination], committed);
  });

  test('and the branch the check reads first reaches it the same way', () async {
    // The innocent neighbour INSIDE the defect's own file: this call carries the row's answer
    // independently of the one beside it, so a red result here would mean the session refuses
    // everything.
    final _Session session = machine();

    expect(await rowSaying(elevated: true).check(contextFor(session, FakeFiles())), isA<Ready>());
    expect(session.carriedOut, contains(readBranch));
  });

  test('the same copy under a row that grants nothing is refused by the machine', () async {
    // What a dropped answer looks like from the machine's side, and the reason the assertions above
    // are worth anything: the step is correct, the row simply granted no root, and git refuses the
    // reading the whole copy rests on.
    final _Session session = machine();

    final CheckResult answer = await rowSaying(
      elevated: false,
    ).check(contextFor(session, FakeFiles()));

    expect(session.refused, contains(readBranch));
    expect(answer, isA<Blocked>(), reason: '$answer');
    expect((answer as Blocked).reason, contains(repository));
  });

  group('the reading a row cannot grant, because the row is about something else', () {
    /// Where the first checkout of an installation stands, under a directory only root may enter.
    const String checkout = '/srv/programs-checkout';

    /// The account that checkout is handed to, which is not the account this run is.
    const String account = 'operator';

    const String readOwner = 'stat -c %U $checkout';

    /// The cloning row as a program writes it, which says nothing about elevation.
    ///
    /// It cannot: the flag says whether the checkout and the settings files are root's to read, and
    /// every git command of this row runs at it — a checkout just handed to another account is one
    /// git refuses to root. So the ownership reading is the one command of this row that is asked as
    /// root on its own, like the two that perform the hand-over.
    Step cloningRow() => gitRegistry
        .step(const StepName('git_clone'))!
        .create(
          const Arguments(<String, Object>{
            'repository': checkout,
            'host': 'code.example.com',
            'branch': base,
            'origin_answer': 'platform_repo',
            'owner_answer': 'operator_user',
          }),
        );

    /// A machine where the directory the checkout stands in may only be entered by root.
    _Session machineHiding() => _Session(const <String, _RootOnly>{
      readOwner: _RootOnly(
        answersRoot: 'root\n',
        refusal: "stat: cannot statx '$checkout': Permission denied",
        refusedExitCode: 1,
        orTheGroup: 'root',
      ),
    });

    StepContext cloning(_Session session, FakeFiles files) => StepContext(
      shell: session,
      files: files,
      http: FakeHttp(),
      clock: FakeClock(),
      entropy: FakeEntropy(),
      log: const SilentLog(),
      step: const StepName('git_clone'),
      arguments: Arguments.none,
      answers: const Arguments(<String, Object>{
        'platform_repo': 'acme/acme-platform',
        'operator_user': account,
      }),
      facts: Facts.none,
    );

    test('the ownership reading arrives as root, whatever the row said about the files', () async {
      // Asked as the account the run started as, this is the reading that comes back empty and is
      // then read as "belongs to nobody else" — so the hand-over is skipped and every git command
      // after it meets a repository git refuses outright. No row can fix that by granting more,
      // which is why the elevation of this one command is not the row's to state.
      final _Session session = machineHiding();

      final CheckResult answer = await cloningRow().check(
        cloning(session, FakeFiles()..directories.add(checkout)),
      );

      expect(session.refused, isEmpty, reason: 'a refused command is one that ran as the operator');
      expect(session.carriedOut, contains(readOwner));
      expect(answer, isA<Ready>(), reason: '$answer');
    });
  });

  test('THE SESSION AND NOT THE FLAG: a session already in the group needs no elevation', () async {
    // What makes this machine a session rather than a reading of `Command.elevated`. The same
    // unelevated copy goes through here, because the account this session began as was already in
    // the group that owns the checkout, and it would go through on a real machine for the same
    // reason. A shell that only read the flag could not tell these two runs apart.
    final _Session session = machine(groupsAtLogin: <String>{recordsGroup});

    await rowSaying(elevated: false).apply(contextFor(session, FakeFiles()));

    expect(session.refused, isEmpty);
    expect(session.carriedOut, contains(readCommitted));
  });
}

/// One command whose answer only root may have, and how the tool itself refuses everybody else.
final class _RootOnly {
  /// Records what root is answered and what anybody else is told.
  const _RootOnly({
    required this.answersRoot,
    required this.refusal,
    required this.refusedExitCode,
    required this.orTheGroup,
  });

  /// What the command writes on its output when it is allowed to run.
  final String answersRoot;

  /// What the tool writes on its error output when it is not, in the tool's own words.
  final String refusal;

  /// What the tool returns when it refuses, which differs per tool and is what a step reads.
  final int refusedExitCode;

  /// The group whose members may run it without being root.
  final String orTheGroup;
}

/// A session on a machine, answering as the account the run was started as.
///
/// **The supplementary groups are fixed at construction, and nothing here can widen them.** A
/// process reads its groups when its session begins, so a step that adds the account to a group
/// grants the NEXT session and not this one. That is what makes the elevation of the command itself
/// the only thing that decides, and it is why a step is measured here rather than by reading back
/// the field it composed.
final class _Session implements Shell {
  /// Opens a session whose account stands in [groupsAtLogin], on a machine where [_onlyRootMay]
  /// names the commands whose answer is not the operator's to have.
  _Session(this._onlyRootMay, {Set<String> groupsAtLogin = const <String>{}})
    : _groupsAtLogin = <String>{...groupsAtLogin};

  final Map<String, _RootOnly> _onlyRootMay;
  final Set<String> _groupsAtLogin;

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
    final _RootOnly? guarded = _onlyRootMay[argv];
    if (guarded == null || command.elevated || _groupsAtLogin.contains(guarded.orTheGroup)) {
      carriedOut.add(argv);
      return CommandResult(
        exitCode: 0,
        stdout: guarded?.answersRoot ?? '',
        stderr: '',
        elapsed: Duration.zero,
      );
    }
    refused.add(argv);
    return CommandResult(
      exitCode: guarded.refusedExitCode,
      stdout: '',
      stderr: '${guarded.refusal}\n',
      elapsed: Duration.zero,
    );
  }
}
