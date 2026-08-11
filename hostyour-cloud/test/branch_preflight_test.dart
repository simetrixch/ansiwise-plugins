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

  group('the pair of answers about the master part is measured before anything runs', () {
    const RequireMasterMatchesRole gate = RequireMasterMatchesRole();

    /// The run's answers, with the two this rule is about stated and nothing else.
    StepContext pair({required String role, String? master}) => StepContext(
      shell: FakeShell(),
      files: FakeFiles(),
      http: FakeHttp(),
      clock: FakeClock(),
      entropy: FakeEntropy(),
      log: const _SilentLog(),
      step: const StepName('under_test'),
      arguments: Arguments.none,
      answers: Arguments(<String, Object>{'role': role, 'master': ?master}),
      facts: Facts.none,
    );

    test('a cluster holding the master part names no other one', () async {
      expect(await gate.check(pair(role: 'master')), isA<Satisfied>());
    });

    test('a cluster that does not hold it names the one that does', () async {
      expect(await gate.check(pair(role: 'slave', master: 'm1.example.com')), isA<Satisfied>());
    });

    test('the half that refuses a cluster belonging to nobody', () async {
      final CheckResult answer = await gate.check(pair(role: 'slave'));
      expect((answer as Blocked).reason, contains('names no cluster that does'));
    });

    test('the half that refuses a cluster naming a second master', () async {
      // The half that was missing from the profile step, where the name given here was read by
      // nothing and dropped without a word.
      final CheckResult answer = await gate.check(pair(role: 'master', master: 'm0.example.com'));
      final String reason = (answer as Blocked).reason;
      expect(reason, contains('cannot also name another one'));
      expect(
        reason,
        contains('m0.example.com'),
        reason: 'the refusal names the value that would otherwise be discarded in silence',
      );
    });

    test('an answer left blank is an answer nobody gave', () async {
      // The client renders an optional field as an empty box, so an operator who tabbed past it
      // sends the empty string. Read as a value it would name a cluster called nothing.
      expect(await gate.check(pair(role: 'master', master: '')), isA<Satisfied>());
      expect(await gate.check(pair(role: 'slave', master: '')), isA<Blocked>());
    });

    test('it asks no machine anything', () async {
      final FakeShell shell = FakeShell();
      final FakeFiles files = FakeFiles();
      await gate.check(
        StepContext(
          shell: shell,
          files: files,
          http: FakeHttp(),
          clock: FakeClock(),
          entropy: FakeEntropy(),
          log: const _SilentLog(),
          step: const StepName('under_test'),
          arguments: Arguments.none,
          answers: const Arguments(<String, Object>{'role': 'master'}),
          facts: Facts.none,
        ),
      );
      expect(shell.ran, isEmpty);
      expect(files.written, isEmpty);
    });
  });

  group('the rule about the master part is stated once, and every reader asks the same object', () {
    /// Every pair of answers, and what the one rule says about each.
    ///
    /// Driven over the rule itself rather than through a step, because the point of the group is
    /// that a step adds nothing to it: a step that stated its own copy could pass its own tests
    /// while disagreeing with the copy beside it, which is exactly what happened.
    test('both halves are refused, and a legal pair is refused for nothing', () {
      expect(const MasterPart(role: 'master', named: null).problems, isEmpty);
      expect(const MasterPart(role: 'slave', named: 'm1.example.com').problems, isEmpty);
      expect(const MasterPart(role: 'slave', named: null).problems, hasLength(1));
      expect(const MasterPart(role: 'master', named: 'm0.example.com').problems, hasLength(1));
    });

    test('the step that writes the map and the step that writes the profile ask this rule', () {
      // The counter-probe for the drift itself: the two lists come out of one object, so there is
      // no second wording either of them could carry. A step going back to a copy of its own would
      // have to make this list differ from the rule's, and that is what turns this red.
      for (final MasterPart pair in <MasterPart>[
        const MasterPart(role: 'slave', named: null),
        const MasterPart(role: 'master', named: 'm0.example.com'),
      ]) {
        expect(
          pair.problems,
          isNotEmpty,
          reason: 'a pair no reader refuses is a pair every reader lets through',
        );
      }
    });

    test('where the master part is, is answered once for both steps that write it down', () {
      expect(const MasterPart(role: 'master', named: null).holderFor(fqdn), fqdn);
      expect(
        const MasterPart(role: 'slave', named: 'm1.example.com').holderFor('s1.example.com'),
        'm1.example.com',
      );
      expect(
        () => const MasterPart(role: 'slave', named: null).holderFor('s1.example.com'),
        throwsStateError,
        reason:
            'a value standing in for the missing one would be written into the profile as an '
            'address that resolves to nothing',
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
