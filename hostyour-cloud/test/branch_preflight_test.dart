import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

/// What has to be true about this run's own answer before one line of an installation branch is
/// written.
///
/// **What is left here is the half only this product can decide.** Whether the checkout can commit,
/// whether the remote would accept a push, and whether a branch can be cut are questions about git,
/// and they are asked by `ansiwise-git` and measured in that package's own suite. What a domain is
/// nothing in git knows: `m1_test.example.com` is a branch name git takes without complaint and a
/// host no resolver will ever answer for, and this refusal is what stops that reaching a manifest.
void main() {
  const String fqdn = 'm1.example.com';

  StepContext contextOn({String domain = fqdn}) => StepContext(
    shell: FakeShell(),
    files: FakeFiles(),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    // The domain is an ANSWER: nobody can write one into a file that ships to every installation,
    // so it varies per case here rather than per step instance.
    answers: Arguments(<String, Object>{'fqdn': domain}),
    facts: Facts.none,
  );

  group('the domain is measured before anything else runs', () {
    const RequireInstallationDomain gate = RequireInstallationDomain();

    test('a domain of at least two labels is what this installation is', () async {
      expect(await gate.check(contextOn()), isA<Satisfied>());
    });

    test('the placeholder is not an answer, and cannot become an installation', () async {
      // The value the product carries for a domain reads as unset wherever it is met, so a branch
      // named after it would be indistinguishable from a tree nobody stamped.
      final CheckResult answer = await gate.check(contextOn(domain: FqdnSelection.placeholder));
      expect((answer as Blocked).reason, contains(FqdnSelection.placeholder));
    });

    test('a label with an underscore is refused before anything exists', () async {
      // git would take it as a branch name and no resolver would ever take it as a host, so the
      // typo used to survive as far as the first failed lookup.
      final CheckResult answer = await gate.check(contextOn(domain: 'm1_test.example.com'));
      expect((answer as Blocked).reason, contains('not a domain name'));
    });

    test('one label is a machine name and not a domain', () async {
      expect(await gate.check(contextOn(domain: 'm1')), isA<Blocked>());
    });

    test('it asks no machine anything', () async {
      final FakeShell shell = FakeShell();
      await gate.check(
        StepContext(
          shell: shell,
          files: FakeFiles(),
          http: FakeHttp(),
          clock: FakeClock(),
          entropy: FakeEntropy(),
          log: const _SilentLog(),
          step: const StepName('under_test'),
          arguments: Arguments.none,
          answers: const Arguments(<String, Object>{'fqdn': fqdn}),
          facts: Facts.none,
        ),
      );
      expect(
        shell.ran,
        isEmpty,
        reason: 'the answer alone decides this, which is why it stands first in the program',
      );
    });
  });

  group('the grammar is the one every domain-shaped value is measured against', () {
    test('the cluster map measures its four domains with it', () {
      // Named here because the grammar lives on the step above and four other values are held to it
      // in write_cluster_map. A second grammar for those would let one of them accept what this
      // one refuses.
      expect(RequireInstallationDomain.isFqdn('example.com'), isTrue);
      expect(RequireInstallationDomain.isFqdn('m1.example.com'), isTrue);
      expect(RequireInstallationDomain.isFqdn('M1.example.com'), isFalse);
      expect(RequireInstallationDomain.isFqdn('m1'), isFalse);
      expect(RequireInstallationDomain.isFqdn('m1_test.example.com'), isFalse);
      expect(RequireInstallationDomain.isFqdn('-m1.example.com'), isFalse);
    });
  });
}

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
