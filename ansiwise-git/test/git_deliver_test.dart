import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Recording what a run wrote, and proving it left the machine.
///
/// **Both exist because of one measurement.** A real run cut a branch, stamped every marker, wrote
/// four files and ended `exit 0` — leaving nineteen changed paths in a working tree and nothing on
/// the remote. Every step was right about itself and the installation branch did not exist.
void main() {
  const List<String> paths = <String>['clusters', 'configs'];
  const GitCommit commit = GitCommit(
    repository: repository,
    paths: paths,
    message: 'what this run wrote',
  );
  const GitPush push = GitPush(repository: repository, remote: remote);

  const String tip = 'a1b2c3d4';

  FakeShell dirty({String status = ' M clusters/one.yaml\n'}) =>
      checkout(head: branch)
        ..answers('git -C $repository status --porcelain -- clusters configs', status);

  group('recording what was written', () {
    test('a tree with changes among the named paths has work to do', () async {
      expect(await commit.check(contextOn(shell: dirty())), isA<Ready>());
    });

    test('THE INNOCENT NEIGHBOUR: a tree with none is already satisfied', () async {
      // Without this, a step that always reported work would pass the assertion above and make every
      // second run of a program look unfinished.
      expect(await commit.check(contextOn(shell: dirty(status: ''))), isA<Satisfied>());
    });

    test('every named path is staged BY NAME, never as one blanket add', () async {
      // A blanket add records whatever else stands in the checkout — a file somebody was editing, a
      // leftover from a run that failed — as part of this installation.
      final FakeShell shell = dirty();
      await commit.apply(contextOn(shell: shell));

      expect(shell.ran, contains('git -C $repository add -- clusters'));
      expect(shell.ran, contains('git -C $repository add -- configs'));
      expect(shell.ran.where((String c) => c.contains('add -- .')), isEmpty);
    });

    test('a second run records nothing and does not fail for it', () async {
      final FakeShell shell = dirty(status: '');
      await commit.apply(contextOn(shell: shell));

      expect(shell.ran.where((String c) => c.contains('commit')), isEmpty);
    });

    test(
      'a path this row names and the checkout does not hold is refused before anything is staged',
      () async {
        // The shape this reproduces: a directory is renamed in the tree, the rows that write into
        // it follow, and this row goes on naming the old name. git add refuses a pathspec matching
        // nothing, so the run stages the paths before it and then dies — with two files written, no
        // commit, and git's message rather than this step's.
        const GitCommit naming = GitCommit(
          repository: repository,
          paths: <String>['clusters', 'cluster'],
          message: 'what this run wrote',
        );
        final FakeShell shell = checkout(head: branch)
          ..answers(
            'git -C $repository status --porcelain -- clusters cluster',
            ' M clusters/one.yaml\n',
          )
          ..fails('git -C $repository ls-files --error-unmatch -- cluster');

        expect(
          await naming.check(contextOn(shell: shell)),
          isA<Blocked>().having((Blocked blocked) => blocked.reason, 'reason', contains('cluster')),
        );
      },
    );

    test('THE INNOCENT NEIGHBOUR: a path only this run has written is not read as absent', () async {
      // What installation state looks like on the first run of a freshly cut branch: git has never
      // heard of the file, and add takes it anyway. Asking the index alone would refuse the whole
      // row at the one moment it matters most.
      final FakeShell shell = dirty()
        ..fails('git -C $repository ls-files --error-unmatch -- clusters')
        ..answers(
          'git -C $repository ls-files --others --exclude-standard -- clusters',
          'clusters/active/one.yaml\n',
        );

      expect(await commit.check(contextOn(shell: shell)), isA<Ready>());
    });

    test(
      'THE CASE THIS REFUSAL EXISTS FOR: a status git could not carry out is not "nothing differs"',
      () async {
        // The silent-success shape this whole step exists to prevent, one level in: a status that
        // FAILED read as an empty one makes the check answer satisfied, so the commit is never made
        // and the run reports success over a checkout nobody could look at.
        final FakeShell shell = checkout(head: branch)
          ..fails(
            'git -C $repository status --porcelain -- clusters configs',
            exitCode: 128,
            stderr: 'fatal: unable to read index',
          );

        expect(await commit.check(contextOn(shell: shell)), isA<Blocked>());
      },
    );

    test(
      'what this row names none of is written into the record, and does not fail the run',
      () async {
        // The whole-tree question, which is a DIFFERENT FakeShell key from the one dirty() arranges:
        // no `--` and no paths. That is what makes this measure what the row named none of rather
        // than what it named.
        final FakeShell shell = dirty()
          ..answers('git -C $repository status --porcelain', ' M installation/profile.yaml\n');
        final RecordingLog log = RecordingLog();

        await commit.apply(contextOn(shell: shell, log: log));

        expect(log.warnings.single, contains('installation/profile.yaml'));
      },
    );

    test(
      'THE INNOCENT NEIGHBOUR: a checkout carrying nothing else produces no such line',
      () async {
        final FakeShell shell = dirty()..answers('git -C $repository status --porcelain', '');
        final RecordingLog log = RecordingLog();

        await commit.apply(contextOn(shell: shell, log: log));

        expect(log.warnings, isEmpty);
      },
    );
  });

  group('proving it left the machine', () {
    FakeShell pushable({String? remoteAt}) {
      final FakeShell shell = checkout(head: branch)
        ..answers('git -C $repository rev-parse $branch', '$tip\n')
        ..answers('git -C $repository push $remote $branch', '');
      if (remoteAt == null) {
        shell.answers('git -C $repository ls-remote --heads $remote $branch', '');
      } else {
        shell.answers(
          'git -C $repository ls-remote --heads $remote $branch',
          '$remoteAt\trefs/heads/$branch\n',
        );
      }
      return shell;
    }

    test('a branch the remote does not carry has work to do', () async {
      expect(await push.check(contextOn(shell: pushable())), isA<Ready>());
    });

    test(
      'THE INNOCENT NEIGHBOUR: one it already carries at the same commit is satisfied',
      () async {
        expect(await push.check(contextOn(shell: pushable(remoteAt: tip))), isA<Satisfied>());
      },
    );

    test('THE CASE THIS STEP EXISTS FOR: git says 0 and the remote does not carry it', () async {
      // `git push` answers 0 for a push that had nothing to send, and that is the same answer as one
      // that delivered. A step trusting the exit code would be right almost always and silently
      // wrong on exactly the run whose work never left the machine.
      final FakeShell shell = pushable();

      expect(
        () => push.apply(contextOn(shell: shell)),
        throwsA(
          isA<CommandFailed>().having(
            (CommandFailed failed) => failed.message,
            'message',
            contains('on this machine and nowhere else'),
          ),
        ),
      );
    });

    test('the remote carrying ANOTHER commit is refused too, not read as arrival', () async {
      final FakeShell shell = pushable(remoteAt: 'deadbeef');

      expect(() => push.apply(contextOn(shell: shell)), throwsA(isA<CommandFailed>()));
    });

    test('and where it landed at the right commit, nothing is thrown', () async {
      await push.apply(contextOn(shell: pushable(remoteAt: tip)));
    });

    test('every command that reaches the remote refuses to be asked anything', () async {
      // There is no terminal on the other side of a run a client opened. A git that decides to ask
      // for a credential does not fail the push, it hangs it until the deadline — and a run that
      // hangs says nothing at all, where a refusal names what could not write.
      final FakeShell shell = pushable(remoteAt: tip);
      await push.apply(contextOn(shell: shell));

      final Iterable<Command> reaching = shell.commands.where(
        (Command each) => each.arguments.contains('push') || each.arguments.contains('ls-remote'),
      );
      expect(reaching, isNotEmpty);
      for (final Command each in reaching) {
        expect(
          each.environment['GIT_TERMINAL_PROMPT'],
          '0',
          reason: '${each.argv.join(' ')} would stop and ask',
        );
        expect(each.environment['GIT_SSH_COMMAND'], contains('BatchMode=yes'));
      }
    });
  });
}
