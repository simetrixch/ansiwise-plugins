import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_helm/ansiwise_helm.dart';
import 'package:test/test.dart';

/// Whether a row that says helm needs root reaches helm on the ONE machine state where it matters.
///
/// **The state is a machine whose account is already in the group and whose session is not.** A
/// cluster distribution that ships helm inside its own command admits one group and refuses every
/// account outside it. A first installation puts the operating account into that group — and a
/// supplementary group is read once, when a session starts, so the run doing the granting carries
/// the group list it authenticated with and nothing it does afterwards adds to it. The machine is
/// configured correctly, every later run succeeds, and every helm invocation of THAT run is refused.
///
/// So the fake below fixes the session's groups at construction and refuses whatever did not come
/// elevated, while the account it names IS in the group. A test that asserted the flag reached a
/// field would pass on a machine nobody could install on; this one fails there.
///
/// Each row is built through the registry, out of the values a program row writes, so the answer
/// travels the whole path it travels on a machine: the row, the argument declaration, the step's own
/// factory, the composer, and the command that leaves for the machine.
void main() {
  /// The group the wrapping command admits. Invented, because which group a distribution keeps is a
  /// fact of that distribution and this package must not know one.
  const String admits = 'cluster-operators';

  /// How helm is reached where it ships inside another command.
  const List<String> wrapped = <String>['wrapper', 'helm'];

  const String list = 'wrapper helm list --namespace ledger -o json';
  const String heldValues = 'wrapper helm get values ledger --namespace ledger -o json';
  const String upgrade =
      'wrapper helm upgrade --install ledger example-charts/ledger --namespace ledger '
      '--version 0.34.0';
  const String repositories = 'wrapper helm repo list -o json';

  /// What the row writes for a release, without the answer that decides how helm is reached.
  const Map<String, Object> releaseRow = <String, Object>{
    'helm_command': wrapped,
    'release': 'ledger',
    'chart': 'example-charts/ledger',
    'chart_version': '0.34.0',
    'namespace': 'ledger',
  };

  /// What the row writes for a chart repository, the same way.
  const Map<String, Object> repositoryRow = <String, Object>{
    'helm_command': wrapped,
    'name': 'example-charts',
    'url': 'https://charts.example.test',
  };

  test('a row that says helm needs root installs on a session that predates the grant', () async {
    // THE BARE-MACHINE STATE, planted whole: the account is in the group, this session started
    // before it was, and the row answers that the distribution admits root.
    final _WrappedHelm machine = _WrappedHelm(admits: admits, sessionCarries: const <String>{})
      ..putTheAccountIn(admits)
      ..answers(upgrade, 'NAME: ledger\nSTATUS: deployed\nREVISION: 1\n');
    final _CapturedLog log = _CapturedLog();

    await _fromRow('helm_release', <String, Object>{
      ...releaseRow,
      'helm_needs_root': true,
    }).apply(_contextOn(machine, log: log));

    expect(
      log.informed.join('\n'),
      contains('deployed'),
      reason: 'the upgrade reached helm, which is what the answer on the row is for',
    );
  });

  test('the same row without that answer meets the refusal the machine is in', () async {
    // THE DEFECT ITSELF, and what makes the test above a measurement rather than a fake that admits
    // everything: the row is identical bar the one answer, and the machine refuses it.
    final _WrappedHelm machine = _WrappedHelm(admits: admits, sessionCarries: const <String>{})
      ..putTheAccountIn(admits)
      ..answers(upgrade, 'NAME: ledger\nSTATUS: deployed\nREVISION: 1\n');

    await expectLater(
      _fromRow('helm_release', releaseRow).apply(_contextOn(machine)),
      throwsA(
        isA<CommandFailed>().having(
          (CommandFailed failure) => failure.message,
          'message',
          contains('started before'),
        ),
      ),
    );
  });

  test('what a release READS is reached the same way', () async {
    // The reads decide whether the upgrade runs at all, and a refused read is not an empty answer:
    // it would report a release that is installed as absent, and one that is absent as unlistable.
    final _WrappedHelm machine = _WrappedHelm(admits: admits, sessionCarries: const <String>{})
      ..putTheAccountIn(admits)
      ..answers(list, '[{"name":"ledger","status":"deployed","chart":"ledger-0.34.0"}]')
      ..answers(heldValues, '{}');

    final CheckResult answer = await _fromRow('helm_release', <String, Object>{
      ...releaseRow,
      'helm_needs_root': true,
    }).check(_contextOn(machine));

    expect(answer, isA<Satisfied>());
  });

  test('a chart repository is registered the same way', () async {
    // The row above the release, which has no elevation of any kind before this change: its add and
    // its listing reach the same command and are refused by the same group.
    final _WrappedHelm machine = _WrappedHelm(admits: admits, sessionCarries: const <String>{})
      ..putTheAccountIn(admits)
      ..answers(repositories, '[{"name":"example-charts","url":"https://charts.example.test"}]');

    final CheckResult answer = await _fromRow('helm_repository', <String, Object>{
      ...repositoryRow,
      'helm_needs_root': true,
    }).check(_contextOn(machine));

    expect(answer, isA<Satisfied>());
  });

  test('a session opened after the grant carries the group and asks for no root', () async {
    // THE INNOCENT CASE. The account was put in the group before this session started, so the
    // session carries it, and the row leaves the answer off — helm is reached as the account that
    // owns what it writes, and nothing is raised to root that does not need to be.
    final _WrappedHelm machine = _WrappedHelm(
      admits: admits,
      sessionCarries: const <String>{admits},
    )..answers(upgrade, 'NAME: ledger\nSTATUS: deployed\nREVISION: 1\n');
    final _CapturedLog log = _CapturedLog();

    await _fromRow('helm_release', releaseRow).apply(_contextOn(machine, log: log));

    expect(log.informed.join('\n'), contains('deployed'));
    expect(
      machine.reached.every((Command each) => !each.elevated),
      isTrue,
      reason: 'a row that did not ask for root does not get it',
    );
  });
}

/// The step a program row of these values builds, through the registry the binary carries.
///
/// The declared defaults are filled in first, the way the resolver fills them, so a row that leaves
/// an optional argument out reaches the step exactly as it does on a machine.
Step _fromRow(String step, Map<String, Object> row) {
  final RegisteredStep registered = helmSteps[StepName(step)]!;
  final Map<String, Object> defaults = <String, Object>{
    for (final ArgumentSpec spec in registered.arguments)
      if (spec.defaultValue case final Object value) spec.name: value,
  };
  return registered.create(Arguments(row).withDefaults(defaults));
}

/// A machine where helm ships inside a cluster distribution's own command.
///
/// **The command admits ONE group, and the session's groups are fixed when it starts.** That is the
/// whole of what this fake models, and it is the difference between proving that a flag reached a
/// field and proving that a row reaches helm: an account can be in the group while the session it is
/// working in is not, and no command run in that session can change it. Root is admitted without any
/// group at all.
final class _WrappedHelm implements Shell {
  /// A machine whose wrapping command admits [admits], in a session carrying [sessionCarries].
  _WrappedHelm({required this.admits, required Set<String> sessionCarries})
    : _sessionCarries = Set<String>.unmodifiable(sessionCarries);

  /// The group the wrapping command admits.
  final String admits;

  /// The groups THIS session carries, read once when it started and never added to afterwards.
  final Set<String> _sessionCarries;

  /// Every group the account is in ON the machine, which a membership row adds to at any time.
  final Set<String> _onTheMachine = <String>{};

  /// What each admitted command line answers.
  final Map<String, String> _answers = <String, String>{};

  /// Every command that reached the machine, admitted or refused.
  final List<Command> reached = <Command>[];

  /// Puts the account in [group] on the machine, the way a membership row does — after this session
  /// started, which is what a first installation does and why its own helm rows are refused.
  void putTheAccountIn(String group) => _onTheMachine.add(group);

  /// Makes [argv] answer [output] to whoever the command admits.
  void answers(String argv, String output) => _answers[argv] = output;

  @override
  Future<CommandResult> run(Command command) async {
    reached.add(command);
    if (!command.elevated && !_sessionCarries.contains(admits)) {
      return CommandResult(
        exitCode: 1,
        stdout: '',
        stderr: _onTheMachine.contains(admits)
            ? 'Insufficient permissions to access this command. The account is in "$admits" and '
                  'this session was started before it was put there'
            : 'Insufficient permissions to access this command. The account is not in "$admits"',
        elapsed: Duration.zero,
      );
    }
    return CommandResult(
      exitCode: 0,
      stdout: _answers[command.argv.join(' ')] ?? '',
      stderr: '',
      elapsed: Duration.zero,
    );
  }
}

StepContext _contextOn(Shell shell, {Logger? log}) => StepContext(
  shell: shell,
  files: FakeFiles(),
  http: FakeHttp(),
  clock: FakeClock(),
  entropy: FakeEntropy(),
  log: log ?? const _SilentLog(),
  step: const StepName('under_test'),
  arguments: Arguments.none,
  answers: Arguments.none,
  facts: Facts.none,
);

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

/// A logger the test can read back, kept by level because the level is part of what is asserted.
final class _CapturedLog implements Logger {
  final List<String> debugged = <String>[];
  final List<String> informed = <String>[];
  final List<String> warned = <String>[];
  final List<String> errored = <String>[];

  @override
  void debug(String message) => debugged.add(message);

  @override
  void info(String message) => informed.add(message);

  @override
  void warn(String message) => warned.add(message);

  @override
  void error(String message) => errored.add(message);
}
