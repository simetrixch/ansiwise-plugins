import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The mirror a machine's pulls of one registry go through, and the states its credential can be
/// found in.
///
/// **The answer names here are deliberately not the ones any product uses.** Which machine this is
/// and which machine the mirror runs on are read out of the run under the names the ROW gives, so a
/// test written on a product's own words would pass just as well if the names were baked into the
/// package. These are made up on purpose.
void main() {
  const StepName under = StepName('under_test');
  const String repository = '/srv/checkout';
  const String tier = 'dev';
  const String thisMachine = 's1.example.com';
  const String mirrorMachine = 'm1.example.com';
  const String mirrorHost = 'mirror.$mirrorMachine';
  // NAMED FOR THE MACHINE, with the slot every real program's path carries: the profile of one
  // installation is named for that installation, so a program file shipped to every installation
  // spells the name as a slot. Without one here, a path whose slot is never filled is a path no
  // test can notice going unread (measured on a real deployment: both steps reported themselves
  // satisfied and wrote no mirror at all).
  const String profilePath = '$repository/clusters/active/$thisMachine.yaml';
  const String secretsPath = '$repository/secrets/secrets.$tier';
  const String certsDirectory = '/var/lib/containerd/certs.d';
  const String mirroredRegistry = 'registry.example.com';
  const String fallback = 'https://registry.example.com';
  const String credential = 'cHVsbC11c2VyOnNlY3JldA==';

  /// The names this row reads the run's answers under, and the axis its credential file is per.
  const String machineNameAnswer = 'machine_name';
  const String mirrorMachineAnswer = 'mirror_machine';
  const String tierAnswer = 'tier';

  const RegistryMirror layout = RegistryMirror(
    repository: repository,
    profilePath: 'clusters/active/<$machineNameAnswer>.yaml',
    mirrorHostKey: 'global.endpoints.registry.host',
    secretsPath: 'secrets/secrets.<$tierAnswer>',
    credentialKey: 'REGISTRY_PULL_DOCKERCONFIGJSON',
    placeholderPrefix: 'BASE64_OF_',
    mirroredRegistry: mirroredRegistry,
    thisMachineAnswer: machineNameAnswer,
    mirrorMachineAnswer: mirrorMachineAnswer,
    runAnswer: tierAnswer,
  );

  const RequireRegistryPullCredential step = RequireRegistryPullCredential(layout: layout);

  const WriteContainerdRegistryMirror mirror = WriteContainerdRegistryMirror(
    layout: layout,
    certsDirectory: certsDirectory,
    fallback: fallback,
    fileMode: 384,
  );

  String profile({String host = mirrorHost}) =>
      'global:\n'
      '  someOtherUrl: https://elsewhere.$mirrorMachine\n'
      '  endpoints:\n'
      '    registry:\n'
      '      host: $host\n';

  String secrets({String? value, String newline = '\n'}) {
    final String written =
        value ??
        base64.encode(
          utf8.encode(
            jsonEncode(<String, Object>{
              'auths': <String, Object>{
                mirrorHost: <String, String>{'auth': credential},
              },
            }),
          ),
        );
    return <String>[
      '# the credentials this machine needs',
      'REGISTRY_PULL_DOCKERCONFIGJSON=$written',
      '',
    ].join(newline);
  }

  /// A run on a machine that pulls through another machine's mirror, which is the case these tests
  /// are written on: the three values the two steps read are answered, not constructed into them.
  Arguments answeredAs({String machine = thisMachine, String mirrorRunsOn = mirrorMachine}) =>
      hostAnswering(<String, Object>{
        tierAnswer: tier,
        machineNameAnswer: machine,
        mirrorMachineAnswer: mirrorRunsOn,
      });

  HostMachine machineWith({String? secretsFile, bool withCertsDirectory = true}) {
    final HostMachine machine = HostMachine();
    machine.files.contents[profilePath] = profile();
    if (secretsFile != null) {
      machine.files.contents[secretsPath] = secretsFile;
    }
    if (withCertsDirectory) {
      machine.files.directories.add(certsDirectory);
    }
    return machine;
  }

  group('which machine this is', () {
    test('a row naming an answer this run does not hold is refused by both steps', () {
      // Without this the pair would read an empty name, decide this machine IS the mirror, and
      // leave every pull on the rate-limited public path with nothing saying so.
      final HostMachine machine = machineWith(secretsFile: secrets());
      final StepContext context = machine.contextFor(under, Arguments.none, hostAnswers);

      for (final Future<CheckResult> answer in <Future<CheckResult>>[
        step.check(context),
        mirror.check(context),
      ]) {
        expect(
          answer.then((CheckResult result) => (result as Blocked).reason),
          completion(contains(machineNameAnswer)),
        );
      }
    });

    test('a machine that is the mirror needs no mirror at all', () async {
      // At this point in its own install that mirror does not exist, so this is a genuine no-op
      // rather than something that failed.
      expect(
        await step.check(
          machineWith().contextFor(under, Arguments.none, answeredAs(machine: mirrorMachine)),
        ),
        isA<Satisfied>(),
      );
    });

    test(
      'an empty answer says the mirror runs here, which is what one machine alone states',
      () async {
        final HostMachine machine = machineWith(secretsFile: secrets());
        expect(
          await mirror.check(
            machine.contextFor(under, Arguments.none, answeredAs(mirrorRunsOn: '')),
          ),
          isA<Satisfied>(),
        );
        expect(machine.files.written, isEmpty);
      },
    );
  });

  group('the states the credential can be found in', () {
    test('a mirror address that cannot be read means there is no mirror to write', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[profilePath] = 'global:\n  someOtherUrl: https://elsewhere\n';
      expect(
        await step.check(machine.contextFor(under, Arguments.none, answeredAs())),
        isA<Satisfied>(),
      );
    });

    test('no credential file on the machine warns, writes no mirror and stays green', () async {
      // The unattended base install of a machine runs before any credential reaches it. Failing
      // here would kill every one of them.
      final HostMachine machine = machineWith();
      expect(
        await step.check(machine.contextFor(under, Arguments.none, answeredAs())),
        isA<Satisfied>(),
      );
      expect(machine.said.join('\n'), contains(secretsPath));
      expect(machine.said.join('\n'), contains('run this program again'));

      final HostMachine writing = machineWith();
      expect(
        await mirror.check(writing.contextFor(under, Arguments.none, answeredAs())),
        isA<Satisfied>(),
      );
      expect(writing.files.written, isEmpty);
    });

    test('a credential file with the line endings of another operating system is refused', () async {
      // The character prints as nothing, so the failure surfaces far away as a rejected credential
      // for a value that looks perfectly correct.
      final HostMachine machine = machineWith(secretsFile: secrets(newline: '\r\n'));
      final CheckResult answer = await step.check(
        machine.contextFor(under, Arguments.none, answeredAs()),
      );
      expect((answer as Blocked).reason, contains('line endings'));
    });

    test('a blank credential is refused by name', () async {
      final HostMachine machine = machineWith(secretsFile: secrets(value: ''));
      final CheckResult answer = await step.check(
        machine.contextFor(under, Arguments.none, answeredAs()),
      );
      expect((answer as Blocked).reason, contains('REGISTRY_PULL_DOCKERCONFIGJSON'));
      expect(answer.reason, contains('blank'));
    });

    test('the placeholder an example file ships is refused by name', () async {
      final HostMachine machine = machineWith(secretsFile: secrets(value: 'BASE64_OF_/dev/null'));
      final CheckResult answer = await step.check(
        machine.contextFor(under, Arguments.none, answeredAs()),
      );
      expect((answer as Blocked).reason, contains('placeholder'));
    });

    test('a usable credential passes', () async {
      final HostMachine machine = machineWith(secretsFile: secrets());
      expect(
        await step.check(machine.contextFor(under, Arguments.none, answeredAs())),
        isA<Satisfied>(),
      );
    });

    test('the same refusal is made again where the mirror is written', () async {
      // Running the writing program on its own keeps the guard that the gate before the install
      // carries.
      final HostMachine machine = machineWith(secretsFile: secrets(value: ''));
      expect(
        await mirror.check(machine.contextFor(under, Arguments.none, answeredAs())),
        isA<Blocked>(),
      );
      expect(machine.files.written, isEmpty);
    });
  });

  group('the file the mirror is written into', () {
    test('the mirrored registry stays in it as the fallback', () async {
      // With it, a mirror that is down makes a pull slower. Without it, the same mirror makes every
      // pull impossible.
      final HostMachine machine = machineWith(secretsFile: secrets());
      await mirror.apply(machine.contextFor(under, Arguments.none, answeredAs()));
      expect(machine.files.contents[mirror.path], contains('server = "$fallback"'));
    });

    test('the mirror address comes from the profile and is never composed', () async {
      final HostMachine machine = machineWith(secretsFile: secrets());
      await mirror.apply(machine.contextFor(under, Arguments.none, answeredAs()));
      final String written = machine.files.contents[mirror.path] ?? '';
      expect(written, contains('[host."https://$mirrorHost"]'));
      expect(
        written,
        isNot(contains(thisMachine)),
        reason: 'nothing here composes the address out of any name',
      );
    });

    test('it carries the credential and is readable by its owner alone', () async {
      final HostMachine machine = machineWith(secretsFile: secrets());
      await mirror.apply(machine.contextFor(under, Arguments.none, answeredAs()));
      expect(machine.files.contents[mirror.path], contains('authorization = "Basic $credential"'));
      expect(machine.files.modes[mirror.path], 384);
    });

    test('the credential reaches the file and nothing else', () async {
      final HostMachine machine = machineWith(secretsFile: secrets());
      final StepContext context = machine.contextFor(under, Arguments.none, answeredAs());
      await mirror.apply(context);
      final StepPlan plan = await mirror.plan(context);

      expect(machine.said.join('\n'), isNot(contains(credential)));
      expect(plan.summary, isNot(contains(credential)));
      expect((plan as DiffPlan).after, isNot(contains(credential)));
      expect(
        plan.after,
        contains(WriteContainerdRegistryMirror.redactedCredential),
        reason: 'what the plan says instead is named, so an empty diff cannot pass for a redaction',
      );
      // BOTH sides. This plan is taken over a file the apply above already wrote, so `before` is
      // the machine's own text, and an assertion looking only at what the step composed would miss
      // it. The record writes `before` out, and the redactor hides the values of declared-secret
      // ANSWERS; this one comes off a machine, so nothing hides it.
      expect(plan.before, isNot(contains(credential)));
      expect(
        plan.before,
        contains(WriteContainerdRegistryMirror.redactedCredential),
        reason: 'the line is still shown, so a redaction cannot be read as a line the file lacks',
      );
    });

    test('a plan written before anything exists carries no credential either', () async {
      // The case above plans over a file this run already wrote. This one plans on a machine where
      // the file is not there at all, which is the shape an operator reads before the first run.
      final HostMachine machine = machineWith(secretsFile: secrets());
      final StepPlan plan = await mirror.plan(
        machine.contextFor(under, Arguments.none, answeredAs()),
      );
      expect((plan as DiffPlan).before, isEmpty);
      expect(plan.after, isNot(contains(credential)));
      expect(plan.after, contains(WriteContainerdRegistryMirror.redactedCredential));
    });

    test('nothing out of the credential file reaches this program beyond the credential', () async {
      // A file of credentials that is run rather than read puts every value in it into everything
      // the run starts afterwards.
      final HostMachine machine = machineWith(
        secretsFile: '${secrets()}SOME_OTHER_SECRET=must-not-travel\n',
      );
      await mirror.apply(machine.contextFor(under, Arguments.none, answeredAs()));
      expect(machine.files.contents[mirror.path], isNot(contains('must-not-travel')));
      expect(machine.said.join('\n'), isNot(contains('must-not-travel')));
    });

    test('a second run does not write it again, and nothing is restarted', () async {
      // The container runtime reads the file again on every pull.
      final HostMachine machine = machineWith(secretsFile: secrets());
      final StepContext context = machine.contextFor(under, Arguments.none, answeredAs());

      expect(await mirror.check(context), isA<Ready>());
      await mirror.apply(context);
      expect(await mirror.check(context), isA<Satisfied>());
      expect(machine.files.written, hasLength(1));
      expect(machine.changing, isEmpty);
    });

    test('a machine whose runtime reads no such directory is warned and skipped', () async {
      final HostMachine machine = machineWith(secretsFile: secrets(), withCertsDirectory: false);
      expect(
        await mirror.check(machine.contextFor(under, Arguments.none, answeredAs())),
        isA<Satisfied>(),
      );
      expect(machine.files.written, isEmpty);
      expect(machine.said.join('\n'), contains('rate-limited'));
    });

    test('the file stands where the container runtime looks for it', () {
      expect(mirror.path, '$certsDirectory/$mirroredRegistry/hosts.toml');
    });
  });
}
