import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Putting one tag on one commit, and the two ways that goes wrong quietly.
///
/// A tag is what everything downstream regenerates from, so the two failures worth guarding are the
/// ones nothing reports: a tag silently MOVED to another commit, which leaves every statement made
/// about it standing while the tree it names has changed, and a tag that exists in one checkout and
/// nowhere else, which is a statement nothing can resolve.
void main() {
  const String tag = '1.2.3-alpha-20260824120000';
  const String tip = 'a1b2c3d4e5f6';
  const String other = '9876543210ab';

  const GitTag step = GitTag(
    repository: repository,
    tag: tag,
    ref: base,
    message: 'what this run released',
  );

  /// A checkout that answers the way a healthy one does, with the tag wherever the case puts it.
  FakeShell tagging({String? here, String? onRemote, String at = tip}) {
    final FakeShell shell = FakeShell()
      ..answers('git check-ref-format refs/tags/$tag', '')
      ..answers('git -C $repository rev-parse --quiet --verify $base^{commit}', '$at\n');
    if (here == null) {
      shell.fails('git -C $repository rev-parse --quiet --verify refs/tags/$tag^{commit}');
    } else {
      shell.answers(
        'git -C $repository rev-parse --quiet --verify refs/tags/$tag^{commit}',
        '$here\n',
      );
    }
    // WHAT THE REAL COMMAND ANSWERS, and the arrangement here is what lets a real defect through or
    // catches it. An annotated tag is an object of its own, and a remote answers with BOTH its id
    // and the commit it dereferences to — but only where the pattern matches the peeled ref too.
    // Asked for the exact name it answers with the object id alone, and a step reading that
    // compares a tag object against a commit and reports a tag that has moved. A fixture supplying
    // both lines for the exact pattern, which no remote does, lets the step pass here and fail on
    // the first real tag it cuts.
    shell.answers(
      'git -C $repository ls-remote --tags $remote refs/tags/$tag*',
      onRemote == null ? '' : 'ffffffffffff\trefs/tags/$tag\n$onRemote\trefs/tags/$tag^{}\n',
    );
    return shell;
  }

  test('a tag on neither side is made and pushed, and the second run asks for nothing', () async {
    final FakeShell shell = tagging()
      ..changes(
        'git -C $repository tag --annotate $tag --message what this run released $base',
        () {
          // The machine after the tag: it stands here now, and the remote still has none.
        },
      );

    expect(await step.check(contextOn(shell: shell)), isA<Ready>());
    await step.apply(contextOn(shell: shell));

    expect(
      shell.ran,
      containsAllInOrder(<String>[
        'git -C $repository tag --annotate $tag --message what this run released $base',
        'git -C $repository push $remote refs/tags/$tag',
      ]),
      reason: 'the tag is made before it is pushed, which is the only order that means anything',
    );

    // THE POSTCONDITION IS ASKED OF THE MACHINE the act left behind, not of the fact that two
    // commands returned zero.
    final FakeShell after = tagging(here: tip, onRemote: tip);
    expect(await step.check(contextOn(shell: after)), isA<Satisfied>());
  });

  test(
    'THE INNOCENT NEIGHBOUR: a tag on both sides at the same commit is already satisfied',
    () async {
      // Without it a step that always reported work would pass the case above and re-push on every
      // run, which a remote accepts silently.
      final CheckResult answer = await step.check(
        contextOn(
          shell: tagging(here: tip, onRemote: tip),
        ),
      );

      expect(answer, isA<Satisfied>());
      expect((answer as Satisfied).because, contains(tip));
    },
  );

  test('a tag standing on another commit here is refused, never moved', () async {
    final CheckResult answer = await step.check(
      contextOn(
        shell: tagging(here: other, onRemote: other),
      ),
    );

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains(other));
    expect(answer.reason, contains('moves'));
  });

  test('a tag moved here while the remote knows none is refused by the LOCAL side', () async {
    // The case that separates the two refusals. With the remote carrying nothing, only the local
    // comparison can catch it — and without that comparison this run would push a tag pointing at a
    // tree nobody released under that name.
    final CheckResult answer = await step.check(contextOn(shell: tagging(here: other)));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('in this checkout'));
  });

  test('a LIGHTWEIGHT tag on the remote is read from its only line', () async {
    // The other half the pattern has to cover: such a tag has no dereferenced line anywhere, and
    // there the one id IS the commit. A step that only ever read the peeled line would report every
    // lightweight tag as absent and try to make it again.
    final FakeShell shell = tagging()
      ..answers(
        'git -C $repository ls-remote --tags $remote refs/tags/$tag*',
        '$tip\trefs/tags/$tag\n',
      );

    final CheckResult answer = await step.check(contextOn(shell: shell));

    expect(
      answer,
      isA<Ready>(),
      reason:
          'the remote has it on the right commit and this checkout has none, so only the push is '
          'left',
    );
  });

  test('a tag the REMOTE already carries on another commit is refused too', () async {
    // The worse half of the same shape: something has already resolved that tag, so moving it would
    // change what was released under a name that has been handed out.
    final CheckResult answer = await step.check(contextOn(shell: tagging(onRemote: other)));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('already resolved'));
  });

  test('a tag made here by a run that never finished is pushed rather than remade', () async {
    // The interrupted run. A step that only pushed what it had just created would leave that tag
    // local for ever, and every later run would report it finished because the name is taken.
    final FakeShell shell = tagging(here: tip);

    expect(await step.check(contextOn(shell: shell)), isA<Ready>());
    await step.apply(contextOn(shell: shell));

    expect(shell.ran, contains('git -C $repository push $remote refs/tags/$tag'));
    expect(
      shell.ran.where((String c) => c.contains('tag --annotate')),
      isEmpty,
      reason: 'the tag was already there, and remaking it is what git refuses anyway',
    );
  });

  test('a name git will not take is refused in git\'s own words', () async {
    const GitTag bad = GitTag(repository: repository, tag: 'not a tag', ref: base, message: 'm');
    final FakeShell shell = FakeShell()..fails('git check-ref-format refs/tags/not a tag');

    final CheckResult answer = await bad.check(contextOn(shell: shell));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('not a tag'));
  });

  test('a row that got no tag from the row before it is refused', () async {
    // The row takes the tag from a measurement, so it is READ as optional and the demand lives
    // here. A step built without one would otherwise put a tag called "" on a commit.
    const GitTag empty = GitTag(repository: repository, tag: '', ref: base, message: 'm');

    final CheckResult answer = await empty.check(contextOn(shell: tagging()));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('states no tag'));
  });

  group('where the checkout is named', () {
    // ONE ROW POINTS AT ONE CHECKOUT. A row stating both sources is not a preference to resolve
    // silently — it is two statements, and picking one of them makes the other a lie nobody sees.
    test('a row naming both the path and an answer is refused', () async {
      const GitTag both = GitTag(
        repository: repository,
        repositoryAnswer: 'platform_checkout',
        tag: tag,
        ref: base,
        message: 'm',
      );

      final CheckResult answer = await both.check(contextOn(shell: tagging()));

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('one row points at one checkout'));
    });

    test('a row naming neither is refused', () async {
      const GitTag none = GitTag(tag: tag, ref: base, message: 'm');

      final CheckResult answer = await none.check(contextOn(shell: tagging()));

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('states no checkout'));
    });

    test("a run holding no such answer is refused by that answer's name", () async {
      const GitTag named = GitTag(
        repositoryAnswer: 'platform_checkout',
        tag: tag,
        ref: base,
        message: 'm',
      );

      final CheckResult answer = await named.check(contextOn(shell: tagging(), name: null));

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('platform_checkout'));
    });

    test('THE ANSWER FORM REACHES THE SAME CHECKOUT as the written one', () async {
      // The innocent case: without it, a step that refused every answered path would satisfy the
      // three refusals above and never work at all.
      const GitTag named = GitTag(
        repositoryAnswer: 'platform_checkout',
        tag: tag,
        ref: base,
        message: 'what this run released',
      );

      final CheckResult answer = await named.check(
        contextOn(
          shell: tagging(here: tip, onRemote: tip),
          name: repository,
          answerName: 'platform_checkout',
        ),
      );

      expect(answer, isA<Satisfied>());
    });
  });

  group('undoing', () {
    test('a tag this run made is taken back off both sides', () async {
      final bool before = await step.capture(contextOn(shell: tagging()));
      expect(before, isFalse);

      final FakeShell shell = tagging(here: tip, onRemote: tip);
      await step.undo(contextOn(shell: shell), before);

      expect(shell.ran, contains('git -C $repository push --delete $remote $tag'));
      expect(shell.ran, contains('git -C $repository tag --delete $tag'));
    });

    test('a tag that was already there is left exactly alone', () async {
      // Something may already have resolved it, and taking it away would break whatever did.
      final FakeShell shell = tagging(here: tip, onRemote: tip);
      final bool before = await step.capture(contextOn(shell: shell));
      expect(before, isTrue);

      final FakeShell undoing = tagging(here: tip, onRemote: tip);
      await step.undo(contextOn(shell: undoing), before);

      expect(undoing.ran.where((String c) => c.contains('delete')), isEmpty);
    });
  });
}
