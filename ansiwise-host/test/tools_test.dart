import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The tag shapes a program row states for the tools below: one project writes its tag with a
/// leading letter, another writes its own name in front of the number.
const List<String> pinPrefixes = <String>['v', 'jq-'];

/// The two shapes a pinned release arrives in, each written the way a program row writes it.
///
/// One step covers both, so what separates them is only their arguments — which is the claim these
/// tests are here to hold. A release that IS the binary is fetched straight to where it goes; one
/// that arrives packed is unpacked out of an archive, and its project spells the version without
/// the shape its tag carries, which is what the second slot in a url is for.
/// A tool whose release arrives PACKED, and whose project spells the version without the shape its
/// tag carries — which is what the second slot in a url is for.
///
/// Invented rather than borrowed. A fixture naming a real vendor's release layout is a
/// specification of one product's dependency living in a package that must serve any product, and
/// it goes stale the day that vendor moves a path.
const InstallPinnedTool packedCli = InstallPinnedTool(
  tool: 'packed-cli',
  version: 'v2.0.3',
  url:
      'https://releases.example.invalid/packed-cli/${InstallPinnedTool.bareVersionPlaceholder}/'
      'packed-cli_${InstallPinnedTool.bareVersionPlaceholder}_linux_amd64.zip',
  directory: InstallPinnedTool.defaultDirectory,
  archive: '/tmp/packed-cli.zip',
  versionCommand: <String>['version'],
  pinPrefixes: pinPrefixes,
);

/// A tool whose version is a RELEASE TAG rather than a bare number — a stamped binary answers
/// `<major>.<minor>.<patch>-<channel>-<ts14>`, ts14 being a UTC `yyyyMMddHHmmss`.
///
/// Invented for the same reason as the two around it, and its pin is the whole of what separates it
/// from them: a tag BEGINS with three numbers a bare-version reader matches, so a reader that stops
/// there answers something the tool never printed and the machine is fetched again on every run.
const InstallPinnedTool stampedCli = InstallPinnedTool(
  tool: 'stamped-cli',
  version: '0.1.0-alpha-20260822223803',
  url:
      'https://releases.example.invalid/stamped-cli/'
      '${InstallPinnedTool.versionPlaceholder}/stamped-cli',
  directory: InstallPinnedTool.defaultDirectory,
  archive: null,
  versionCommand: <String>['--version'],
  pinPrefixes: pinPrefixes,
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
  pinPrefixes: pinPrefixes,
);

/// The tools an operator uses on the machine, and the pins that make two machines the same.
void main() {
  const StepName under = StepName('under_test');

  group('the two things every tool download needs', () {
    const InstallToolPrerequisites step = InstallToolPrerequisites(
      packages: <String>['curl', 'unzip'],
    );

    test('the verdict comes from the commands, never from the package manager', () async {
      // Automatic updates hold the package lock for minutes after a machine boots, so an install
      // exits with a failure on a freshly provisioned machine that already carries both.
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(onThePathKey('curl'), '/usr/bin/curl\n')
        ..answers(onThePathKey('unzip'), '/usr/bin/unzip\n')
        ..fails('apt-get install --yes', exitCode: 100, stderr: 'could not get lock');

      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a machine missing one of them installs it and is judged again on the command', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(onThePathKey('curl'), '/usr/bin/curl\n')
        ..fails(onThePathKey('unzip'))
        ..fails('apt-get install --yes unzip', exitCode: 100, stderr: 'could not get lock')
        ..changes('apt-get install --yes unzip', () {
          machine.shell.answers(onThePathKey('unzip'), '/usr/bin/unzip\n');
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
        ..shell.fails(onThePathKey('curl'))
        ..shell.fails(onThePathKey('unzip'));
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
        ..answers(onThePathKey('yq'), '/usr/local/bin/yq\n')
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
        ..answers(onThePathKey('yq'), '/usr/local/bin/yq\n')
        ..answers('yq --version', 'yq (https://github.com/mikefarah/yq/) version v4.53.3\n');

      expect(await yqCli.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a tool answering a release tag is held against its pin whole, and left alone', () async {
      // The machine that costs something: it is AT the pin, and a reader stopping at the first
      // three numbers of the tag holds `0.1.0` against a pin that is still whole, never matches,
      // and fetches the release again on every run — silently, because every fetch succeeds.
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(onThePathKey('stamped-cli'), '/usr/local/bin/stamped-cli\n')
        ..answers('stamped-cli --version', '${stampedCli.version}\n');

      expect(await stampedCli.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a release-tagged tool at another stamp of the same numbers is fetched', () async {
      // The other half, and the reason the tag is compared whole rather than trimmed to its numbers
      // on both sides: a rebuild of the same version IS three equal numbers and a different stamp,
      // so a comparison that only reached the numbers would call this machine right.
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(onThePathKey('stamped-cli'), '/usr/local/bin/stamped-cli\n')
        ..answers('stamped-cli --version', '0.1.0-alpha-20260101000000\n');

      expect(await stampedCli.check(machine.contextFor(under)), isA<Ready>());
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
        pinPrefixes: pinPrefixes,
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
        pinPrefixes: pinPrefixes,
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
          pinPrefixes: pinPrefixes,
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
          tool: 'silent-cli',
          version: 'v4.2.3',
          url:
              'https://releases.example.invalid/silent-cli/'
              '${InstallPinnedTool.versionPlaceholder}/silent-cli',
          directory: InstallPinnedTool.defaultDirectory,
          archive: null,
          versionCommand: <String>[],
          pinPrefixes: pinPrefixes,
        ).check(HostMachine().contextFor(under));
        expect((answer as Blocked).reason, contains('what version it is'));
      },
    );

    test('the fetch names the pinned release and never a latest one', () {
      // The one download path that spells the version without the shape its tag carries, which is
      // what the second slot exists for — the pin is still written once, as v2.0.3.
      expect(packedCli.fetchedFrom, contains('/packed-cli/2.0.3/packed-cli_2.0.3_linux_amd64.zip'));

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
        ..answers(onThePathKey('yq'), '/usr/local/bin/yq\n')
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
      expect(packedCli.irreversibleReason, contains('everything the archive holds is unpacked'));
    });

    test('the packed copy is removed whether the unpacking worked or not', () async {
      // A half-finished download left behind is what the next run would unpack.
      final HostMachine machine = HostMachine();
      machine.shell
        ..fails(onThePathKey('packed-cli'))
        ..fails('unzip -o -d ${packedCli.directory} ${packedCli.archive}');

      await expectLater(packedCli.apply(machine.contextFor(under)), throwsA(isA<CommandFailed>()));
      expect(machine.files.deleted, contains(packedCli.archive));
    });

    // A TOOL A SERVICE RUNS COULD NOT BE REPLACED AT ALL while the fetch wrote into the file that
    // was already there. `curl --output` opens the target and writes through it, and Linux refuses
    // that on a file some process is EXECUTING. Measured on a real machine against a running
    // binary: `curl: (23) client returned ERROR on write of 16375 bytes`, and the old file left
    // intact — a clean failure, and a failure every single time.
    //
    // A rename replaces the directory ENTRY instead, so the running process keeps the inode it
    // started from and the next invocation is the new file.
    test(
      'the fetch lands beside the tool and is MOVED onto it, never written through it',
      () async {
        final HostMachine machine = HostMachine();
        machine.shell.fails(onThePathKey('yq'));

        await yqCli.apply(machine.contextFor(under));

        final String target = '${yqCli.directory}/yq';
        expect(
          machine.shell.ran,
          containsAllInOrder(<String>[
            'chmod 755 $target.incoming',
            'mv -f $target.incoming $target',
          ]),
          reason:
              'the execute bit is set before the move, so the target is never briefly there and '
              'unrunnable',
        );
        expect(
          machine.shell.ran.where((String each) => each.startsWith('curl ')).single,
          allOf(contains('--output $target.incoming'), isNot(contains('--output $target '))),
        );
      },
    );

    test('the incoming file stands BESIDE the target, on its own filesystem', () async {
      // A rename is atomic only within one filesystem, and /tmp is frequently another one — a
      // fetch into /tmp would fall back to a copy, which writes through the target again.
      expect(yqCli.incoming, startsWith('${yqCli.directory}/'));
    });

    test('a fetch that failed leaves nothing beside the tool', () async {
      // A half-finished download under a name nothing reads is what the next run would fetch over
      // and be none the wiser about.
      final HostMachine machine = HostMachine();
      machine.shell
        ..fails(onThePathKey('yq'))
        ..fails(
          'curl --silent --show-error --fail --location --output '
          '${yqCli.directory}/yq.incoming ${yqCli.fetchedFrom}',
        );

      await expectLater(yqCli.apply(machine.contextFor(under)), throwsA(isA<CommandFailed>()));
      expect(machine.files.deleted, contains('${yqCli.directory}/yq.incoming'));
    });
  });

  group('the pins held against the machine', () {
    // The release-tagged tool stands in the same list as the bare-numbered ones, because one run
    // holds every tool a program pins and the two shapes have to be read side by side rather than
    // each in a suite of its own.
    const RequireCliToolVersions step = RequireCliToolVersions(
      tools: <String>[
        'packed-cli=v2.0.3',
        'yq=v4.53.3',
        'jq=jq-1.8.2',
        'tailscale=v1.98.10',
        'stamped-cli=0.1.0-alpha-20260822223803',
      ],
      unpinnable: <String>['jq', 'tailscale'],
      versionCommands: <String>[
        'packed-cli=version',
        'yq=--version',
        'jq=--version',
        'tailscale=version',
        'stamped-cli=--version',
      ],
      pinPrefixes: pinPrefixes,
    );

    HostMachine withTools({Map<String, String> answers = const <String, String>{}}) {
      final HostMachine machine = HostMachine();
      for (final String tool in <String>['packed-cli', 'yq', 'jq', 'tailscale', 'stamped-cli']) {
        machine.shell.answers(onThePathKey(tool), '/usr/local/bin/$tool\n');
      }
      machine.shell
        ..answers('packed-cli version', 'Packed CLI v2.0.3 (abcdef1), built 2026-01-01\n')
        ..answers('yq --version', 'yq (https://github.com/mikefarah/yq/) version v4.53.3\n')
        ..answers('jq --version', 'jq-1.8.2\n')
        ..answers('tailscale version', '1.98.10\n  tailscale commit: abcdef1\n')
        ..answers('stamped-cli --version', '0.1.0-alpha-20260822223803\n');
      answers.forEach(machine.shell.answers);
      return machine;
    }

    test('the tag shape comes off before the comparison', () {
      expect(RequireCliToolVersions.bare('v4.53.3', pinPrefixes), '4.53.3');
      expect(RequireCliToolVersions.bare('jq-1.8.2', pinPrefixes), '1.8.2');
      expect(RequireCliToolVersions.bare('2.0.3', pinPrefixes), '2.0.3');
    });

    test('at most ONE shape comes off, so two of them cannot eat into the version', () {
      // The defect this replaced: every shape was stripped in turn, so a tag beginning with one of
      // them and holding another lost both and was compared as a number no tool answers with.
      expect(RequireCliToolVersions.bare('vjq-1.7', pinPrefixes), 'jq-1.7');
    });

    test('the longest shape wins, so one that begins with another is not cut short', () {
      expect(RequireCliToolVersions.bare('jq-1.8.2', <String>['j', 'jq-']), '1.8.2');
    });

    test('a row that names no shape leaves every pin as it stands', () {
      expect(RequireCliToolVersions.bare('v4.53.3', <String>[]), 'v4.53.3');
    });

    test('a release tag carries no shape to take off, so the whole tag is what is compared', () {
      expect(
        RequireCliToolVersions.bare('0.1.0-alpha-20260822223803', pinPrefixes),
        '0.1.0-alpha-20260822223803',
      );
    });

    test('a release tag is read whole, and not as the three numbers it begins with', () {
      expect(
        RequireCliToolVersions.versionIn('0.1.0-alpha-20260822223803'),
        '0.1.0-alpha-20260822223803',
      );
      expect(
        RequireCliToolVersions.versionIn('12.7.30-stable-20250101235959'),
        '12.7.30-stable-20250101235959',
      );
    });

    test('a bare version is read exactly as it is read today', () {
      // Every shape the tools pinned before a release tag existed answer in, held here so that
      // making room for the fuller shape cannot quietly change what any of them reads as.
      expect(
        RequireCliToolVersions.versionIn('yq (https://github.com/mikefarah/yq/) version v4.53.3'),
        '4.53.3',
      );
      expect(RequireCliToolVersions.versionIn('1.98.10'), '1.98.10');
      expect(
        RequireCliToolVersions.versionIn('Packed CLI v2.0.3 (abcdef1), built 2026-01-01'),
        '2.0.3',
      );
      expect(RequireCliToolVersions.versionIn('jq-1.8.2'), '1.8.2');
      expect(RequireCliToolVersions.versionIn('cluster-cli: v3.4.5'), '3.4.5');
      expect(RequireCliToolVersions.versionIn('v2.0'), '2.0');
    });

    test('a line carrying nothing shaped like a version is no version, and not a guess', () {
      // What a binary built without a tag answers. It is deliberately not shaped like a version, so
      // that nothing comparing can mistake it for a released one.
      expect(RequireCliToolVersions.versionIn('unreleased'), isNull);
    });

    test('the ORDER of the two shapes is what does it, and the other order answers wrongly', () {
      // Held against a reader that differs from the real one in nothing but the order, so what is
      // measured here is the order and not the shapes. The shorter shape matches INSIDE the fuller
      // one, so trying it first stops at three numbers of a tag and answers a version the tool never
      // printed — and that value, against a pin that stays whole, is a machine refetched forever.
      String? shorterFirst(String said) {
        for (final RegExp shape in <RegExp>[
          RegExp(r'\d+\.\d+(\.\d+)?'),
          RegExp(r'\d+\.\d+\.\d+-[A-Za-z]+-\d{14}'),
        ]) {
          final RegExpMatch? found = shape.firstMatch(said);
          if (found != null) {
            return found.group(0);
          }
        }
        return null;
      }

      const String tag = '0.1.0-alpha-20260822223803';
      expect(shorterFirst(tag), '0.1.0', reason: 'this is the answer the other order gives');
      expect(RequireCliToolVersions.versionIn(tag), tag);

      // And the order costs the bare shapes nothing, because the fuller shape does not fit a line
      // without a channel and a stamp on it: both orders reach the same reader for those.
      for (final String said in <String>['v4.53.3', '1.98.10', 'jq-1.8.2', 'unreleased']) {
        expect(shorterFirst(said), RequireCliToolVersions.versionIn(said));
      }
    });

    test('a version reader answers with the bare version and nothing else', () async {
      // Two shapes, and neither is the bare number. One prints the version and then the commit it
      // was built from on the lines after it; the other prints a name in front of the version and
      // the build behind it on the one line.
      final HostMachine machine = withTools();
      expect(
        (await RequireCliToolVersions.installedVersion(
          machine.contextFor(under),
          'tailscale',
          <String>['version'],
        )).version,
        '1.98.10',
      );
      expect(
        (await RequireCliToolVersions.installedVersion(
          machine.contextFor(under),
          'packed-cli',
          <String>['version'],
        )).version,
        '2.0.3',
      );
    });

    // A TOOL WITHOUT A VERSION IS THREE DIFFERENT SITUATIONS, and the report has to tell them
    // apart. The third — present, answering, unreadable — is what a binary built outside a release
    // looks like: it answers a WORD rather than a number, deliberately, so that nothing compares it
    // to a pin. Reported as absent, it sends an operator to place a binary already standing there.
    test('a tool that is absent, one that will not answer, and one that answers a word', () async {
      final HostMachine machine = withTools();
      machine.shell
        ..fails(onThePathKey('gone-cli'))
        ..answers(onThePathKey('mute-cli'), '/usr/local/bin/mute-cli\n')
        ..fails('mute-cli --version', stderr: 'error while loading shared libraries')
        ..answers(onThePathKey('unstamped-cli'), '/usr/local/bin/unstamped-cli\n')
        ..answers('unstamped-cli --version', 'unreleased\n');

      Future<String> problemOf(String tool) async => (await RequireCliToolVersions.installedVersion(
        machine.contextFor(under),
        tool,
        <String>['--version'],
      )).problem;

      expect(await problemOf('gone-cli'), contains('is not on this machine'));
      expect(
        await problemOf('mute-cli'),
        allOf(
          contains('would not say what version it is'),
          contains('error while loading shared libraries'),
        ),
        reason: 'the words the tool said are the only thing that says which failure this is',
      );
      expect(
        await problemOf('unstamped-cli'),
        allOf(contains('unreleased'), isNot(contains('is not on this machine'))),
        reason: 'it IS on the machine, and quoting what it answered is what shows that',
      );
    });

    test('a machine at every pin passes', () async {
      expect(await step.check(withTools().contextFor(under)), isA<Satisfied>());
    });

    test('a tool that is missing fails, whether its version could be chosen or not', () async {
      final HostMachine machine = withTools();
      machine.shell
        ..fails(onThePathKey('jq'))
        ..fails(onThePathKey('yq'));

      final CheckResult answer = await step.check(machine.contextFor(under));
      final String reason = (answer as Blocked).reason;
      expect(reason, contains('jq is not on this machine'));
      expect(reason, contains('yq is not on this machine'));
    });

    test('a tool that IS there and answers a word is not reported as missing', () async {
      // The whole report an operator acts on, not the reader underneath it. A binary built outside
      // a release answers `unreleased` — a word rather than a number, on purpose, so that nothing
      // compares it to a pin — and reported as absent it sends somebody to place a binary that is
      // already standing there.
      final HostMachine machine = withTools();
      machine.shell.answers('yq --version', 'unreleased\n');

      final CheckResult answer = await step.check(machine.contextFor(under));
      final String reason = (answer as Blocked).reason;
      expect(
        reason,
        allOf(contains('yq answered "unreleased"'), isNot(contains('yq is not on this machine'))),
        reason: 'quoting what it said is the whole of what tells the two situations apart',
      );
    });

    test('a tool that is there and will not answer says so, with what it said', () async {
      final HostMachine machine = withTools();
      machine.shell.fails('yq --version', stderr: 'error while loading shared libraries');

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect(
        (answer as Blocked).reason,
        allOf(
          contains('yq is on this machine and would not say what version it is'),
          contains('error while loading shared libraries'),
        ),
      );
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

    test('a release-tagged tool that drifted is named at the whole tag it is at', () async {
      // Three numbers equal and the stamp not — a rebuild of the same version. What the operator is
      // told has to be the tag the binary answered, because the numbers alone name two releases.
      final HostMachine machine = withTools(
        answers: <String, String>{'stamped-cli --version': '0.1.0-alpha-20260101000000\n'},
      );
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('stamped-cli is at 0.1.0-alpha-20260101000000'));
    });

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
      const RequireCliToolVersions unknown = RequireCliToolVersions(
        tools: <String>['silent-cli=v4.2.3'],
        unpinnable: <String>[],
        versionCommands: <String>[],
        pinPrefixes: pinPrefixes,
      );
      final CheckResult answer = await unknown.check(withTools().contextFor(under));
      expect((answer as Blocked).reason, contains('silent-cli'));
    });

    test('an entry that does not read as a tool and its arguments is no reader at all', () async {
      // Half a line is worse than none: it would otherwise be kept as a tool with an empty command,
      // and the machine would be asked its version by running the tool with no arguments at all.
      const RequireCliToolVersions malformed = RequireCliToolVersions(
        tools: <String>['yq=v4.53.3'],
        unpinnable: <String>[],
        versionCommands: <String>['yq=', '=--version', 'yq'],
        pinPrefixes: pinPrefixes,
      );
      final CheckResult answer = await malformed.check(withTools().contextFor(under));
      expect((answer as Blocked).reason, contains('nothing was given to ask yq'));
    });

    test('everything wrong is reported at once', () async {
      final HostMachine machine = withTools();
      machine.shell
        ..fails(onThePathKey('yq'))
        ..fails(onThePathKey('packed-cli'));
      final CheckResult answer = await step.check(machine.contextFor(under));
      final String reason = (answer as Blocked).reason;
      expect(reason, contains('yq'));
      expect(reason, contains('packed-cli'));
    });
  });

  group('the shell aliases', () {
    // The shape this covers is a short name standing in for a longer command a package installed
    // under a name of its own. Which tool that is belongs to the row, so the fixture invents one.
    const AddShellAlias step = AddShellAlias(
      alias: 'cluster-cli',
      command: 'bundle.cluster-cli',
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
        rcFiles: <String, String>{'.bashrc': "alias cluster-cli='bundle.cluster-cli'\n"},
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
        (await InstallAuthorizedKey.homeOf(machine.contextFor(under))).home,
        '/srv/$operatorUser',
      );
    });
  });

  group('the credentials for this cluster', () {
    const List<String> credentialsCommand = <String>['cluster', 'config'];
    const ExportKubeconfig step = ExportKubeconfig(credentialsCommand: credentialsCommand);
    const String credentials = 'apiVersion: v1\nkind: Config\nclusters: []\n';

    test('the file is readable by its owner alone, and so is the directory', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(
          'getent passwd $operatorUser',
          '$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n',
        )
        ..answers('cluster config', credentials);

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
        ..answers('cluster config', 'apiVersion: v1\nusers:\n- name: admin\n  token: s3cr3t\n');

      final StepPlan plan = await step.plan(machine.contextFor(under));
      expect((plan as DiffPlan).after, isNot(contains('s3cr3t')));
    });

    test('it says what is lost, because the file is replaced whole', () {
      expect(step.irreversibleReason, contains('another cluster'));
    });

    // A COMMAND THAT WOULD NOT ANSWER IS THREE DIFFERENT STATES, and only one of them is about the
    // cluster. The cluster may not be running; the account may be one the distribution does not
    // admit; or the session may predate the group that grants that admission — which is what every
    // first bring-up produces, because the same run is what puts the account in that group and
    // supplementary groups are read once, when a session starts.
    //
    // Told only that the cluster would not hand its credentials over, an operator goes and looks at
    // a cluster that is perfectly healthy. So the command's OWN WORDS are what the refusal carries.
    test('a refusal carries what the command said, not a sentence about the cluster', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(
          'getent passwd $operatorUser',
          '$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n',
        )
        ..fails(
          'cluster config',
          stderr:
              'Insufficient permissions to access the cluster. You can either try again with sudo '
              'or add the user $operatorUser to the cluster group',
        );

      final CheckResult result = await step.check(machine.contextFor(under));
      expect(result, isA<Blocked>());
      expect(
        (result as Blocked).reason,
        allOf(contains('Insufficient permissions'), contains('group')),
        reason:
            'the distribution names the group in its own sentence, and that sentence is the whole '
            'difference between a broken cluster and a session started one step too early',
      );
      expect(
        result.reason,
        contains(credentialsCommand.join(' ')),
        reason: 'an operator has to know WHICH command said it before they can run it themselves',
      );
    });

    test('a command that succeeds and prints nothing is named as that, not as a failure', () async {
      // An empty answer is neither a working cluster nor a refused one, and reporting it as a
      // failure with no words behind it is the shape that sends somebody looking for a message
      // nothing wrote.
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(
          'getent passwd $operatorUser',
          '$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n',
        )
        ..answers('cluster config', '');

      final CheckResult result = await step.check(machine.contextFor(under));
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('answered nothing at all'));
    });

    // WHAT ADMITS THE CALLER IS A PROPERTY OF THE SESSION, so a table of commands measures nothing
    // here: it answers the same however the command was run. The machine below is the one every
    // first bring-up produces — the account IS in the group, and the session this run happens in
    // was started before it was put there — and in that machine the only caller the distribution
    // admits is root.
    test('a session started before the group still gets the credentials', () async {
      final _SessionBoundCluster cluster = _SessionBoundCluster(sessionCarriesTheGroup: false);
      final FakeFiles files = FakeFiles();
      final Step row = _rowFor(<String, Object>{
        'credentials_command': credentialsCommand,
        'elevated': true,
      });

      final StepContext context = _sessionContext(cluster, files);
      expect(await row.check(context), isA<Ready>());
      await row.apply(context);

      expect(files.contents['$operatorHome/.kube/config'], _SessionBoundCluster.credentials);
    });

    // THE INNOCENT NEIGHBOUR: the session of a second run, or of a first one after a fresh login,
    // carries the group already, and a row that says nothing about root is served exactly as the
    // operator. Without it this pair would also be passed by a step that raised every call to root
    // whatever its row said, which is a different step from the one being measured.
    test('a session that carries the group is served as the account it started as', () async {
      final _SessionBoundCluster cluster = _SessionBoundCluster(sessionCarriesTheGroup: true);
      final FakeFiles files = FakeFiles();
      final Step row = _rowFor(<String, Object>{'credentials_command': credentialsCommand});

      final StepContext context = _sessionContext(cluster, files);
      expect(await row.check(context), isA<Ready>());
      await row.apply(context);

      expect(files.contents['$operatorHome/.kube/config'], _SessionBoundCluster.credentials);
      expect(
        cluster.asked.map((Command each) => each.elevated),
        everyElement(isFalse),
        reason: 'a row that did not ask for root is not given it, in the check or in the act',
      );
    });
  });
}

/// The step a program row carrying [arguments] builds, taken out of the registry a program reaches.
///
/// Built through the registry rather than by calling the constructor, because what is measured is
/// the whole path a row travels: an argument a row states and the factory drops never reaches the
/// command, and a step constructed by hand in a test is handed the value the row could not deliver.
Step _rowFor(Map<String, Object> arguments) {
  final RegisteredStep? entry = hostRegistry.step(const StepName('export_kubeconfig'));
  if (entry == null) {
    throw StateError('export_kubeconfig is not registered, so nothing here measures anything');
  }
  return entry.create(Arguments(arguments));
}

/// A context whose shell is [shell] and whose files are [files], for the machine below.
StepContext _sessionContext(Shell shell, FakeFiles files) => StepContext(
  shell: shell,
  files: files,
  http: FakeHttp(),
  clock: FakeClock(),
  entropy: FakeEntropy(),
  log: const _SilentLog(),
  step: const StepName('under_test'),
  arguments: Arguments.none,
  answers: hostAnswers,
  facts: Facts.none,
);

/// A machine whose session read its supplementary groups when it started, which is the whole of the
/// failure this pair is about.
///
/// The account is in the group and the group database says so — the row that grants it ran earlier
/// in this same program — but a session carries the groups it was started with, and this one was
/// started before that row. The distribution admits root whatever a session carries, and admits
/// anybody else only through the group, which is exactly the pair of remedies its own refusal
/// names.
final class _SessionBoundCluster implements Shell {
  /// A machine whose session was started after the group was granted where [sessionCarriesTheGroup].
  _SessionBoundCluster({required this.sessionCarriesTheGroup});

  /// Whether the session this run happens in was started after the account joined the group.
  final bool sessionCarriesTheGroup;

  /// What the distribution hands a caller it admits.
  static const String credentials = 'apiVersion: v1\nkind: Config\nclusters: []\n';

  /// What it says to one it does not, in its own words.
  static const String refusal =
      'Insufficient permissions to access the cluster. You can either try again with sudo or add '
      'the user $operatorUser to the cluster group';

  /// Every time the credentials were asked for, so a test can say how they were asked.
  final List<Command> asked = <Command>[];

  @override
  Future<CommandResult> run(Command command) async {
    final String argv = command.argv.join(' ');
    if (argv == 'getent passwd $operatorUser') {
      return _printed('$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n');
    }
    if (argv != 'cluster config') {
      return _printed('');
    }
    asked.add(command);
    return command.elevated || sessionCarriesTheGroup
        ? _printed(credentials)
        : const CommandResult(exitCode: 1, stdout: '', stderr: refusal, elapsed: Duration.zero);
  }

  static CommandResult _printed(String stdout) =>
      CommandResult(exitCode: 0, stdout: stdout, stderr: '', elapsed: Duration.zero);
}

final class _SilentLog implements Logger {
  const _SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
