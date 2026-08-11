import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

/// What the stage config has to say before a part of the platform is deployed.
///
/// **Why this file exists at all.** The three toggles decide what a deployment builds, and until now
/// nothing measured them directly — they were exercised only through whole-program runs that always
/// stated a value. So the one case a real machine actually presents, a key standing at its template
/// placeholder, was never asked. It answered the opposite of what the toggle promises, and every
/// suite stayed green.
///
/// **The two toggles are opposites on purpose**, so each case below is asked of BOTH: one whose
/// default is to deploy (the identity provider) and one whose default is not to (the secret store).
/// A test that only asked the second would pass on the wrong reading, because a wrong "no" and a
/// right "no" are the same word.
void main() {
  group('a key the installation never answered', () {
    test('is unset when the file does not name it, and the default decides', () async {
      expect(await deploys(_idp, 'DOMAIN_SUFFIX=m1.example.com\n'), isTrue);
      expect(await deploys(_vault, 'DOMAIN_SUFFIX=m1.example.com\n'), isFalse);
    });

    test(
      'is unset when the file names it EMPTY, which is where a filled template stands',
      () async {
        expect(
          await deploys(_idp, 'ENABLE_IDP=\n'),
          isTrue,
          reason:
              'a template stands with every key at a placeholder, so an empty value is the state a '
              'machine holds until somebody answers it — reading it as a stated no turns the '
              "identity provider's default upside down",
        );
        expect(await deploys(_vault, 'ENABLE_VAULT=\n'), isFalse);
      },
    );

    test('is unset when the file names it as an empty quoted value', () async {
      expect(await deploys(_idp, 'ENABLE_IDP=""\n'), isTrue);
      expect(await deploys(_vault, 'ENABLE_VAULT=""\n'), isFalse);
    });

    test('says in the plan which of the two it was, so a reader can tell them apart', () async {
      expect(await because(_idp, 'DOMAIN_SUFFIX=m1.example.com\n'), contains('does not name'));
      expect(await because(_idp, 'ENABLE_IDP=\n'), contains('leaves ENABLE_IDP empty'));
    });
  });

  group('a key the installation answered', () {
    test('deploys the part when it says exactly true', () async {
      expect(await deploys(_idp, 'ENABLE_IDP=true\n'), isTrue);
      expect(await deploys(_vault, 'ENABLE_VAULT=true\n'), isTrue);
    });

    test('does not deploy it when it says false', () async {
      expect(await deploys(_idp, 'ENABLE_IDP=false\n'), isFalse);
      expect(await deploys(_vault, 'ENABLE_VAULT=false\n'), isFalse);
    });

    // The innocent-looking neighbours. Each of these reads as agreement to a person and says
    // something this installation never defined, which is how a cluster ends up running a component
    // nobody switched on.
    for (final String yes in <String>['1', 'yes', 'True', 'TRUE', 'on']) {
      test('refuses "$yes", which merely reads as yes', () async {
        expect(await deploys(_idp, 'ENABLE_IDP=$yes\n'), isFalse);
        expect(await deploys(_vault, 'ENABLE_VAULT=$yes\n'), isFalse);
      });
    }
  });

  group('a stage config that cannot be read', () {
    test('deploys nothing, whatever the default would have been', () async {
      expect(await deploys(_idp, null), isFalse);
      expect(await deploys(_vault, null), isFalse);
    });
  });
}

/// The identity provider's toggle, whose default is to deploy.
const StageToggle _idp = StageToggle(
  key: 'ENABLE_IDP',
  part: 'the identity provider',
  whenUnset: true,
);

/// The secret store's toggle, whose default is not to.
const StageToggle _vault = StageToggle(
  key: 'ENABLE_VAULT',
  part: 'the secret store',
  whenUnset: false,
);

/// Whether [toggle] deploys its part on a machine whose stage config holds [config].
///
/// A null [config] is a checkout that carries none at all.
Future<bool> deploys(StageToggle toggle, String? config) async =>
    (await toggle.evaluate(_machine(config))).held;

/// What [toggle] says in the plan about a machine whose stage config holds [config].
Future<String> because(StageToggle toggle, String? config) async =>
    (await toggle.evaluate(_machine(config))).because;

/// A machine carrying one stage config, or none when [config] is null.
PredicateContext _machine(String? config) => PredicateContext(
  shell: FakeShell(),
  files: FakeFiles(<String, String>{'$stageConfigDirectory/${stageConfigPrefix}dev': ?config}),
  http: FakeHttp(),
  clock: FakeClock(),
  log: const _SilentLog(),
);

/// A logger that keeps what it is told, because a predicate is measured by what it answers.
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
