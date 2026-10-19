import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Asking a remote whether it publishes the branch this run names, both ways round.
void main() {
  const RemoteHasBranch carrying = RemoteHasBranch(
    repository: repository,
    remote: remote,
    nameAnswer: nameAnswer,
  );
  const RemoteHasBranch lacking = RemoteHasBranch(
    repository: repository,
    remote: remote,
    nameAnswer: nameAnswer,
    holdsWhenPublished: false,
  );

  const String asking = 'git -C $repository ls-remote --heads $remote refs/heads/$branch';

  group('what the remote publishes decides both shapes', () {
    test('a published branch holds the one shape and not the other', () async {
      final FakeShell shell = checkout()..answers(asking, 'e5e5e5\trefs/heads/$branch\n');

      expect((await carrying.evaluate(contextOn(shell: shell))).held, isTrue);
      expect((await lacking.evaluate(contextOn(shell: shell))).held, isFalse);
    });

    test('a remote publishing none holds the other shape', () async {
      final FakeShell shell = checkout()..answers(asking, '');

      expect((await carrying.evaluate(contextOn(shell: shell))).held, isFalse);
      expect((await lacking.evaluate(contextOn(shell: shell))).held, isTrue);
    });

    test('both directions say what the remote said', () async {
      final FakeShell shell = checkout()..answers(asking, 'e5e5e5\trefs/heads/$branch\n');

      expect((await carrying.evaluate(contextOn(shell: shell))).because, contains(branch));
      expect((await lacking.evaluate(contextOn(shell: shell))).because, contains(branch));
    });

    test('a longer branch ending in this name is not this branch', () async {
      final FakeShell shell = checkout()..answers(asking, 'f6f6f6\trefs/heads/work/$branch\n');

      expect((await carrying.evaluate(contextOn(shell: shell))).held, isFalse);
    });

    test('it changes nothing', () async {
      final FakeShell shell = checkout()..answers(asking, 'e5e5e5\trefs/heads/$branch\n');
      await carrying.evaluate(contextOn(shell: shell));

      expect(shell.commands.where((Command each) => !each.observes), isEmpty);
    });
  });

  group('what it refuses to answer at all', () {
    test('a remote that could not be asked, in BOTH shapes', () async {
      // The refusal has to reach both, or the shape that reads "it publishes none" would turn a
      // remote nobody reached into a decision to cut a branch on top of one already published.
      final FakeShell shell = checkout()
        ..fails(asking, exitCode: 128, stderr: 'fatal: could not read Username');

      expect(
        () => carrying.evaluate(contextOn(shell: shell)),
        throwsA(isA<ConditionUnanswerable>()),
      );
      expect(
        () => lacking.evaluate(contextOn(shell: shell)),
        throwsA(isA<ConditionUnanswerable>()),
      );
    });

    test('the refusal names the remote, the branch and what git said', () async {
      final FakeShell shell = checkout()
        ..fails(asking, exitCode: 128, stderr: 'fatal: could not read Username');

      await expectLater(
        () => carrying.evaluate(contextOn(shell: shell)),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            allOf(contains(remote), contains(branch), contains('could not read Username')),
          ),
        ),
      );
    });

    test('a run holding no answer under the name it was pointed at', () async {
      final FakeShell shell = checkout();

      await expectLater(
        () => carrying.evaluate(contextOn(shell: shell, name: null)),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            contains(nameAnswer),
          ),
        ),
      );
      expect(shell.ran, isEmpty, reason: 'there is no branch to ask a remote about');
    });
  });

  test('the configuration decides which answer, and nothing here assumes one', () async {
    const RemoteHasBranch other = RemoteHasBranch(
      repository: repository,
      remote: remote,
      nameAnswer: 'somewhere_else',
    );
    final FakeShell shell = checkout()
      ..answers(
        'git -C $repository ls-remote --heads $remote refs/heads/from-elsewhere',
        'a7a7a7\trefs/heads/from-elsewhere\n',
      );

    final PredicateResult answer = await other.evaluate(
      contextOn(shell: shell, name: 'from-elsewhere', answerName: 'somewhere_else'),
    );
    expect(answer.held, isTrue);
  });

  // A remote that is not served to anybody is asked with the credential the run holds. The run
  // holds it as an ANSWER because the machine may have no settings file yet, and a run that lacks
  // the answer asks as it always did.
  group('a remote asked with the credential the run holds', () {
    const String credentialAnswer = 'forge_token';
    const String account = 'reader';
    const String credential = 'NotARealCredentialItIsATestFixture';
    const String forgeUrl = 'https://forge.example.com/acme/platform.git';
    final String authorization = base64Encode(utf8.encode('$account:$credential'));

    const RemoteHasBranch withCredential = RemoteHasBranch(
      repository: repository,
      remote: remote,
      nameAnswer: nameAnswer,
      credentialAnswer: credentialAnswer,
      credentialUser: account,
    );

    /// A checkout whose remote is served at [address] and publishes the branch.
    FakeShell servedAt(String address) => checkout()
      ..answers('git -C $repository remote get-url $remote', '$address\n')
      ..answers(asking, 'e5e5e5\trefs/heads/$branch\n');

    StepContext holding(Shell shell, {bool credentialGiven = true}) => contextOn(
      shell: shell,
      also: <String, Object>{if (credentialGiven) credentialAnswer: credential},
    );

    Command listing(FakeShell shell) =>
        shell.commands.firstWhere((Command each) => each.arguments.contains('ls-remote'));

    test('INNOCENT CASE: the credential rides the environment of the one ls-remote, keyed on the '
        "remote's host", () async {
      final FakeShell shell = servedAt(forgeUrl);
      final PredicateResult answer = await withCredential.evaluate(holding(shell));

      expect(answer.held, isTrue);
      expect(listing(shell).environment, <String, String>{
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'http.https://forge.example.com/.extraHeader',
        'GIT_CONFIG_VALUE_0': 'Authorization: Basic $authorization',
      });
    });

    test('INNOCENT CASE: a port in the remote address is part of the key git matches on', () async {
      final FakeShell shell = servedAt('https://forge.example.com:8443/acme/platform.git');
      await withCredential.evaluate(holding(shell));

      expect(
        listing(shell).environment['GIT_CONFIG_KEY_0'],
        'http.https://forge.example.com:8443/.extraHeader',
      );
    });

    test('INNOCENT CASE: the credential is in no argument and the predicate only looks', () async {
      final FakeShell shell = servedAt(forgeUrl);
      await withCredential.evaluate(holding(shell));

      for (final String command in shell.ran) {
        expect(command, isNot(contains(credential)));
        expect(command, isNot(contains(authorization)));
      }
      expect(shell.commands.where((Command each) => !each.observes), isEmpty);
    });

    test('INNOCENT CASE: the record of the run does not contain the credential', () async {
      final MemoryRecorder recorder = MemoryRecorder(FakeClock());
      await withCredential.evaluate(holding(recording(servedAt(forgeUrl), recorder)));

      final List<String> record = <String>[
        for (final CommandStarted started in recorder.only<CommandStarted>()) ...started.argv,
        ...recorder.output,
      ];
      expect(record, isNotEmpty, reason: 'a record that holds nothing proves nothing about it');
      for (final String line in record) {
        expect(line, isNot(contains(credential)));
        expect(line, isNot(contains(authorization)));
      }
    });

    test('INNOCENT CASE: a run lacking the answer asks as it always did, with no header', () async {
      final FakeShell shell = servedAt(forgeUrl);
      final PredicateResult answer = await withCredential.evaluate(
        holding(shell, credentialGiven: false),
      );

      expect(answer.held, isTrue);
      expect(listing(shell).environment, isEmpty);
      expect(
        shell.ran.where((String each) => each.contains('get-url')),
        isEmpty,
        reason: 'nothing to present, so the address is not read',
      );
    });

    test(
      'INNOCENT CASE: a run holding an empty value asks as it always did, with no header',
      () async {
        final FakeShell shell = servedAt(forgeUrl);
        await withCredential.evaluate(
          contextOn(shell: shell, also: const <String, Object>{credentialAnswer: ''}),
        );

        expect(listing(shell).environment, isEmpty);
      },
    );

    test('INNOCENT CASE: a condition naming no credential asks with no header', () async {
      final FakeShell shell = servedAt(forgeUrl);
      await carrying.evaluate(holding(shell));

      expect(listing(shell).environment, isEmpty);
    });

    test(
      'INNOCENT CASE: the factory reads both arguments off what one installation wrote',
      () async {
        final RemoteHasBranch built = RemoteHasBranch.carrying(
          const Arguments(<String, Object>{
            'repository': repository,
            'name_answer': nameAnswer,
            'credential_answer': credentialAnswer,
            'credential_user': account,
          }),
        );
        final FakeShell shell = servedAt(forgeUrl);
        await built.evaluate(holding(shell));

        expect(
          listing(shell).environment['GIT_CONFIG_VALUE_0'],
          'Authorization: Basic $authorization',
        );
      },
    );

    for (final (String shape, RemoteHasBranch condition) in <(String, RemoteHasBranch)>[
      ('carrying', withCredential),
      (
        'lacking',
        const RemoteHasBranch(
          repository: repository,
          remote: remote,
          nameAnswer: nameAnswer,
          holdsWhenPublished: false,
          credentialAnswer: credentialAnswer,
          credentialUser: account,
        ),
      ),
    ]) {
      test('PLANTED DEFECT: a remote that refuses the credential is unanswerable in the $shape '
          'shape, never "it publishes none"', () async {
        final FakeShell shell = servedAt(forgeUrl)
          ..fails(asking, exitCode: 128, stderr: 'fatal: Authentication failed');

        await expectLater(
          () => condition.evaluate(holding(shell)),
          throwsA(
            isA<ConditionUnanswerable>().having(
              (ConditionUnanswerable refusal) => refusal.because,
              'because',
              allOf(
                contains('Authentication failed'),
                isNot(contains(credential)),
                isNot(contains(authorization)),
              ),
            ),
          ),
        );
      });
    }

    test('PLANTED DEFECT: credential_answer without credential_user is refused by name, and '
        'nothing is asked', () async {
      const RemoteHasBranch half = RemoteHasBranch(
        repository: repository,
        remote: remote,
        nameAnswer: nameAnswer,
        credentialAnswer: credentialAnswer,
      );
      final FakeShell shell = servedAt(forgeUrl);

      await expectLater(
        () => half.evaluate(holding(shell)),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            allOf(contains('credential_answer'), contains('credential_user')),
          ),
        ),
      );
      expect(shell.ran, isEmpty);
    });

    test('PLANTED DEFECT: credential_user without credential_answer is refused by name, and '
        'nothing is asked', () async {
      const RemoteHasBranch half = RemoteHasBranch(
        repository: repository,
        remote: remote,
        nameAnswer: nameAnswer,
        credentialUser: account,
      );
      final FakeShell shell = servedAt(forgeUrl);

      await expectLater(
        () => half.evaluate(holding(shell, credentialGiven: false)),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            allOf(contains('credential_answer'), contains('credential_user')),
          ),
        ),
      );
      expect(shell.ran, isEmpty);
    });

    for (final String address in <String>[
      'git@forge.example.com:acme/platform.git',
      'http://forge.example.com/acme/platform.git',
    ]) {
      test(
        'PLANTED DEFECT: $address is not an https address, so it cannot be shown a credential and '
        'is refused rather than asked without one',
        () async {
          final FakeShell shell = servedAt(address);

          await expectLater(
            () => withCredential.evaluate(holding(shell)),
            throwsA(
              isA<ConditionUnanswerable>().having(
                (ConditionUnanswerable refusal) => refusal.because,
                'because',
                allOf(contains(remote), contains('https'), isNot(contains(credential))),
              ),
            ),
          );
          expect(shell.ran.where((String each) => each.contains('ls-remote')), isEmpty);
        },
      );
    }

    test('PLANTED DEFECT: a remote whose address cannot be read is refused', () async {
      final FakeShell shell = servedAt(forgeUrl)
        ..fails('git -C $repository remote get-url $remote', stderr: 'error: No such remote');

      await expectLater(
        () => withCredential.evaluate(holding(shell)),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            contains('No such remote'),
          ),
        ),
      );
      expect(shell.ran.where((String each) => each.contains('ls-remote')), isEmpty);
    });
  });
}
