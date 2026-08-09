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
import 'package:hostyour_cloud/hostyour_cloud.dart';

/// Arranges [FakeShell], [FakeFiles] and [FakeHttp] for one step.
typedef Fixture = void Function(FakeShell shell, FakeFiles files, FakeHttp http);

/// What the check passes for a text argument with no default.
///
/// A fixture answers for the values the check actually hands the step, not for the values a program
/// file would. Reading it from one place here is what stops the two drifting apart.
const String _plausibleText = 'x';

/// The home directory the passwd entry in these fixtures reports.
const String _home = '/home/$_plausibleText';

/// What `plausibleArguments` hands `install_packages` for its `packages` list.
///
/// The fixture has to answer for exactly those, so it reads the same source rather than a second copy
/// that could drift.
const List<String> _plausiblePackages = <String>[_plausibleText];

/// The fake machine each named step meets, by the name a program file writes.
final Map<String, Fixture> stepFixtures = <String, Fixture>{
  // The manifest has to be in the checkout at all, or the check is blocked before it asks anything.
  // `kubectl diff` then reports a difference until the apply, and none afterwards — which is the
  // postcondition, answered by the API server rather than by a comparison of our own.
  'kubernetes_object': (FakeShell shell, FakeFiles files, FakeHttp http) {
    const String file = '$_plausibleText/$_plausibleText';
    files.contents[file] = 'kind: Namespace\n';
    shell.fails('kubectl diff --filename $file');
    shell.changes(
      'kubectl apply --filename $file',
      () => shell.answers('kubectl diff --filename $file', ''),
    );
  },

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

  // dpkg answers "not installed" until apt has run, and "installed" afterwards — which is what the
  // step's postcondition reads, and what a fake that only records commands can never show.
  'install_packages': (FakeShell shell, FakeFiles files, FakeHttp http) {
    for (final String package in _plausiblePackages) {
      shell.fails('dpkg-query -W -f=\${Status} $package');
    }
    shell.changes('apt-get update', () {});
    shell.changes('apt-get install --yes ${_plausiblePackages.join(' ')}', () {
      for (final String package in _plausiblePackages) {
        shell.answers('dpkg-query -W -f=\${Status} $package', 'install ok installed');
      }
    });
  },

  // The archive holds two files until `apt-get clean` empties it.
  'clean_package_cache': (FakeShell shell, FakeFiles files, FakeHttp http) {
    files.contents['${CleanPackageCache.archives}/one.deb'] = '';
    files.contents['${CleanPackageCache.archives}/two.deb'] = '';
    shell.changes('apt-get clean', () {
      files.contents.remove('${CleanPackageCache.archives}/one.deb');
      files.contents.remove('${CleanPackageCache.archives}/two.deb');
    });
  },

  // apt says it would remove one package until it has.
  'remove_unused_packages': (FakeShell shell, FakeFiles files, FakeHttp http) {
    shell.answers('apt-get --dry-run autoremove', 'Remv oldpackage [1.0]\n');
    shell.changes('apt-get autoremove --yes', () {
      shell.answers('apt-get --dry-run autoremove', '\n');
    });
  },

  // sshd keeps answering `yes` until the reload, which is exactly the silent failure the step is
  // built around — a drop-in nothing reads leaves the password working.
  'disable_password_login': (FakeShell shell, FakeFiles files, FakeHttp http) {
    shell.answers(
      'sshd -T',
      'port 22\npasswordauthentication yes\nkbdinteractiveauthentication yes\n',
    );
    shell.changes('systemctl reload ssh', () {
      shell.answers(
        'sshd -T',
        'port 22\npasswordauthentication no\nkbdinteractiveauthentication no\n',
      );
    });
  },

  // The account has to exist before a key can be put in its home, and the home comes from the passwd
  // entry rather than from `~` — which is something a shell expands and nothing here goes through a
  // shell.
  'install_authorized_key': (FakeShell shell, FakeFiles files, FakeHttp http) {
    shell.answers(
      'getent passwd $_plausibleText',
      '$_plausibleText:x:1000:1000::$_home:/bin/bash\n',
    );
    shell.answers('chown $_plausibleText:$_plausibleText $_home/.ssh', '');
    shell.answers('chown $_plausibleText:$_plausibleText $_home/.ssh/authorized_keys', '');
  },

  // The gate reads sshd's own resolved configuration and the modes of three paths — the file, its
  // directory and the home. sshd refuses any of them being too open and says nothing about why.
  'require_key_login_possible': (FakeShell shell, FakeFiles files, FakeHttp http) {
    shell.answers('sshd -T', 'port 22\npubkeyauthentication yes\n');
    shell.answers(
      'getent passwd $_plausibleText',
      '$_plausibleText:x:1000:1000::$_home:/bin/bash\n',
    );
    shell.answers('stat -c %a $_home', '755\n');
    shell.answers('stat -c %a $_home/.ssh', '700\n');
    shell.answers('stat -c %a $_home/.ssh/authorized_keys', '600\n');
    files.contents['$_home/.ssh/authorized_keys'] = '$_plausibleText\n';
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
      'BUILD_PLANE=""',
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
