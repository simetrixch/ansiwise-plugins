import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The two shapes a pinned release arrives in, each written the way a program row writes it.
///
/// One step covers both, so what separates them is only their arguments — which is the claim these
/// tests are here to hold. A release that IS the binary is fetched straight to where it goes; one
/// that arrives packed is unpacked out of an archive, and its project spells the version without
/// the shape its tag carries, which is what the second slot in a url is for.
const InstallPinnedTool vaultCli = InstallPinnedTool(
  tool: 'vault',
  version: 'v2.0.3',
  url:
      'https://releases.hashicorp.com/vault/${InstallPinnedTool.bareVersionPlaceholder}/'
      'vault_${InstallPinnedTool.bareVersionPlaceholder}_linux_amd64.zip',
  directory: InstallPinnedTool.defaultDirectory,
  archive: '/tmp/vault.zip',
  versionCommand: <String>['version'],
);

const InstallPinnedTool yqCli = InstallPinnedTool(
  tool: 'yq',
  version: 'v4.53.3',
  url:
      'https://github.com/mikefarah/yq/releases/download/'
      '${InstallPinnedTool.versionPlaceholder}/yq_linux_amd64',
  directory: InstallPinnedTool.defaultDirectory,
  archive: null,
  versionCommand: <String>['--version'],
);

/// The tools an operator uses on the machine, and the pins that make two machines the same.
void main() {
  const StepName under = StepName('under_test');

  group('the two things every tool download needs', () {
    const EnsureToolPrerequisites step = EnsureToolPrerequisites(
      packages: <String>['curl', 'unzip'],
    );

    test('the verdict comes from the commands, never from the package manager', () async {
      // Automatic updates hold the package lock for minutes after a machine boots, so an install
      // exits with a failure on a freshly provisioned machine that already carries both.
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers('command -v curl', '/usr/bin/curl\n')
        ..answers('command -v unzip', '/usr/bin/unzip\n')
        ..fails('apt-get install --yes', exitCode: 100, stderr: 'could not get lock');

      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a machine missing one of them installs it and is judged again on the command', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers('command -v curl', '/usr/bin/curl\n')
        ..fails('command -v unzip')
        ..fails('apt-get install --yes unzip', exitCode: 100, stderr: 'could not get lock')
        ..changes('apt-get install --yes unzip', () {
          machine.shell.answers('command -v unzip', '/usr/bin/unzip\n');
        });

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(
        await step.check(context),
        isA<Satisfied>(),
        reason: 'the package manager reported a failure and the command is there',
      );
    });

    test('one gate up front rather than three failures further down', () async {
      final HostMachine machine = HostMachine()
        ..shell.fails('command -v curl')
        ..shell.fails('command -v unzip');
      final StepPlan plan = await step.plan(machine.contextFor(under));
      expect(plan.summary, contains('curl'));
      expect(plan.summary, contains('unzip'));
    });
  });

  group('the skip predicate, which differs by where a tool comes from', () {
    test('a tool fetched at a pinned release skips on the version and not on being there', () async {
      // A binary that was on the machine before this platform existed would otherwise be left where
      // it is, held against the pin, and reported as wrong on every run with nothing able to fix it.
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers('command -v yq', '/usr/local/bin/yq\n')
        ..answers('yq --version', 'yq (https://github.com/mikefarah/yq/) version v4.40.0\n');

      expect(
        await yqCli.check(machine.contextFor(under)),
        isA<Ready>(),
        reason: 'an ordinary re-run corrects a machine that drifted, with nothing forced',
      );
    });

    test('a tool already at the pin is left alone', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers('command -v yq', '/usr/local/bin/yq\n')
        ..answers('yq --version', 'yq (https://github.com/mikefarah/yq/) version v4.53.3\n');

      expect(await yqCli.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a tool from the package manager skips on being there, taking no version', () async {
      // The other half of the pair, and the reason the pins call this one unpinnable: nothing here
      // names a version, because the package manager carries exactly one and no run could reach
      // another.
      final HostMachine machine = HostMachine()
        ..shell.answers(r'dpkg-query -W -f=${Status} jq', 'install ok installed');
      const InstallPackages step = InstallPackages(<String>['jq']);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a pin nobody wrote is refused rather than resolved to whatever is current', () async {
      final CheckResult answer = await InstallPinnedTool(
        tool: yqCli.tool,
        version: '',
        url: yqCli.url,
        directory: yqCli.directory,
        archive: null,
        versionCommand: yqCli.versionCommand,
      ).check(HostMachine().contextFor(under));
      expect((answer as Blocked).reason, contains('pinned release'));
    });

    test('a url carrying no slot for the pin is refused, because the two could disagree', () async {
      // The hole the shared step opens and the composed ones could not have: a url with the version
      // written into it would fetch one release while the pin claims another, and the fetch would
      // report success either way.
      final CheckResult answer = await const InstallPinnedTool(
        tool: 'yq',
        version: 'v4.53.3',
        url: 'https://github.com/mikefarah/yq/releases/download/v4.40.0/yq_linux_amd64',
        directory: InstallPinnedTool.defaultDirectory,
        archive: null,
        versionCommand: <String>['--version'],
      ).check(HostMachine().contextFor(under));
      expect((answer as Blocked).reason, contains(InstallPinnedTool.versionPlaceholder));
    });

    test(
      'a url carrying a slot nothing fills is refused rather than fetched as it stands',
      () async {
        // The pin fills exactly two slots. A misspelled one passes the slot-for-the-pin gate as long
        // as a correct one is also there, and would otherwise reach curl inside the address.
        final CheckResult answer = await const InstallPinnedTool(
          tool: 'yq',
          version: 'v4.53.3',
          url:
              'https://github.com/mikefarah/yq/releases/download/'
              '${InstallPinnedTool.versionPlaceholder}/yq_<architekture>',
          directory: InstallPinnedTool.defaultDirectory,
          archive: null,
          versionCommand: <String>['--version'],
        ).check(HostMachine().contextFor(under));
        expect((answer as Blocked).reason, contains('<architekture>'));
      },
    );

    test(
      'a row that says nothing about asking the version is refused, not fetched every run',
      () async {
        // The skip is decided on the version, so a tool the row gave no way of asking would be
        // fetched again on every run and nothing would notice.
        final CheckResult answer = await const InstallPinnedTool(
          tool: 'helm',
          version: 'v4.2.3',
          url: 'https://example.com/helm/${InstallPinnedTool.versionPlaceholder}/helm',
          directory: InstallPinnedTool.defaultDirectory,
          archive: null,
          versionCommand: <String>[],
        ).check(HostMachine().contextFor(under));
        expect((answer as Blocked).reason, contains('what version it is'));
      },
    );

    test('the fetch names the pinned release and never a latest one', () {
      // The one download path that spells the version without the shape its tag carries, which is
      // what the second slot exists for — the pin is still written once, as v2.0.3.
      expect(vaultCli.fetchedFrom, contains('/vault/2.0.3/vault_2.0.3_linux_amd64.zip'));

      expect(yqCli.fetchedFrom, contains('/download/v4.53.3/'));
      expect(yqCli.fetchedFrom, isNot(contains('latest')));
    });

    test('a release that is the binary itself is fetched to where it goes and made runnable', () {
      expect(yqCli.archive, isNull);
      expect(yqCli.path, '${InstallPinnedTool.defaultDirectory}/yq');
    });

    test('the machine this step exists for is the one it cannot be taken back on', () async {
      // The drifted machine, which is the whole reason the skip is decided on the version: the
      // check finds 4.44.1 against a pin of 4.53.3, and the apply then writes the pin over it.
      // Nothing here holds the binary that machine came with.
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers('command -v yq', '/usr/local/bin/yq\n')
        ..answers('yq --version', 'yq (https://github.com/mikefarah/yq/) version v4.44.1\n');

      expect(await yqCli.check(machine.contextFor(under)), isA<Ready>());

      // Unwind records "taken back" whenever a reversible step's undo returns without throwing, so
      // the only way this step cannot say that about a binary it did not keep is to not be one.
      expect(yqCli, isNot(isA<ReversibleStep<Object?>>()));
      expect(yqCli, isA<IrreversibleStep>());
      expect(yqCli.irreversibleReason, contains('nothing on this machine keeping a copy'));

      // And it says it CONDITIONALLY, because this step also runs on a machine carrying no such
      // tool, where it creates the file and replaces nothing. The reason is read at the point of no
      // return before a run, so one asserting a loss that will not happen is a refusal an operator
      // weighs against a cost they do not have.
      expect(yqCli.irreversibleReason, contains('where something already stood there'));
    });

    test('what a packed release has to be is stated on the argument a row writes', () async {
      // The unpacking writes every file the archive holds into the directory and the step names
      // none of them, so the constraint has to reach whoever writes the row.
      final ArgumentSpec archive = InstallPinnedTool.arguments.firstWhere(
        (ArgumentSpec spec) => spec.name == 'archive',
      );
      expect(archive.describes, contains('exactly one file'));
      expect(vaultCli.irreversibleReason, contains('everything the archive holds is unpacked'));
    });

    test('the packed copy is removed whether the unpacking worked or not', () async {
      // A half-finished download left behind is what the next run would unpack.
      final HostMachine machine = HostMachine();
      machine.shell
        ..fails('command -v vault')
        ..fails('unzip -o -d ${vaultCli.directory} ${vaultCli.archive}');

      await expectLater(vaultCli.apply(machine.contextFor(under)), throwsA(isA<CommandFailed>()));
      expect(machine.files.deleted, contains(vaultCli.archive));
    });
  });

  group('the pins held against the machine', () {
    const AssertCliToolVersions step = AssertCliToolVersions(
      tools: <String>['vault=v2.0.3', 'yq=v4.53.3', 'jq=jq-1.8.2', 'tailscale=v1.98.10'],
      unpinnable: <String>['jq', 'tailscale'],
      versionCommands: <String>[
        'vault=version',
        'yq=--version',
        'jq=--version',
        'tailscale=version',
      ],
    );

    HostMachine withTools({Map<String, String> answers = const <String, String>{}}) {
      final HostMachine machine = HostMachine();
      for (final String tool in <String>['vault', 'yq', 'jq', 'tailscale']) {
        machine.shell.answers('command -v $tool', '/usr/local/bin/$tool\n');
      }
      machine.shell
        ..answers('vault version', 'Vault v2.0.3 (abcdef1), built 2026-01-01\n')
        ..answers('yq --version', 'yq (https://github.com/mikefarah/yq/) version v4.53.3\n')
        ..answers('jq --version', 'jq-1.8.2\n')
        ..answers('tailscale version', '1.98.10\n  tailscale commit: abcdef1\n');
      answers.forEach(machine.shell.answers);
      return machine;
    }

    test('the tag shapes come off before the comparison', () {
      expect(AssertCliToolVersions.bare('v4.53.3'), '4.53.3');
      expect(AssertCliToolVersions.bare('jq-1.8.2'), '1.8.2');
      expect(AssertCliToolVersions.bare('2.0.3'), '2.0.3');
    });

    test('a version reader answers with the bare version and nothing else', () async {
      // Two shapes, and neither is the bare number. One prints the version and then the commit it
      // was built from on the lines after it; the other prints a name in front of the version and
      // the build behind it on the one line.
      final HostMachine machine = withTools();
      expect(
        await AssertCliToolVersions.installedVersion(
          machine.contextFor(under),
          'tailscale',
          <String>['version'],
        ),
        '1.98.10',
      );
      expect(
        await AssertCliToolVersions.installedVersion(machine.contextFor(under), 'vault', <String>[
          'version',
        ]),
        '2.0.3',
      );
    });

    test('a machine at every pin passes', () async {
      expect(await step.check(withTools().contextFor(under)), isA<Satisfied>());
    });

    test('a tool that is missing fails, whether its version could be chosen or not', () async {
      final HostMachine machine = withTools();
      machine.shell
        ..fails('command -v jq')
        ..fails('command -v yq');

      final CheckResult answer = await step.check(machine.contextFor(under));
      final String reason = (answer as Blocked).reason;
      expect(reason, contains('jq is not on this machine'));
      expect(reason, contains('yq is not on this machine'));
    });

    test(
      'a version difference on a tool whose path takes no version is reported, not failed',
      () async {
        final HostMachine machine = withTools(
          answers: <String, String>{'jq --version': 'jq-1.7.1\n'},
        );
        expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
        expect(machine.said.join('\n'), contains('jq is at 1.7.1'));
        expect(machine.said.join('\n'), contains('no run can reach the pin'));
      },
    );

    test('a version difference on a tool fetched at a pin fails', () async {
      final HostMachine machine = withTools(
        answers: <String, String>{
          'yq --version': 'yq (https://github.com/mikefarah/yq/) version v4.40.0\n',
        },
      );
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('yq is at 4.40.0'));
    });

    test('a tool named here with nothing able to ask it its version is caught', () async {
      // The assertion is the only thing binding the list to the steps that install them: a tool
      // added to one and not the other would otherwise never be installed and nothing would say so.
      const AssertCliToolVersions unknown = AssertCliToolVersions(
        tools: <String>['helm=v4.2.3'],
        unpinnable: <String>[],
        versionCommands: <String>[],
      );
      final CheckResult answer = await unknown.check(withTools().contextFor(under));
      expect((answer as Blocked).reason, contains('helm'));
    });

    test('an entry that does not read as a tool and its arguments is no reader at all', () async {
      // Half a line is worse than none: it would otherwise be kept as a tool with an empty command,
      // and the machine would be asked its version by running the tool with no arguments at all.
      const AssertCliToolVersions malformed = AssertCliToolVersions(
        tools: <String>['yq=v4.53.3'],
        unpinnable: <String>[],
        versionCommands: <String>['yq=', '=--version', 'yq'],
      );
      final CheckResult answer = await malformed.check(withTools().contextFor(under));
      expect((answer as Blocked).reason, contains('nothing was given to ask yq'));
    });

    test('everything wrong is reported at once', () async {
      final HostMachine machine = withTools();
      machine.shell
        ..fails('command -v yq')
        ..fails('command -v vault');
      final CheckResult answer = await step.check(machine.contextFor(under));
      final String reason = (answer as Blocked).reason;
      expect(reason, contains('yq'));
      expect(reason, contains('vault'));
    });
  });

  group('the shell aliases', () {
    const AddShellAlias step = AddShellAlias(
      alias: 'kubectl',
      command: 'microk8s.kubectl',
      rcFiles: <String>['.bashrc', '.zshrc'],
    );

    HostMachine account({Map<String, String> rcFiles = const <String, String>{}}) {
      final HostMachine machine = HostMachine();
      machine.shell.answers(
        'getent passwd $operatorUser',
        '$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n',
      );
      rcFiles.forEach((String name, String content) {
        machine.files.contents['$operatorHome/$name'] = content;
      });
      return machine;
    }

    test('a startup file this machine does not have is never created', () async {
      final HostMachine machine = account();
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      await step.apply(machine.contextFor(under));
      expect(machine.files.written, isEmpty);
    });

    test('the alias goes into every startup file that is there', () async {
      final HostMachine machine = account(
        rcFiles: <String, String>{'.bashrc': '# a shell\n', '.zshrc': '# another shell\n'},
      );
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(machine.files.contents['$operatorHome/.bashrc'], contains(step.line));
      expect(machine.files.contents['$operatorHome/.zshrc'], contains(step.line));
      expect(await step.check(context), isA<Satisfied>());
    });

    test('a second run adds no second line', () async {
      final HostMachine machine = account(
        rcFiles: <String, String>{'.bashrc': "alias kubectl='microk8s.kubectl'\n"},
      );
      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.files.written, isEmpty);
    });

    test('the home is read from the account rather than composed from the name', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers(
        'getent passwd $operatorUser',
        '$operatorUser:x:1000:1000::/srv/$operatorUser:/bin/bash\n',
      );
      expect(
        await AddShellAlias.homeOf(machine.contextFor(under), operatorUser),
        '/srv/$operatorUser',
      );
    });
  });

  group('the credentials for this cluster', () {
    const ExportKubeconfig step = ExportKubeconfig();
    const String credentials = 'apiVersion: v1\nkind: Config\nclusters: []\n';

    test('the file is readable by its owner alone, and so is the directory', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(
          'getent passwd $operatorUser',
          '$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n',
        )
        ..answers('microk8s config', credentials);

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(machine.files.contents['$operatorHome/.kube/config'], credentials);
      expect(machine.files.modes['$operatorHome/.kube/config'], 0x180);
      expect(machine.files.modes['$operatorHome/.kube'], 0x1c0);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('the credentials never reach the plan', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(
          'getent passwd $operatorUser',
          '$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n',
        )
        ..answers('microk8s config', 'apiVersion: v1\nusers:\n- name: admin\n  token: s3cr3t\n');

      final StepPlan plan = await step.plan(machine.contextFor(under));
      expect((plan as DiffPlan).after, isNot(contains('s3cr3t')));
    });

    test('it says what is lost, because the file is replaced whole', () {
      expect(step.irreversibleReason, contains('another cluster'));
    });
  });
}
