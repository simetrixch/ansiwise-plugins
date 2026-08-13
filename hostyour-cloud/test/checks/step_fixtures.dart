/// A fake machine arranged for one step, so its second run can be measured at all.
///
/// The idempotence check runs every registered step twice against a fake machine. On a BLANK fake
/// most steps cannot be measured: `FakeShell` records a command and does not carry it out, so a step
/// whose postcondition is left behind by a command never sees it become true, and a step whose
/// precondition is an account or a checkout is blocked before it starts. Those come back NOT COVERED,
/// and the check names them rather than counting them as passing — which is the whole point, because
/// a step counted as passing on a fake that could not exercise it is the failure the check exists to
/// prevent.
///
/// What is here closes that for the steps it names. A fixture arranges the fake the way the real
/// machine would be arranged: `FakeShell.changes` makes a command alter the rest of the fake exactly
/// as the real one alters a machine, which is what lets a postcondition actually become true.
///
/// **A step with no fixture is still reported NOT COVERED, and that is deliberate.** Adding a step
/// tomorrow either brings its fixture or is named in the ledger the check asserts against. Nothing
/// here may make a step look covered that was not.
library;

import 'package:ansiwise_api/testing.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';

/// What the check passes for a text argument with no default.
///
/// A fixture answers for the values the check actually hands the step, not for the values a program
/// file would. It is read from the package that hands them over rather than restated here, because a
/// fixture and the prober disagreeing about this one character is a fixture arranging the wrong file
/// and a step coming back not covered for no visible reason.
const String _plausibleText = plausibleText;

/// The fake machine each named step meets, by the name a program file writes.
final Map<String, Fixture> stepFixtures = <String, Fixture>{
  // The nine toggles this step decides, as a branch carries them. Without them its check is BLOCKED
  // before it starts — the ApplicationSet matches on these files, so a tree without one is a tree
  // where that application reaches no cluster, and the step says so rather than writing around it.
  'stamp_app_toggles': (FakeShell shell, FakeFiles files, FakeHttp http) {
    for (final String app in <String>[
      ...StampAppToggles.onTheBuildPlane,
      ...StampAppToggles.whereTheMasterIs,
      ...StampAppToggles.whereTheMasterIsNot,
    ]) {
      files.contents['$_plausibleText/cluster/apps/$app.yaml'] =
          '# What this application is, and when it belongs on a cluster.\n'
          'name: $app\n'
          'deploy: "false"\n';
    }
  },


};

/// [lines] as the text of a file, ending in a newline the way every file these steps read does.
String _lines(List<String> lines) => '${lines.join('\n')}\n';
