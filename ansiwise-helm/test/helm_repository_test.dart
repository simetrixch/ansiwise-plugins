import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_helm/ansiwise_helm.dart';
import 'package:test/test.dart';

/// What the undo of a repository registration takes back: the overwrite, and nothing more.
///
/// The removal these tests forbid was measured misdirecting on a machine: any genuine failure at a
/// row below the registration unwound past it, the undo removed the repository, and the NEXT
/// attempt failed earlier — at the release, with `repo <name> not found` — sending whoever read the
/// record to the repository row, where nothing was wrong.
void main() {
  /// The repository under test, invented rather than borrowed, for the same reason the release
  /// tests invent theirs: these tests are about the undo, and the undo does not care whose charts
  /// the index holds.
  const HelmRepository repository = HelmRepository(
    name: 'example-charts',
    url: 'https://charts.example.test',
    helm: Helm(),
  );

  test('a name helm held nothing under stands after the undo', () async {
    // THE DEFECT THIS FORBIDS: `helm repo remove` on the unwind. The registration installs nothing
    // and nothing consults it unless a row names it, so removing it repairs nothing — it only makes
    // the next attempt fail at a row where nothing is wrong.
    final FakeShell shell = FakeShell();

    await repository.undo(_contextOn(shell), null);

    expect(
      shell.ran,
      isNot(contains('helm repo remove example-charts')),
      reason:
          'removing the registration makes the next attempt fail at the release below it with '
          '"repo not found", pointing at this row, where nothing is wrong',
    );
  });

  test('what stands is said to the record', () async {
    // The unwind writes "taken back" around every undo, and this one deliberately leaves something
    // standing — so the step says so itself, or the record claims a removal that never happened.
    final _CapturedLog log = _CapturedLog();

    await repository.undo(_contextOn(FakeShell(), log: log), null);

    expect(log.informed.join('\n'), contains('example-charts'));
  });

  test('an address the add overwrote is put back', () async {
    // The innocent neighbour: an address registered before the run belongs to whatever registered
    // it, and after `--force-update` only the capture still says what it was. This half of the undo
    // is a restoration, and leaving it out would turn "leave the registration standing" into
    // "keep the overwrite".
    final FakeShell shell = FakeShell();

    await repository.undo(_contextOn(shell), 'https://charts.before.test');

    expect(
      shell.ran,
      contains('helm repo add example-charts https://charts.before.test --force-update'),
    );
  });
}

StepContext _contextOn(FakeShell shell, {Logger? log}) => StepContext(
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

final class _CapturedLog implements Logger {
  final List<String> informed = <String>[];

  @override
  void debug(String message) {}

  @override
  void info(String message) => informed.add(message);

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
