/// A fake machine arranged for one step, so its second run can be measured at all.
///
/// The idempotence audit runs every registered step twice against a fake machine. On a BLANK fake
/// most steps cannot be measured: `FakeShell` records a command and does not carry it out, so a step
/// whose postcondition a real kubectl call would leave behind never sees it become true, and a step
/// whose precondition is a manifest in a checkout is blocked before it starts. Those come back NOT
/// COVERED, and the audit names them rather than counting them as passing — which is the whole
/// point, because a step counted as passing on a fake that could not exercise it is the failure the
/// audit exists to prevent.
///
/// What is here closes that for the steps it names. A fixture arranges the fake the way the real
/// machine would be arranged: `FakeShell.changes` makes a command alter the rest of the fake exactly
/// as the real one alters a machine, which is what lets a postcondition actually become true.
///
/// **A step with no fixture is still reported NOT COVERED, and that is deliberate.** Adding a step
/// tomorrow either brings its fixture or is named in the ledger the audit asserts against. Nothing
/// here may make a step look covered that was not.
library;

import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';

/// What the audit passes for a text argument with no default.
///
/// A fixture answers for the values the audit actually hands the step, not for the values a program
/// file would. It is read from the package that hands them over rather than restated here, because a
/// fixture and the prober disagreeing about this one character is a fixture arranging the wrong file
/// and a step coming back not covered for no visible reason.
const String _plausibleText = plausibleText;

/// How the client is invoked in these fixtures.
///
/// The audit hands each step the DEFAULT of the invocation argument, which is the one word kubectl
/// defines for itself. Read off the composer rather than written out, so a fixture cannot come to
/// expect a command line the audit never produces.
final String _client = const Kubectl().argv(const <String>[]).join(' ');

/// The fake machine each named step meets, by the name a program file writes.
final Map<String, Fixture> stepFixtures = <String, Fixture>{
  // The manifest has to be in the checkout at all, or the check is blocked before it asks anything.
  // `kubectl diff` then reports a difference until the apply, and none afterwards — which is the
  // postcondition, answered by the API server rather than by a comparison of our own.
  'kubernetes_object': (FakeShell shell, FakeFiles files, FakeHttp http) {
    const String file = '$_plausibleText/$_plausibleText';
    files.contents[file] = 'kind: Namespace\n';
    // The audit hands the OPTIONAL ownership label its placeholder for key and value alike, so the
    // guard runs: the live object carries that label, which is the innocent case.
    shell.answers(
      '$_client get --filename $file -o json',
      '{"kind":"Namespace","metadata":{"name":"$_plausibleText",'
          '"labels":{"$_plausibleText":"$_plausibleText"}}}',
    );
    shell.fails('$_client diff --filename $file');
    shell.changes(
      '$_client apply --filename $file',
      () => shell.answers('$_client diff --filename $file', ''),
    );
  },

  // The live object carries the ownership label, so the guard admits it; the delete flips the
  // cluster's answer to "none of these objects", which is the state the second check reads.
  'remove_kubernetes_object': (FakeShell shell, FakeFiles files, FakeHttp http) {
    const String file = '$_plausibleText/$_plausibleText';
    files.contents[file] = 'kind: Namespace\n';
    shell.answers(
      '$_client get --filename $file -o json',
      '{"kind":"Namespace","metadata":{"name":"$_plausibleText",'
          '"labels":{"$_plausibleText":"$_plausibleText"}}}',
    );
    shell.changes(
      '$_client delete --filename $file --ignore-not-found',
      () => shell.fails('$_client get --filename $file -o json'),
    );
  },
  // The same arrangement as the reversible sibling, plus the client timeout this step carries. The
  // apply is therefore a different command line, so the sibling's fixture would leave this one
  // recording a command the fake never carried out — which the audit reports as not covered.
  'kubernetes_object_irreversible': (FakeShell shell, FakeFiles files, FakeHttp http) {
    const String file = '$_plausibleText/$_plausibleText';
    final String apply =
        '$_client apply --filename $file '
        '--request-timeout=${KubernetesObjectIrreversible.requestTimeout.inSeconds}s';
    files.contents[file] = 'kind: Namespace\n';
    shell.fails('$_client diff --filename $file');
    shell.changes(apply, () => shell.answers('$_client diff --filename $file', ''));
  },
};
