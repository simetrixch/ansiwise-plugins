import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_helm/ansiwise_helm.dart';
import 'package:test/test.dart';

/// Whether a release already holds what the file says, which decides whether an upgrade runs.
///
/// **This package had no test of its own steps at all** — only the audits every package carries — so
/// a hundred and fifty of them were green over a comparison that could never say yes.
///
/// The comparison encoded both sides and compared the strings. A map has no order and encoding gives
/// it one, so the file's order and helm's order produced different text for the same values: the
/// release was never "already so", the step's own post-check never held, the run unwound, and the
/// unwind removed the chart repository the row above had registered. The next attempt then failed at
/// the release with "repo not found" and sent whoever read it to the repository row, where nothing
/// was wrong.
void main() {
  const String path = '/srv/values.yaml';

  /// The release under test, INVENTED rather than borrowed.
  ///
  /// A fixture naming a real vendor's chart is a specification of one product's dependency living in
  /// a package that must serve any product, and it goes stale the day that vendor renames a chart.
  /// What these tests are about is the comparison, and the comparison does not care what is
  /// installed.
  const HelmRelease release = HelmRelease(
    release: 'ledger',
    chart: 'example-charts/ledger',
    chartVersion: '0.34.0',
    namespace: 'ledger',
    values: path,
    helm: Helm(),
  );

  /// A machine where helm holds the release, answering [held] for its values.
  StepContext machine({required String file, required String held, Logger? log}) => _contextOn(
    FakeShell()
      ..answers(
        'helm list --namespace ledger -o json',
        '[{"name":"ledger","status":"deployed","chart":"ledger-0.34.0"}]',
      )
      ..answers('helm get values ledger --namespace ledger -o json', held),
    FakeFiles(<String, String>{path: file}),
    log: log,
  );

  test('the same values in a different order are the same values', () async {
    // THE DEFECT. helm gives its own ordering back and the file has the operator's, and neither is
    // wrong. A step that read that as a difference would upgrade on every run for ever.
    final CheckResult answer = await release.check(
      machine(
        file: 'server:\n  enabled: true\nui:\n  enabled: false\n',
        held: '{"ui":{"enabled":false},"server":{"enabled":true}}',
      ),
    );

    expect(
      answer,
      isA<Satisfied>(),
      reason: 'the release holds exactly what the file says, written in another order',
    );
  });

  test('the same keys nested deeper are still compared by shape, not by text', () async {
    final CheckResult answer = await release.check(
      machine(file: 'a:\n  b:\n    c: 1\n    d: 2\n', held: '{"a":{"b":{"d":2,"c":1}}}'),
    );

    expect(answer, isA<Satisfied>());
  });

  test('a list keeps its order, because a list has one', () async {
    // The innocent neighbour of the rule above: sorting a map is right and sorting a list is a lie.
    // Two lists with the same entries in another order are two different values to whatever reads
    // them.
    final CheckResult answer = await release.check(
      machine(file: 'hosts:\n  - a\n  - b\n', held: '{"hosts":["b","a"]}'),
    );

    expect(
      answer,
      isA<Ready>(),
      reason: 'the release holds a different list, and an upgrade is what puts the file\'s there',
    );
  });

  test('a values file the two readers disagree about stops the row', () async {
    // THE DEFECT THIS BLOCKS, planted whole: the file writes 0400, helm stored 256, and the
    // comparison below would find 400 against 256 for ever. Blocked rather than reported, because
    // only whoever wrote the file can say which of the two was meant.
    final CheckResult answer = await release.check(
      machine(file: 'secret:\n  defaultMode: 0400\n', held: '{"secret":{"defaultMode":256}}'),
    );

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('0400'));
  });

  test('a file that quotes what it means is not stopped', () async {
    // The innocent neighbour: the same value, written the way both readers agree on.
    final CheckResult answer = await release.check(
      machine(file: 'secret:\n  defaultMode: 256\n', held: '{"secret":{"defaultMode":256}}'),
    );

    expect(answer, isA<Satisfied>());
  });

  test('a real difference is still a difference', () async {
    final CheckResult answer = await release.check(
      machine(file: 'ui:\n  enabled: true\n', held: '{"ui":{"enabled":false}}'),
    );

    expect(answer, isA<Ready>());
  });

  test('a release at another chart version is not already so', () async {
    final CheckResult answer = await release.check(
      _contextOn(
        FakeShell()..answers(
          'helm list --namespace ledger -o json',
          '[{"name":"ledger","status":"deployed","chart":"ledger-0.33.0"}]',
        ),
        FakeFiles(<String, String>{path: 'ui:\n  enabled: true\n'}),
      ),
    );

    expect(answer, isA<Ready>());
  });

  // WHAT THE RECORD HOLDS when the step decides to act. An upgrade that exits 0 and installs
  // nothing brings the second check here with a record of nothing but exit codes: output is kept
  // only for a failed command or a `keep_output` row, and every command answered 0. So a decision
  // to act carries its measurement itself, at info — the default record keeps nothing quieter —
  // and these tests hold that the lines name what was read rather than only that something was.

  test('a listing that does not hold the release says which releases it read', () async {
    final _CapturedLog log = _CapturedLog();
    final CheckResult answer = await release.check(
      _contextOn(
        FakeShell()..answers(
          'helm list --namespace ledger -o json',
          '[{"name":"registry","status":"deployed","chart":"registry-1.2.0"}]',
        ),
        FakeFiles(<String, String>{path: 'ui:\n  enabled: true\n'}),
        log: log,
      ),
    );

    expect(answer, isA<Ready>());
    expect(
      log.informed.join('\n'),
      allOf(contains('registry'), contains('ledger is not among them')),
      reason: 'one exit code is not a measurement — the record has to show what the listing named',
    );
  });

  test('a namespace holding no releases at all is said as that', () async {
    final _CapturedLog log = _CapturedLog();
    final CheckResult answer = await release.check(
      _contextOn(
        FakeShell()..answers('helm list --namespace ledger -o json', '[]'),
        FakeFiles(<String, String>{path: 'ui:\n  enabled: true\n'}),
        log: log,
      ),
    );

    expect(answer, isA<Ready>());
    expect(log.informed.join('\n'), contains('no releases'));
  });

  test('the chart comparison that decides an upgrade reaches the record', () async {
    final _CapturedLog log = _CapturedLog();
    await release.check(
      _contextOn(
        FakeShell()..answers(
          'helm list --namespace ledger -o json',
          '[{"name":"ledger","status":"deployed","chart":"ledger-0.33.0"}]',
        ),
        FakeFiles(<String, String>{path: 'ui:\n  enabled: true\n'}),
        log: log,
      ),
    );

    expect(
      log.informed.join('\n'),
      allOf(contains('ledger-0.33.0'), contains('ledger-0.34.0')),
      reason: 'held and wanted are the comparison, and the record shows both sides or neither',
    );
  });

  test('values that differ from the file reach the record with the file named', () async {
    final _CapturedLog log = _CapturedLog();
    await release.check(
      machine(file: 'ui:\n  enabled: true\n', held: '{"ui":{"enabled":false}}', log: log),
    );

    expect(log.informed.join('\n'), allOf(contains(path), contains('differ')));
  });

  // WHAT THE UPGRADE ITSELF ANSWERED. A helm upgrade that returns 0 and installs nothing is the
  // shape this is about: output is kept only for a failed command or a `keep_output` row, so the
  // record holds exit codes and no measurement, and the unwind then takes the namespace — and with
  // it the release's own record — before anybody can look. What
  // helm SAID is the one thing that separates an upgrade that did nothing from one whose work was
  // removed after it, and these tests hold that the step says it.

  const String upgrade =
      'helm upgrade --install ledger example-charts/ledger --namespace ledger '
      '--version 0.34.0 --values $path';

  test('the report helm answered with reaches the record', () async {
    final _CapturedLog log = _CapturedLog();
    final FakeShell shell = FakeShell()
      ..answers(
        upgrade,
        'Release "ledger" does not exist. Installing it now.\n'
        'NAME: ledger\n'
        'LAST DEPLOYED: Thu Aug 20 17:38:12 2026\n'
        'NAMESPACE: ledger\n'
        'STATUS: deployed\n'
        'REVISION: 1\n',
      );

    await release.apply(_contextOn(shell, FakeFiles(<String, String>{path: '{}\n'}), log: log));

    expect(
      log.informed.join('\n'),
      allOf(contains('ledger'), contains('deployed'), contains('revision 1')),
      reason: 'an exit code says nothing about whether a release was installed, and helm said it',
    );
    expect(log.warned, isEmpty, reason: 'helm reported a release, which is what this row is for');
  });

  test('an upgrade that returns 0 and answers nothing is recorded as answering nothing', () async {
    // THE DEFECT, planted as it was measured: every command returned 0, and the record could not
    // say whether helm had written twelve lines nobody kept or none at all. A fake shell with no
    // answer for a command returns exactly that — exit 0 and empty output.
    final _CapturedLog log = _CapturedLog();

    await release.apply(
      _contextOn(FakeShell(), FakeFiles(<String, String>{path: '{}\n'}), log: log),
    );

    expect(
      log.warned.join('\n'),
      allOf(contains('returned 0'), contains('nothing at all')),
      reason: 'a silent exit 0 is the case the whole incident turned on, so it is said out loud',
    );
    expect(log.informed, isEmpty, reason: 'nothing was reported, so nothing may read as a report');
  });

  test('an upgrade that answers many lines and no status keeps the LAST of them', () async {
    // The other half of that question, and the half a record without output cannot answer: whether
    // helm said nothing, or said many lines nobody kept. Bounded, because the answer goes on one line
    // of a record — and bounded at the TAIL, because a tool says why it stopped at the end of what
    // it wrote (ansiwise-core recording_ports.dart:59). Keeping the head drops the line a reader
    // came for, and disagrees with what the record does with the same command's output one row over.
    final _CapturedLog log = _CapturedLog();
    final FakeShell shell = FakeShell()
      ..answers(upgrade, <String>[for (int each = 1; each <= 12; each++) 'line $each'].join('\n'));

    await release.apply(_contextOn(shell, FakeFiles(<String, String>{path: '{}\n'}), log: log));

    final String said = log.warned.join('\n');
    expect(said, contains('line 12'), reason: 'the last line is where a tool says why it stopped');
    expect(said, contains('line 3'), reason: 'ten are kept, so twelve lines begin at the third');
    expect(said, isNot(contains('line 1 ')), reason: 'the first two are the ones dropped');
    expect(said, contains('2 line(s) more'), reason: 'what was dropped is counted, not hidden');
  });

  test('a failing upgrade carries what helm wrote on both streams', () async {
    // Measured by hand on the machine: helm writes the line about installing to standard output and
    // the reason it stopped to standard error. A refusal that carried only one of the two dropped
    // half of what an operator reads first.
    final FakeShell shell = FakeShell()
      ..answer(
        upgrade,
        const CommandResult(
          exitCode: 1,
          stdout: 'Release "ledger" does not exist. Installing it now.',
          stderr: 'Error: create: failed to create: namespaces "ledger" not found',
          elapsed: Duration.zero,
        ),
      );

    await expectLater(
      release.apply(_contextOn(shell, FakeFiles(<String, String>{path: '{}\n'}))),
      throwsA(
        isA<CommandFailed>().having(
          (CommandFailed failure) => failure.message,
          'message',
          allOf(contains('namespaces "ledger" not found'), contains('Installing it now')),
        ),
      ),
    );
  });

  test('a release already so has nothing to explain', () async {
    // The innocent neighbour: a machine already in the wanted state produces a Satisfied with its
    // own `because`, and no line about acting — a record that said "not installed" over a release
    // that is there would misdirect exactly the way the bare answer did.
    final _CapturedLog log = _CapturedLog();
    final CheckResult answer = await release.check(
      machine(file: 'ui:\n  enabled: true\n', held: '{"ui":{"enabled":true}}', log: log),
    );

    expect(answer, isA<Satisfied>());
    expect(log.informed, isEmpty);
  });
}

StepContext _contextOn(FakeShell shell, FakeFiles files, {Logger? log}) => StepContext(
  shell: shell,
  files: files,
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

/// A logger the test can read back, kept by level because the level is part of what is asserted:
/// a line the step says at debug is dropped by the default record, so saying it there is not
/// saying it at all.
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
