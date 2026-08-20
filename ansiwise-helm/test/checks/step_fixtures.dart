/// A fake machine arranged for one step, so its second run can be measured at all.
///
/// The idempotence audit runs every registered step twice against a fake machine. On a BLANK fake
/// most steps cannot be measured: `FakeShell` records a command and does not carry it out, so a step
/// whose postcondition a real helm call would leave behind never sees it become true. Those come
/// back NOT COVERED, and the audit names them rather than counting them as passing — which is the
/// whole point, because a step counted as passing on a fake that could not exercise it is the
/// failure the audit exists to prevent.
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

/// What the audit passes for a text argument with no default.
///
/// A fixture answers for the values the audit actually hands the step, not for the values a program
/// file would. It is read from the package that hands them over rather than restated here, because a
/// fixture and the prober disagreeing about this one character is a fixture arranging the wrong
/// command line and a step coming back not covered for no visible reason.
const String _plausibleText = plausibleText;

/// The fake machine each named step meets, by the name a program file writes.
final Map<String, Fixture> stepFixtures = <String, Fixture>{
  // helm holds no repository under this name until the add, and holds it at the wanted address
  // afterwards — which is what the step's check reads back out of `helm repo list`, rather than out
  // of the add having returned zero.
  'helm_repository': (FakeShell shell, FakeFiles files, FakeHttp http) {
    const String list = 'helm repo list -o json';
    shell.fails(list);
    shell.changes(
      'helm repo add $_plausibleText $_plausibleText --force-update',
      () => shell.answers(list, '[{"name": "$_plausibleText", "url": "$_plausibleText"}]'),
    );
  },

  // Three things have to be true at once for this step's check to answer satisfied, and the fake
  // has to produce all three: helm lists the release as deployed, the chart it lists is the pinned
  // one, and the values it holds are the values in the file the row named. An empty document is
  // what makes the last comparison a real one without a document of its own to keep in step.
  'helm_release': (FakeShell shell, FakeFiles files, FakeHttp http) {
    const String list = 'helm list --namespace $_plausibleText -o json';
    const String heldValues = 'helm get values $_plausibleText --namespace $_plausibleText -o json';
    const String upgrade =
        'helm upgrade --install $_plausibleText $_plausibleText --namespace $_plausibleText '
        '--version $_plausibleText --values $_plausibleText';
    files.contents[_plausibleText] = '{}\n';
    shell.fails(list);
    // The report helm writes after an install, because the step reads it: a fake that answered an
    // empty exit 0 would exercise the branch for an upgrade that said nothing, which is the case
    // this fixture is not about.
    shell.answers(
      upgrade,
      'NAME: $_plausibleText\nNAMESPACE: $_plausibleText\nSTATUS: deployed\nREVISION: 1\n',
    );
    shell.changes(upgrade, () {
      shell.answers(
        list,
        '[{"name": "$_plausibleText", "status": "deployed", '
        '"chart": "$_plausibleText-$_plausibleText"}]',
      );
      shell.answers(heldValues, '{}');
    });
  },
};
