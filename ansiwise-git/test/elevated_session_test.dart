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
  const String path = '/srv/records/state.conf';
  const String pattern = 'before';
  const String replacement = 'after';
  const String grep = 'grep -q -E $pattern $path';
  const String sed = 'sed -i -E s/$pattern/$replacement/g $path';

  /// The account this run was started as, and the group the file at [path] belongs to.
  const String recordsGroup = 'records';

  /// The step as the registry builds it from a row, so the answer travels the path a row travels.
  ///
  /// Built through [gitRegistry] rather than by calling the constructor: what a row grants reaches a
  /// step through its factory, and a factory that dropped the value would be invisible to a test
  /// that put the field in by hand.
  Step rowSaying({required bool elevated}) => gitRegistry
      .step(const StepName('replace_regex_in_tracked_file'))!
      .create(
        Arguments(<String, Object>{
          'path': path,
          'pattern': pattern,
          'replacement': replacement,
          'elevated': elevated,
        }),
      );

  /// A machine where [path] belongs to root, so both tools that touch it refuse anybody else.
  _Session machine({Set<String> groupsAtLogin = const <String>{}}) =>
      _Session(const <String, _RootOnly>{
        grep: _RootOnly(
          answersRoot: '',
          refusal: 'grep: $path: Permission denied',
          refusedExitCode: 2,
          orTheGroup: recordsGroup,
        ),
        sed: _RootOnly(
          answersRoot: '',
          refusal: "sed: couldn't open temporary file /srv/records/sedXXXX: Permission denied",
          refusedExitCode: 4,
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
    step: const StepName('replace_regex_in_tracked_file'),
    arguments: Arguments.none,
    answers: Arguments.none,
    facts: Facts.none,
  );

  FakeFiles fileHolding(String text) => FakeFiles(<String, String>{path: text});

  test('the rewrite a row granted root reaches the machine as root', () async {
    final _Session session = machine();
    final FakeFiles files = fileHolding('$pattern\n');
    final Step step = rowSaying(elevated: true);

    expect(await step.check(contextFor(session, files)), isA<Ready>());
    await step.apply(contextFor(session, files));

    expect(
      session.refused,
      isEmpty,
      reason: 'a command this session refused is one that ran as the operator',
    );
    expect(session.carriedOut, contains(sed));
  });

  test('and the search the check makes reaches it the same way', () async {
    // The innocent neighbour INSIDE the defect's own file: this call already carried the row's
    // answer before the rewrite did, and it is unaffected either way. Without it a red result here
    // could mean the session refuses everything.
    final _Session session = machine();

    expect(
      await rowSaying(elevated: true).check(contextFor(session, fileHolding('$pattern\n'))),
      isA<Ready>(),
    );
    expect(session.carriedOut, contains(grep));
  });

  test(
    'the same rewrite under a row that grants nothing is refused in the tool\'s own words',
    () async {
      // What a dropped answer looks like from the machine's side, and the reason the assertions above
      // are worth anything: the step is correct, the row simply granted no root, and the session says
      // so as sed says it.
      final _Session session = machine();
      final FakeFiles files = fileHolding('$pattern\n');
      final Step step = rowSaying(elevated: false);

      await expectLater(
        () async => step.apply(contextFor(session, files)),
        throwsA(
          isA<CommandFailed>().having(
            (CommandFailed failure) => failure.toString(),
            'what the tool said',
            contains('Permission denied'),
          ),
        ),
      );
    },
  );

  test('THE SESSION AND NOT THE FLAG: a session already in the group needs no elevation', () async {
    // What makes this machine a session rather than a reading of `Command.elevated`. The same
    // unelevated rewrite goes through here, because the account this session began as was already
    // in the group that owns the file — and it would go through on a real machine for the same
    // reason. A shell that only read the flag could not tell these two runs apart.
    final _Session session = machine(groupsAtLogin: <String>{recordsGroup});

    await rowSaying(elevated: false).apply(contextFor(session, fileHolding('$pattern\n')));

    expect(session.refused, isEmpty);
    expect(session.carriedOut, contains(sed));
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
