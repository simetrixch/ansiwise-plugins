import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Making a checkout able to write to its remote, and where the credential is allowed to be while
/// that is true.
///
/// **It arranges its own checkout rather than the shared one.** The shared arrangement answers an
/// SSH remote, which is exactly the address this step must refuse — so it can serve as one case
/// here and cannot serve as any of the others.
///
/// The property everything circles is WHERE the credential ends up: in one file inside the git
/// directory, at mode 384, and in no command argument at all — because an argument is in the
/// process listing and in the record, and a remote address carrying one is at rest for as long as
/// the checkout stands and is printed by every `git remote -v`.
void main() {
  const String path = '/srv/checkout';
  const String gitDirectory = '$path/.git';
  const String storeFile = '$gitDirectory/push-credentials';
  const String address = 'https://code.example.com/acme/acme-deploy.git';
  const String user = 'writer';
  // Carries an "@" and a ":" on purpose: git's store helper reads each line as a URL, so a
  // credential written raw would split the userinfo somewhere else.
  const String credential = 'NotAReal:Credential@ItIsATestFixture';
  // The same value as git's store file spells it. A command carrying THIS is as much a leak as one
  // carrying the raw text — it is one decoding away — so both are what "in no command" means.
  const String encoded = 'NotAReal%3ACredential%40ItIsATestFixture';
  const String settingsFile = '$path/settings/secrets.dev';
  const String settingsKey = 'PUSH_CREDENTIAL';
  const String helper = 'store --file=$storeFile';
  const String line = 'https://$user:$encoded@code.example.com\n';

  const GitPushCredential fromAnswer = GitPushCredential(
    repository: path,
    remote: remote,
    credentialAnswer: 'push_credential',
    credentialUser: user,
  );

  const GitPushCredential fromFile = GitPushCredential(
    repository: path,
    remote: remote,
    credentialFile: '$path/settings/secrets.<stage>',
    credentialKey: settingsKey,
    credentialUser: user,
    runAnswer: 'stage',
  );

  /// A checkout with an https remote and nothing arranged for a push.
  FakeShell pushable({String at = address, List<String> helpers = const <String>[]}) {
    final FakeShell shell = FakeShell()
      ..answers('git -C $path rev-parse --absolute-git-dir', '$gitDirectory\n')
      ..answers('git -C $path remote get-url $remote', '$at\n');
    if (helpers.isEmpty) {
      shell.fails('git -C $path config --local --get-all credential.helper');
    } else {
      shell.answers(
        'git -C $path config --local --get-all credential.helper',
        '${helpers.join('\n')}\n',
      );
    }
    return shell;
  }

  /// A run holding the credential as the answer this row names.
  StepContext holding(FakeShell shell, {FakeFiles? files}) => contextOn(
    shell: shell,
    files: files ?? FakeFiles(),
    answerName: 'push_credential',
    name: credential,
  );

  group('making the checkout able to write', () {
    test('a checkout with no helper and no credential file has work to do', () async {
      expect(await fromAnswer.check(holding(pushable())), isA<Ready>());
    });

    test('the credential is written into the git directory, owner-only', () async {
      final FakeFiles files = FakeFiles();
      await fromAnswer.apply(holding(pushable(), files: files));

      expect(files.contents[storeFile], line);
      expect(files.modes[storeFile], 384);
    });

    test(
      'THE CREDENTIAL IS IN NO COMMAND, so it is in no process listing and in no record',
      () async {
        final FakeShell shell = pushable();
        await fromAnswer.apply(holding(shell, files: FakeFiles()));

        expect(
          shell.ran.where((String each) => each.contains(credential) || each.contains(encoded)),
          isEmpty,
        );
      },
    );

    test('the helper list is reset and then pointed at that file, locally', () async {
      final FakeShell shell = pushable();
      await fromAnswer.apply(holding(shell, files: FakeFiles()));

      // The empty value first: local configuration is read after system and global, so without it
      // a helper the ACCOUNT configured stands ahead of this one and decides.
      expect(shell.ran, contains('git -C $path config --replace-all credential.helper '));
      expect(shell.ran, contains('git -C $path config --add credential.helper $helper'));
      expect(shell.ran.where((String each) => each.contains('--global')), isEmpty);
    });

    test('a second run finds it already done and has nothing to do', () async {
      // THE COMMANDS REALLY TAKE EFFECT HERE, and that is the whole of what makes this measure
      // anything. A fake shell records a command and changes nothing, so a checkout arranged by
      // hand to answer what this step wants would satisfy the second check whatever the step did
      // with the first. Configured this way, the values the second check reads are the ones the
      // step's own two commands produced.
      final FakeFiles files = FakeFiles();
      final FakeShell shell = pushable();
      final List<String> configured = <String>[];
      void asGitWouldNowAnswer() {
        if (configured.isEmpty) {
          shell.fails('git -C $path config --local --get-all credential.helper');
          return;
        }
        shell.answers(
          'git -C $path config --local --get-all credential.helper',
          '${configured.join('\n')}\n',
        );
      }

      shell
        ..changes('git -C $path config --replace-all credential.helper ', () {
          configured
            ..clear()
            ..add('');
          asGitWouldNowAnswer();
        })
        ..changes('git -C $path config --add credential.helper $helper', () {
          configured.add(helper);
          asGitWouldNowAnswer();
        });

      await fromAnswer.apply(holding(shell, files: files));

      expect(await fromAnswer.check(holding(shell, files: files)), isA<Satisfied>());
    });
  });

  group('what it refuses rather than reporting success over', () {
    // THE THREE SHAPES OF "NOT AN HTTPS ADDRESS", each with its own case, because one refusal
    // covering all three would let two of the tests pass while nothing measured the third. A
    // credential helper answers an https address and nothing else, so configuring one over any of
    // these would leave the checkout exactly as unpushable while the row reported success.
    test('a remote written the way an SSH one is', () async {
      final CheckResult answer = await fromAnswer.check(
        holding(pushable(at: 'git@code.example.com:acme/acme-deploy.git')),
      );

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('git@code.example.com'));
    });

    test('a remote served over plain http, which parses and is still the wrong scheme', () async {
      final CheckResult answer = await fromAnswer.check(
        holding(pushable(at: 'http://code.example.com/acme/acme-deploy.git')),
      );

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('http://code.example.com'));
    });

    test('a remote with the right scheme and no host in it', () async {
      // What the composed line would otherwise carry: a credential and an "@" with nothing after
      // it, which git's store reads as a host of no characters and matches against nothing.
      expect(await fromAnswer.check(holding(pushable(at: 'https://'))), isA<Blocked>());
    });

    test('a remote whose address already carries a credential of its own', () async {
      final CheckResult answer = await fromAnswer.check(
        holding(pushable(at: 'https://writer:already@code.example.com/acme/acme-deploy.git')),
      );

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('inside its own address'));
    });

    test('a row naming both credential sources, before the machine is asked anything', () async {
      const GitPushCredential both = GitPushCredential(
        repository: path,
        remote: remote,
        credentialAnswer: 'push_credential',
        credentialFile: settingsFile,
        credentialKey: settingsKey,
        credentialUser: user,
      );
      final FakeShell shell = pushable();

      expect(await both.check(holding(shell)), isA<Blocked>());
      expect(shell.ran, isEmpty);
    });

    test('a row naming neither', () async {
      const GitPushCredential neither = GitPushCredential(
        repository: path,
        remote: remote,
        credentialUser: user,
      );

      expect(await neither.check(holding(pushable())), isA<Blocked>());
    });

    test('a row naming a file and no key in it', () async {
      const GitPushCredential half = GitPushCredential(
        repository: path,
        remote: remote,
        credentialFile: settingsFile,
        credentialUser: user,
      );

      expect(await half.check(holding(pushable())), isA<Blocked>());
    });
  });

  group('where the credential comes from', () {
    test('the file the row names, with the run\'s own value in the path', () async {
      final FakeFiles files = FakeFiles(<String, String>{
        settingsFile: '# what a push from this checkout is made with\n$settingsKey=$credential\n',
      });
      final StepContext context = contextOn(
        shell: pushable(),
        files: files,
        answerName: 'stage',
        name: 'dev',
      );

      await fromFile.apply(context);

      expect(files.contents[storeFile], line);
    });

    test('and a run holding no such answer is refused by the answer the row named', () async {
      final CheckResult answer = await fromAnswer.check(
        contextOn(shell: pushable(), answerName: 'something_else', name: credential),
      );

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('push_credential'));
    });
  });

  group('taking it back', () {
    test('a checkout that carried its own credential and helper keeps exactly those', () async {
      const String theirs = 'https://somebody:theirown@code.example.com\n';
      const String theirHelper = 'cache --timeout=3600';
      final FakeFiles files = FakeFiles(<String, String>{storeFile: theirs});
      final FakeShell shell = pushable(helpers: const <String>[theirHelper]);
      final StepContext context = holding(shell, files: files);

      final GitPushCredentialBefore before = await fromAnswer.capture(context);
      await fromAnswer.apply(context);
      await fromAnswer.undo(context, before);

      expect(files.contents[storeFile], theirs);
      expect(shell.ran, contains('git -C $path config --add credential.helper $theirHelper'));
      expect(
        shell.ran.where((String each) => each.contains('--add credential.helper $helper')).length,
        1,
        reason: 'the undo put back what stood there and did not add this run\'s own again',
      );
    });

    test('THE INNOCENT NEIGHBOUR: a checkout that carried none is left carrying none', () async {
      final FakeFiles files = FakeFiles();
      final FakeShell shell = pushable();
      final StepContext context = holding(shell, files: files);

      final GitPushCredentialBefore before = await fromAnswer.capture(context);
      await fromAnswer.apply(context);
      await fromAnswer.undo(context, before);

      expect(files.contents.containsKey(storeFile), isFalse);
      expect(shell.ran, contains('git -C $path config --unset-all credential.helper'));
    });
  });
}
