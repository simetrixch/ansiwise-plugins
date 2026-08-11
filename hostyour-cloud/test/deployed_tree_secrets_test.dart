import 'dart:io';

import 'package:test/test.dart';

import 'composition.dart';

/// What the deployed tree may carry under `secrets/`, and what it may never carry.
///
/// **The rule this holds.** One file in that directory ships: the template, every value at a
/// placeholder, which the branch program fills in place on a machine. Everything else that appears
/// there is a FILLED copy — one installation's live credentials — and it must be impossible to
/// commit.
///
/// **Why it is measured and not trusted.** The two halves pull against each other. The directory was
/// excluded whole, which kept every filled copy out and also made the template impossible to ship, so
/// the branch program could never complete. Admitting the template means admitting the directory
/// first, because git does not descend into an excluded one — and an admitted directory is one
/// pattern away from carrying somebody's Vault token in a public-shaped repository.
///
/// **git decides, not a reading of the file.** These ask `git check-ignore`, which is the same
/// mechanism a commit consults. A test that parsed the ignore file itself would be a second
/// implementation of git's matching, and the interesting cases are exactly the ones where a second
/// implementation and git disagree.
void main() {
  test('the template is the one file under secrets/ that git will carry', () {
    expect(
      _ignoredByRules('secrets/secrets.example'),
      isFalse,
      reason:
          'the branch program reads this template off the checkout and answers Blocked without it, '
          'so a template git refuses to carry is a deployment that cannot complete',
    );
  });

  test('every filled copy stays out, whatever it is called', () {
    for (final String path in <String>[
      // One per stage, which is what an installation actually produces.
      'secrets/secrets.dev',
      'secrets/secrets.test',
      'secrets/secrets.prod',
      // The file the secret store's own quorum is written to, which is the one nothing else holds.
      'secrets/vault-prod.txt',
      // A name nobody has thought of yet. The rule may not be a list of the names we happened to
      // predict — the next filled file will have a name this test could not have known.
      'secrets/whatever-somebody-writes-next',
      // The same directory name elsewhere in the tree: the original rule was deliberately broad and
      // narrowing it to the root would have admitted these.
      'apps/manager/secrets',
      'charts/common/secrets/anything',
    ]) {
      expect(
        _ignoredByRules(path),
        isTrue,
        reason:
            '$path holds one installation\'s live credentials, and this repository is cloned by '
            'anybody. A filled copy that git can see is a credential one command away from being '
            'published, and nothing afterwards takes it back',
      );
    }
  });

  test('every value in the shipped template is empty', () {
    final List<String> filled = <String>[
      for (final String raw in File('$deployedRoot/secrets/secrets.example').readAsLinesSync())
        if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=.').hasMatch(raw)) raw,
    ];
    expect(
      filled,
      isEmpty,
      reason:
          'a value still equal to the template counts as NO answer at all, so a plausible-looking '
          'one is read as an answer nobody gave — the mistake that once put certificate mail on a '
          'mailbox nobody reads',
    );
  });
}

/// Whether the ignore RULES of the deployed tree exclude [path], asked of git itself.
///
/// The path need not exist: this is a question about the rules, and the filled copies deliberately do
/// not exist in a checkout.
///
/// **`--no-index` is what makes this a check rather than a tautology, and leaving it off was a real
/// mistake here.** Without it git answers about the INDEX as well, and a tracked path is never
/// reported as ignored whatever the rules say. The template is tracked, so the question "is the
/// template carried" came back yes with the rule that carries it deleted — the check could not fail,
/// and a check that cannot fail reads exactly like one that passed.
bool _ignoredByRules(String path) =>
    Process.runSync('git', <String>[
      '-C',
      deployedRoot,
      'check-ignore',
      '--no-index',
      '-q',
      path,
    ]).exitCode ==
    0;
