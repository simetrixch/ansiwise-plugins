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

  // Both writers fill a template in place, so without the template on the machine they have nothing
  // to fill and refuse. The template is what a branch cut from the trunk carries, which is the
  // machine these two really meet.
  //
  // Every placeholder here differs from what the check answers, so every key counts as unset and is
  // filled — which is what lets the second check see the step from having work to having none.
  'write_stage_config': (FakeShell shell, FakeFiles files, FakeHttp http) {
    files.contents['$_plausibleText/configs/config.example'] = _lines(<String>[
      'LETSENCRYPT_EMAIL="user@example.com"',
      'IDP_BOOTSTRAP_EMAIL="user@example.com"',
      'ALERT_RECIPIENTS=""',
      'UNIT_APEX=""',
      'PLATFORM_DOMAIN=""',
      'BUILD_PLANE_FQDN=""',
      'CATALOG_REPO=""',
      'CLUSTER_NAME="my-cluster"',
      'DOMAIN_SUFFIX="example.com"',
      'DEPLOY_ENV="prod"',
      '# A platform default nobody is asked for.',
      'POD_CIDR="10.244.0.0/16"',
    ]);
  },

  'write_stage_secrets': (FakeShell shell, FakeFiles files, FakeHttp http) {
    files.contents['$_plausibleText/secrets/secrets.example'] = _lines(<String>[
      'GITOPS_REPO_PAT=""',
      'GITOPS_REPO_READ_PAT=""',
      'CLOUDFLARE_API_TOKEN=""',
      'STORAGE_BOX_HOST=""',
      'STORAGE_BOX_USER=""',
      'STORAGE_BOX_PASSWORD=""',
      'REGISTRY_DOCKERHUB_USER=""',
      'REGISTRY_DOCKERHUB_TOKEN=""',
      'BUILD_HOSTYOUR_CLOUD_REPO_PAT=""',
      'BUILD_CATALOG_REPO_PAT=""',
      '# Written back once this installation is running.',
      'VAULT_ROOT_TOKEN=""',
    ]);
  },
};

/// [lines] as the text of a file, ending in a newline the way every file these steps read does.
String _lines(List<String> lines) => '${lines.join('\n')}\n';
