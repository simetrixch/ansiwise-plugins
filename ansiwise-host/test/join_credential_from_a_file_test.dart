import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

/// The join spending a credential that is already on this machine, through the program file alone.
///
/// **What this is about.** `tailnet_join` reads its credential from one place: the answer
/// `auth_key`. A machine whose credential was minted onto its own disk has no caller to carry that
/// value back in as an answer, so until the framework could work an answer out of a FILE there was
/// no way to write the row at all.
///
/// **The step is unchanged, and that is the thing being measured.** Everything here is
/// configuration: the program file declares `auth_key` as the secret in the file another answer
/// names, the run fills it before the first row, and the step reads the answer by name exactly as it
/// does when a caller sent one. A test that drove the step directly would prove nothing about that,
/// so this one goes through the loader, the resolver and the runner.
void main() {
  const String keyFile = '/tmp/a-minted-join-key';
  const String credential = 'a-credential-this-machine-minted-for-itself';
  const String stagedKeyPath = '/tmp/staged-key';
  const String up =
      'tailscale up --login-server https://net.example '
      '--auth-key file:$stagedKeyPath --accept-dns=false';

  /// A program whose only row joins, taking its credential out of the file `key_file` names.
  const String yaml =
      'name: join-with-what-is-on-this-machine\n'
      'roles: [master]\n'
      'steps:\n'
      '  - step: tailnet_join\n'
      '    staged_key_path: $stagedKeyPath\n'
      '    on_failure: exit\n'
      'answers:\n'
      '  - name: login_server\n'
      '    kind: text\n'
      '    describes: where the private network coordinator answers\n'
      '  - name: key_file\n'
      '    kind: text\n'
      '    describes: the file an earlier run left the credential in\n'
      '  - name: auth_key\n'
      '    kind: text\n'
      '    required: false\n'
      '    derived: secret_in_file_at\n'
      '    from: key_file\n'
      '    describes: the credential standing in that file\n';

  RunRecord headerOn(FakeClock clock) => RunRecord(
    id: const RunId('20260831T120000Z-1'),
    program: const ProgramName('join-with-what-is-on-this-machine'),
    mode: Mode.run,
    argv: const <String>['ansiwise', 'join-with-what-is-on-this-machine'],
    start: clock.now(),
    stage: const Stage('dev'),
    role: const Role('master'),
    fqdn: const Fqdn('m1.example.com'),
    commit: '0000000',
    fingerprint: 'test-fingerprint',
  );

  /// Runs the program above against a machine whose client needs to log in, and whose file system
  /// holds [holds].
  Future<({RunRecord closed, FakeShell shell, List<String> staged})> joinOn(
    Map<String, String> holds,
  ) async {
    final FakeClock clock = FakeClock();
    final FakeFiles files = FakeFiles(<String, String>{...holds});
    final FakeShell shell = FakeShell()
      ..answers('tailscale status --json', '{"BackendState":"NeedsLogin"}');
    // WHAT THE STAGED FILE HELD WHILE THE CLIENT RAN. The step removes it whatever the join
    // answers, so the only moment its content can be read is the command itself — and its content
    // is the whole question: it is the credential the answer was worked out to.
    final List<String> staged = <String>[];
    shell.changes(up, () {
      final String? held = files.contents[stagedKeyPath];
      if (held != null) {
        staged.add(held);
      }
      shell.answers('tailscale status --json', '{"BackendState":"Running"}');
      shell.answers('tailscale debug prefs', '{"ControlURL":"https://net.example"}');
    });

    final Program program = loadProgram(yaml, where: 'test.yaml');
    final RunRecord closed =
        await Runner(
          machine: fakeMachine(shell: shell, files: files, clock: clock),
          recorder: MemoryRecorder(clock),
          redactor: Redactor(const <String>[]),
        ).run(
          program: const ProgramResolver(hostRegistry).resolve(program),
          mode: Mode.run,
          header: headerOn(clock),
          answers: program.answers.validate(<String, Object?>{
            'login_server': 'https://net.example/',
            'key_file': keyFile,
          }, program: program.name.value),
        );

    return (closed: closed, shell: shell, staged: staged);
  }

  test('the program file alone is enough: no step of this plugin changed', () {
    // The resolver is where a row naming an answer the program does not declare is refused, and
    // where the step's own declared answers are held against it. A green resolve is what says the
    // row is writable as configuration.
    final Program program = loadProgram(yaml, where: 'test.yaml');
    final ResolvedProgram resolved = const ProgramResolver(hostRegistry).resolve(program);

    expect(resolved.steps.single.entry.step, const StepName('tailnet_join'));
    expect(
      program.answers.named(TailnetJoin.authKeyAnswer)?.derivation?.rule,
      DerivationRule.secretInFileAt,
    );
    expect(program.answers.secretNames, contains(TailnetJoin.authKeyAnswer));
  });

  test('the join stages the credential the file held, and the run closes green', () async {
    final ({RunRecord closed, FakeShell shell, List<String> staged}) ran = await joinOn(
      // With the newline the mint leaves behind, because that is what a file holding a credential
      // actually contains — and it is what the step used to have to strip for itself.
      <String, String>{keyFile: '$credential\n'},
    );

    expect(ran.closed.exitCode, 0);
    expect(ran.staged.single, '$credential\n', reason: 'the client read exactly the minted value');
    expect(ran.shell.ran, contains(up));
  });

  test('the credential still never rides the command line', () async {
    // The step's own promise, asked again from the far end of the new route: a value that arrived
    // as a worked-out answer must reach the client the same way one typed by a caller does.
    final ({RunRecord closed, FakeShell shell, List<String> staged}) ran = await joinOn(
      <String, String>{keyFile: '$credential\n'},
    );

    expect(ran.shell.ran.where((String each) => each.contains(credential)), isEmpty);
  });

  test('THE PLANTED DEFECT: no file means no run, and the refusal names the path', () async {
    // Not an empty credential and not a default. Joined with nothing, the client waits for a person
    // this run does not have — so the run stops before its first row, where the reason still points
    // at the file somebody has to go and look at.
    final ({RunRecord closed, FakeShell shell, List<String> staged}) ran = await joinOn(
      const <String, String>{},
    );

    expect(ran.closed.exitCode, 1);
    expect(ran.closed.steps, isEmpty);
    expect(ran.closed.issues.single, allOf(contains(TailnetJoin.authKeyAnswer), contains(keyFile)));
    expect(ran.shell.ran, isEmpty, reason: 'nothing reached the client');
  });
}
