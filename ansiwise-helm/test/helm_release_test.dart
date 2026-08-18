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
    helm: <String>['helm'],
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
