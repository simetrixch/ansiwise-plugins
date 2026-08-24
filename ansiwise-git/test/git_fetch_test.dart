import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Bringing one ref into a checkout, and the two silences this ends.
///
/// A checkout resolves a remote name to whatever it last saw, and a tag it never fetched to nothing
/// at all. Neither says so: one puts a release on a tree nobody published, the other refuses with a
/// message about a name. What is compared here is therefore what the REMOTE publishes, never when a
/// fetch last happened.
void main() {
  const String tag = '1.2.3-alpha-20260824120000';
  const String tip = 'a1b2c3d4e5f6';
  const String older = '9876543210ab';

  const GitFetch fetchingBranch = GitFetch(repository: repository, remote: remote, branch: base);
  const GitFetch fetchingTag = GitFetch(repository: repository, remote: remote, tag: tag);

  FakeShell remoteHas({String? branchAt = tip, String? tagAt, String? here}) {
    final FakeShell shell = FakeShell()
      ..answers(
        'git -C $repository ls-remote $remote refs/heads/$base',
        branchAt == null ? '' : '$branchAt\trefs/heads/$base\n',
      )
      ..answers(
        'git -C $repository ls-remote $remote refs/tags/$tag*',
        tagAt == null ? '' : 'ffffffffffff\trefs/tags/$tag\n$tagAt\trefs/tags/$tag^{}\n',
      );
    for (final String what in <String>['refs/remotes/$remote/$base', 'refs/tags/$tag']) {
      if (here == null) {
        shell.fails('git -C $repository rev-parse --quiet --verify $what^{commit}');
      } else {
        shell.answers('git -C $repository rev-parse --quiet --verify $what^{commit}', '$here\n');
      }
    }
    return shell;
  }

  test('a checkout behind what the remote publishes has work to do, and names it', () async {
    final FakeShell shell = remoteHas(here: older);

    expect(await fetchingBranch.check(contextOn(shell: shell)), isA<Ready>());

    await fetchingBranch.apply(contextOn(shell: shell));
    expect(
      shell.ran,
      contains('git -C $repository fetch $remote +refs/heads/$base:refs/remotes/$remote/$base'),
      reason:
          'the destination is named outright, because a remote added by hand maps nothing and '
          'the fetch would then update a name no later row reads',
    );
  });

  test('THE INNOCENT NEIGHBOUR: a checkout already level asks for nothing', () async {
    // Without it, a step that always fetched would pass the case above and reach the network on
    // every run of every program that carries this row.
    final CheckResult answer = await fetchingBranch.check(contextOn(shell: remoteHas(here: tip)));

    expect(answer, isA<Satisfied>());
    expect((answer as Satisfied).because, contains(tip));
  });

  test('a tag this checkout has never seen is work to do', () async {
    // The second silence: a merge against such a name refuses with a message about the name, and
    // the checkout was simply behind.
    final FakeShell shell = remoteHas(tagAt: tip);

    expect(await fetchingTag.check(contextOn(shell: shell)), isA<Ready>());
    await fetchingTag.apply(contextOn(shell: shell));
    expect(shell.ran, contains('git -C $repository fetch $remote tag $tag'));
  });

  test('a tag already here on what the remote publishes asks for nothing', () async {
    final CheckResult answer = await fetchingTag.check(
      contextOn(
        shell: remoteHas(tagAt: tip, here: tip),
      ),
    );

    expect(answer, isA<Satisfied>());
  });

  test('a name the remote does not publish is refused, and never fetched', () async {
    // Fetching would answer nothing and leave the check to report a difference for ever. The name
    // is wrong, or whatever writes it has not run, and both are things to say rather than retry.
    final FakeShell shell = remoteHas(branchAt: null);

    final CheckResult answer = await fetchingBranch.check(contextOn(shell: shell));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains(base));
    expect(shell.ran.where((String c) => c.contains('fetch')), isEmpty);
  });

  test('a row naming a branch AND a tag is refused, because they are two statements', () async {
    const GitFetch both = GitFetch(repository: repository, remote: remote, branch: base, tag: tag);

    final CheckResult answer = await both.check(contextOn(shell: remoteHas()));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('two rows'));
  });

  test('a row naming neither is refused, and says where a name would come from', () async {
    const GitFetch neither = GitFetch(repository: repository, remote: remote);

    final CheckResult answer = await neither.check(contextOn(shell: remoteHas()));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('measurement'));
  });
}
