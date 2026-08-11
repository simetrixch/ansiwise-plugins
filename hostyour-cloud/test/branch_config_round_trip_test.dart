import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

/// The stage config as the WRITER produces it, handed to the things that READ it.
///
/// **Why this file exists.** `write_stage_config` composed a key called `BUILD_PLANE` and
/// `BuildPlane` read one called `BUILD_PLANE_FQDN`, and the two never met. Both halves were tested,
/// and both suites were green, because each half was given a stage config that its own author had
/// typed. The condition could therefore never hold in either direction, and nine rows of the GitOps
/// deployment were skipped on every installation with nothing reporting it.
///
/// **A deploy does not catch this.** A skipped row is not a failure — it is the normal way a
/// condition works — so a run where every one of them was skipped looks exactly like a run of a
/// cluster that wanted none of them.
///
/// **So nothing here is typed by hand.** The template the writer fills is derived from the writer's
/// OWN key list, and the file the readers are given is the file the writer wrote. A rename on either
/// side breaks this file, which is the whole point of it.
void main() {
  const String repository = branchCheckout;
  const String fqdn = 'm1.example.com';
  const String elsewhere = 'build.example.com';
  const WriteStageConfig writer = WriteStageConfig(repository: repository);

  test('every key the writer composes reaches the file, under the name it composed', () async {
    final FakeFiles files = await _filled(writer, fqdn: fqdn, buildPlane: fqdn);
    final Map<String, String> written = _assignmentsIn(
      files.contents['$stageConfigDirectory/${stageConfigPrefix}dev']!,
    );

    for (final MapEntry<String, String> pair in _composed(writer, fqdn: fqdn, buildPlane: fqdn)) {
      expect(
        written[pair.key],
        pair.value,
        reason:
            'the file must carry ${pair.key} under exactly that name, or whatever reads it '
            'finds nothing and reports a machine that says nothing rather than a defect',
      );
    }
  });

  group('the build-plane condition, against the file the writer really wrote', () {
    test('holds HERE when the installation names itself as the build plane', () async {
      final FakeFiles files = await _filled(writer, fqdn: fqdn, buildPlane: fqdn);

      expect(await _holds(const BuildPlane(here: true), files), isTrue);
      expect(await _holds(const BuildPlane(here: false), files), isFalse);
    });

    test('holds ELSEWHERE when the installation names another cluster', () async {
      final FakeFiles files = await _filled(writer, fqdn: fqdn, buildPlane: elsewhere);

      expect(await _holds(const BuildPlane(here: false), files), isTrue);
      expect(await _holds(const BuildPlane(here: true), files), isFalse);
    });

    test('is not confused by the template standing beside the config it wrote', () async {
      final FakeFiles files = await _filled(writer, fqdn: fqdn, buildPlane: fqdn);

      expect(
        files.contents.keys,
        containsAll(<String>[
          '$stageConfigDirectory/$stageConfigTemplate',
          '$stageConfigDirectory/${stageConfigPrefix}dev',
        ]),
        reason:
            'both files really are in the directory — nothing removes the template, and the '
            'writer states that it leaves it exactly as it ships. A test that did not assert this '
            'could pass on a machine that never had a template at all',
      );
      expect(
        (await const BuildPlane(here: true).evaluate(_machine(files))).because,
        isNot(contains('never reduced')),
        reason:
            'the template name begins with the stage-config prefix, so a reader matching the '
            'prefix alone finds two configs on EVERY machine, picks neither, and answers no to '
            'every condition that reads this file',
      );
    });

    test('never answers that the pair could not be found', () async {
      final FakeFiles files = await _filled(writer, fqdn: fqdn, buildPlane: fqdn);
      final String said = (await const BuildPlane(here: true).evaluate(_machine(files))).because;

      expect(
        said,
        isNot(contains('does not set')),
        reason:
            'a missing key is what a spelling divergence looks like from the reading side, and '
            'it answers doesNotHold in BOTH directions — so a run where it is wrong is a run where '
            'every row behind it is silently skipped',
      );
    });
  });
}

/// A machine whose stage config is what [writer] wrote from these answers.
///
/// The template is built from the writer's own key list rather than typed here. A template that
/// declares a key the writer does not compose, or misses one it does, is exactly the divergence this
/// file is here to catch, so it must not be possible to introduce one by hand.
Future<FakeFiles> _filled(
  WriteStageConfig writer, {
  required String fqdn,
  required String buildPlane,
}) async {
  final Arguments answers = _answers(fqdn: fqdn, buildPlane: buildPlane);
  final FakeFiles files = FakeFiles(<String, String>{
    '$branchCheckout/configs/config.example': _templateFor(writer, answers),
  });
  // Applied rather than composed: what the readers get is the file that reached the machine.
  await writer.apply(_contextOn(files, answers));
  return files;
}

/// The template the trunk would ship: every key the writer composes, at an empty value.
String _templateFor(WriteStageConfig writer, Arguments answers) => <String>[
  for (final String key in _composed(
    writer,
    answers: answers,
  ).map((MapEntry<String, String> e) => e.key))
    '# what $key holds\n$key=',
].join('\n');

/// What [writer] composes for these answers, as the pairs it would write.
Iterable<MapEntry<String, String>> _composed(
  WriteStageConfig writer, {
  String? fqdn,
  String? buildPlane,
  Arguments? answers,
}) => writer
    .valuesFrom(_contextOn(FakeFiles(), answers ?? _answers(fqdn: fqdn!, buildPlane: buildPlane!)))
    .entries;

/// Whether [predicate] holds on a machine carrying [files].
Future<bool> _holds(BuildPlane predicate, FakeFiles files) async =>
    (await predicate.evaluate(_machine(files))).held;

/// The answers an installation gives, with only the two this file varies exposed.
Arguments _answers({required String fqdn, required String buildPlane}) =>
    Arguments(<String, Object>{
      'fqdn': fqdn,
      'stage': 'dev',
      'build_plane': buildPlane,
      'unit_apex': 'example.com',
      'platform_domain': 'example.com',
      'alert_recipients': <String>['alerts@example.com'],
      'catalog_repo': 'example-org/tenant-catalog',
      'letsencrypt_email': 'certs@example.com',
      'idp_bootstrap_email': 'admin@example.com',
    });

StepContext _contextOn(FakeFiles files, Arguments answers) => StepContext(
  shell: FakeShell(),
  files: files,
  http: FakeHttp(),
  clock: FakeClock(),
  entropy: FakeEntropy(),
  log: const _SilentLog(),
  step: const StepName('under_test'),
  arguments: Arguments.none,
  answers: answers,
  facts: Facts.none,
);

PredicateContext _machine(FakeFiles files) => PredicateContext(
  shell: FakeShell(),
  files: files,
  http: FakeHttp(),
  clock: FakeClock(),
  log: const _SilentLog(),
);

/// The assignments a stage config states, read the way the readers read them.
Map<String, String> _assignmentsIn(String content) => <String, String>{
  for (final String raw in content.split('\n'))
    if (!raw.trim().startsWith('#') && raw.contains('='))
      raw.substring(0, raw.indexOf('=')).trim(): _unquoted(
        raw.substring(raw.indexOf('=') + 1).trim(),
      ),
};

String _unquoted(String value) => value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

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
