import 'dart:io';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The step that gives an account's `ssh` the host key of a machine it has to reach.
///
/// **THE CASES RUN THE REAL `ssh-keygen` OVER REAL FILES, in a home made for each one.** Which lines
/// of a `known_hosts` name a machine is the tool's own judgement — a name may stand in plain form or
/// hashed with a salt — and a fake that answered the tool's output would only show that the step
/// reads the output the test wrote. The one thing that is not real is the account database: the
/// home the account has is the scratch one.
void main() {
  const String host = 'host-2.example.org';
  const String oldKey =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHsiaTSWroVqO3IfaD8EIGgOvfaBanJEm+563U/6zktx';
  const String newKey =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+yarTCqTJqZvrbh838TZX3/vyXyI2j2c9k/NdRKUib';
  const String otherKey =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDqq8RyjhPse72PAyb1ChL0rilxhbMXlCHvel+iPCSDX';
  const String ecdsaKey =
      'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBA75/jXXhnV3v/MIWuAtFzsdb/KAiyAWhi2v1+1SWvdOtvF5Jnqr2mUHIdOInYnVWtOsdYAUAd3bEOeYOtJGXWM=';

  const InstallKnownHost step = InstallKnownHost(
    hostAnswer: 'slave_ssh_host',
    hostPortAnswer: 'slave_ssh_port',
    keyAnswer: 'slave_host_key',
  );

  late Directory scratch;
  late String knownHosts;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('install-known-host');
    Directory('${scratch.path}/.ssh').createSync();
    knownHosts = '${scratch.path}/.ssh/known_hosts';
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  StepContext contextOf({String? name = host, String? port = '22', String? key = newKey}) =>
      HostMachine().contextFor(
        const StepName('install_known_host'),
        Arguments.none,
        hostAnswering(<String, Object>{
          'slave_ssh_host': ?name,
          'slave_ssh_port': ?port,
          'slave_host_key': ?key,
        }),
        _AccountAt(scratch.path),
        const RealFiles(),
      );

  String held() => File(knownHosts).readAsStringSync();

  void hold(String content) => File(knownHosts).writeAsStringSync(content);

  /// Rewrites the file the way `ssh-keygen -H` does, which is how `HashKnownHosts yes` leaves it.
  void hashTheNames() {
    final ProcessResult hashed = Process.runSync('ssh-keygen', <String>['-H', '-f', knownHosts]);
    expect(hashed.exitCode, 0, reason: '${hashed.stderr}');
    File('$knownHosts.old').deleteSync();
  }

  /// Whether the real tool finds a line for [name] in the file, which is the question `ssh` asks of it
  /// under the name it was asked to dial.
  bool findsUnder(String name) =>
      Process.runSync('ssh-keygen', <String>['-F', name, '-f', knownHosts]).exitCode == 0;

  /// The first line of the file that carries [key], which for a hashed name is not recognisable by
  /// its text.
  String lineOf(String key) => held().split('\n').firstWhere((String line) => line.contains(key));

  test('a machine with no entry gets its key, and every other line stays as it was', () async {
    hold('# written by hand\nother.example.org $otherKey\n');

    expect(await step.check(contextOf()), isA<Ready>());
    await step.apply(contextOf());

    expect(held(), '# written by hand\nother.example.org $otherKey\n$host $newKey\n');
    expect(await step.check(contextOf()), isA<Satisfied>());
  });

  test('an account with no .ssh and no known_hosts gets both', () async {
    Directory('${scratch.path}/.ssh').deleteSync();

    expect(await step.check(contextOf()), isA<Ready>());
    await step.apply(contextOf());

    expect(held(), '$host $newKey\n');
    expect(await step.check(contextOf()), isA<Satisfied>());
  });

  test(
    'THE PLANTED DEFECT: a machine that answers with a new key is not satisfied by its old one',
    () async {
      // A step that treated "a line names this machine" as done would leave the master trusting a key
      // the rebuilt machine no longer presents, and every ssh to it would be refused.
      hold('other.example.org $otherKey\n$host $oldKey\nthird.example.org $otherKey\n');

      expect(await step.check(contextOf()), isA<Ready>());
      await step.apply(contextOf());

      expect(held(), 'other.example.org $otherKey\nthird.example.org $otherKey\n$host $newKey\n');
      expect(await step.check(contextOf()), isA<Satisfied>());
    },
  );

  test('THE PLANTED DEFECT: the old key of a HASHED name is found and replaced too', () async {
    hold('other.example.org $otherKey\n$host $oldKey\nthird.example.org $otherKey\n');
    hashTheNames();
    final List<String> before = held().trim().split('\n');
    expect(held(), isNot(contains(host)), reason: 'the names must be hashed for this case');

    expect(await step.check(contextOf()), isA<Ready>());
    await step.apply(contextOf());

    expect(held(), '${before.first}\n${before.last}\n$host $newKey\n');
    expect(held(), isNot(contains(oldKey)));
  });

  test('the old key stands in plain AND hashed form: both lines go', () async {
    hold('$host $oldKey\nother.example.org $otherKey\n');
    final String hashedOld = () {
      hashTheNames();
      return lineOf(oldKey);
    }();
    hold('${held()}$host $oldKey\n');

    await step.apply(contextOf());

    expect(held(), isNot(contains(hashedOld)));
    expect(held(), isNot(contains(oldKey)));
    expect(held().trim().split('\n').last, '$host $newKey');
  });

  test(
    'a second key type for the machine goes, so the file holds exactly one key for it',
    () async {
      hold('$host $newKey\n$host $ecdsaKey\n');

      expect(await step.check(contextOf()), isA<Ready>());
      await step.apply(contextOf());

      expect(held(), '$host $newKey\n');
    },
  );

  test('THE INNOCENT CASE: the new key already in the file, plain, changes nothing', () async {
    hold('other.example.org $otherKey\n$host $newKey\n');

    expect(await step.check(contextOf()), isA<Satisfied>());
    await step.apply(contextOf());

    expect(held(), 'other.example.org $otherKey\n$host $newKey\n');
  });

  test('THE INNOCENT CASE: the new key already in the file, hashed, changes nothing', () async {
    hold('$host $newKey\nother.example.org $otherKey\n');
    hashTheNames();
    final String before = held();

    expect(await step.check(contextOf()), isA<Satisfied>());
    await step.apply(contextOf());

    expect(held(), before);
  });

  test('a second run after the first changes nothing', () async {
    hold('$host $oldKey\n');
    await step.apply(contextOf());
    final String afterFirst = held();

    expect(await step.check(contextOf()), isA<Satisfied>());
    await step.apply(contextOf());

    expect(held(), afterFirst);
  });

  test(
    'THE INNOCENT NEIGHBOUR: a marker line for the machine is left alone and is not its key',
    () async {
      // `@revoked` is somebody's deliberate refusal of a key. Removing it would lift the refusal, and
      // reading it as the machine's key would leave the machine untrusted while saying it is trusted.
      hold('@revoked $host $newKey\n');

      expect(await step.check(contextOf()), isA<Ready>());
      await step.apply(contextOf());

      expect(held(), '@revoked $host $newKey\n$host $newKey\n');
    },
  );

  test(
    'THE INNOCENT NEIGHBOUR: a line for the same name on another port is another machine',
    () async {
      hold('[$host]:2222 $oldKey\n');

      await step.apply(contextOf());

      expect(held(), '[$host]:2222 $oldKey\n$host $newKey\n');
    },
  );

  group('the name ssh looks the machine up under', () {
    test(
      'THE PLANTED DEFECT: a machine on another port than 22 is written as [host]:port, which is the only name ssh consults for it',
      () async {
        await step.apply(contextOf(port: '2222'));

        expect(held(), '[$host]:2222 $newKey\n');
        expect(findsUnder('[$host]:2222'), isTrue);
        expect(findsUnder(host), isFalse, reason: 'a plain name is consulted for port 22 alone');
      },
    );

    test('port 22 is the plain name', () async {
      await step.apply(contextOf());

      expect(held(), '$host $newKey\n');
      expect(findsUnder(host), isTrue);
      expect(findsUnder('[$host]:22'), isFalse);
    });

    test(
      'THE PLANTED DEFECT: the old key of a machine on another port is replaced, plain and hashed',
      () async {
        hold('other.example.org $otherKey\n[$host]:2222 $oldKey\n');
        hashTheNames();
        hold('${held()}[$host]:2222 $oldKey\n');

        expect(await step.check(contextOf(port: '2222')), isA<Ready>());
        await step.apply(contextOf(port: '2222'));

        expect(held(), isNot(contains(oldKey)));
        expect(held().trim().split('\n').last, '[$host]:2222 $newKey');
        expect(findsUnder('[$host]:2222'), isTrue);
        expect(await step.check(contextOf(port: '2222')), isA<Satisfied>());
      },
    );

    test('THE INNOCENT CASE: the key already there under [host]:port changes nothing', () async {
      hold('other.example.org $otherKey\n[$host]:2222 $newKey\n');

      expect(await step.check(contextOf(port: '2222')), isA<Satisfied>());
      await step.apply(contextOf(port: '2222'));

      expect(held(), 'other.example.org $otherKey\n[$host]:2222 $newKey\n');
    });

    test(
      'THE INNOCENT NEIGHBOUR: one name on two ports is two machines, and each keeps its own key',
      () async {
        await step.apply(contextOf());
        await step.apply(contextOf(port: '2222', key: otherKey));

        expect(held(), '$host $newKey\n[$host]:2222 $otherKey\n');
        expect(await step.check(contextOf()), isA<Satisfied>());
        expect(await step.check(contextOf(port: '2222', key: otherKey)), isA<Satisfied>());
      },
    );

    test('a machine moved from port 22 to another keeps its old port\'s line', () async {
      // The line for the old port is another machine's entry as far as this step can tell, and it
      // fails closed: ssh to the old port is refused, never trusted for the new key.
      hold('$host $oldKey\n');

      await step.apply(contextOf(port: '2222'));

      expect(held(), '$host $oldKey\n[$host]:2222 $newKey\n');
    });
  });

  group('every form of machine name a slave row may carry', () {
    const String ipv4 = '203.0.113.7';
    const String ipv6 = '2001:db8::7';

    for (final String name in <String>[ipv4, 'apps2', ipv6]) {
      test(
        'THE PLANTED DEFECT: $name is written, found by the tool and replaced on a new key',
        () async {
          await step.apply(contextOf(name: name, key: oldKey));
          expect(held(), '$name $oldKey\n');
          expect(findsUnder(name), isTrue);

          await step.apply(contextOf(name: name));

          expect(held(), '$name $newKey\n');
          expect(await step.check(contextOf(name: name)), isA<Satisfied>());
        },
      );

      test('$name on another port is written as [$name]:port', () async {
        await step.apply(contextOf(name: name, port: '2222'));

        expect(held(), '[$name]:2222 $newKey\n');
        expect(findsUnder('[$name]:2222'), isTrue);
      });
    }

    test('THE INNOCENT NEIGHBOUR: the address of one machine is not the name of another', () async {
      hold('$ipv4 $otherKey\n$ipv6 $otherKey\n');

      await step.apply(contextOf());

      expect(held(), '$ipv4 $otherKey\n$ipv6 $otherKey\n$host $newKey\n');
    });
  });

  test('a key answer with a comment is written without it', () async {
    await step.apply(contextOf(key: '$newKey operator@somewhere'));

    expect(held(), '$host $newKey\n');
  });

  test('a dry run shows the file it would make and writes nothing', () async {
    hold('$host $oldKey\n');

    final StepPlan plan = await step.plan(contextOf());

    expect(plan, isA<DiffPlan>());
    expect((plan as DiffPlan).before, '$host $oldKey\n');
    expect(plan.after, '$host $newKey\n');
    expect(held(), '$host $oldKey\n');
  });

  test('an undo puts back the file the run found, old key included', () async {
    hold('$host $oldKey\nother.example.org $otherKey\n');
    final KnownHostsBefore found = await step.capture(contextOf());

    await step.apply(contextOf());
    await step.undo(contextOf(), found);

    expect(held(), '$host $oldKey\nother.example.org $otherKey\n');
  });

  test('an undo takes away a known_hosts the run made, and only that', () async {
    final KnownHostsBefore found = await step.capture(contextOf());

    await step.apply(contextOf());
    await step.undo(contextOf(), found);

    expect(File(knownHosts).existsSync(), isFalse);
    expect(Directory('${scratch.path}/.ssh').existsSync(), isTrue);
  });

  test('an undo over a file that was never read leaves it as it stands', () async {
    hold('$host $oldKey\n');

    await step.undo(contextOf(), const KnownHostsBefore.unread());

    expect(held(), '$host $oldKey\n');
  });

  group('what the row names must be one machine and one key', () {
    Future<void> refused(StepContext context, String mentions) async {
      final CheckResult answer = await step.check(context);
      expect(answer, isA<Blocked>(), reason: '$answer');
      expect((answer as Blocked).reason, contains(mentions));
      expect(File(knownHosts).existsSync(), isFalse);
    }

    test('THE PLANTED DEFECT: an answer this run does not hold is refused by name', () async {
      await refused(contextOf(name: null), 'slave_ssh_host');
      await refused(contextOf(port: null), 'slave_ssh_port');
      await refused(contextOf(key: null), 'slave_host_key');
    });

    test(
      'THE PLANTED DEFECT: a name that is a pattern would trust the key for other machines',
      () async {
        for (final String pattern in <String>[
          '*.example.org',
          'host-?.example.org',
          '$host,203.0.113.7',
          '!$host',
          '$host other.example.org',
          '-$host',
          '[2001:db8::7]',
          'fe80::1%eth0',
          '2001:db8::7,203.0.113.7',
          '2001:db8::g',
          '1::2::3',
          '$host:2222',
        ]) {
          await refused(contextOf(name: pattern), 'slave_ssh_host');
        }
      },
    );

    test('THE PLANTED DEFECT: something that is not a port number is refused', () async {
      // A port that the line could not carry as ssh spells it would write a line ssh never reads and
      // report the machine registered.
      for (final String notAPort in <String>[
        '',
        '0',
        '65536',
        '99999',
        '100000',
        '22x',
        '-1',
        '0x16',
        '022',
        '2 2',
        '22.0',
        'ssh',
      ]) {
        await refused(contextOf(port: notAPort), 'slave_ssh_port');
      }
    });

    test('THE INNOCENT CASE: the lowest and the highest port are taken', () async {
      await step.apply(contextOf(port: '1'));
      await step.apply(contextOf(port: '65535'));

      expect(held(), '[$host]:1 $newKey\n[$host]:65535 $newKey\n');
    });

    test('THE PLANTED DEFECT: something that is not one public key is refused', () async {
      for (final String notAKey in <String>[
        'hello',
        'ssh-ed25519',
        'ssh-ed25519 not*base64',
        'Ssh-Ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHsiaTSWroVqO3IfaD8EIGgOvfaBanJEm+563U/6zktx',
        '$newKey\n$oldKey',
      ]) {
        await refused(contextOf(key: notAKey), 'slave_host_key');
      }
    });
  });

  test('the step reads the account under the answer the key installer reads it under', () {
    expect(InstallKnownHost.answers, same(InstallAuthorizedKey.answers));
    expect(InstallKnownHost.arguments.map((ArgumentSpec spec) => spec.name), <String>[
      'host_answer',
      'host_port_answer',
      'host_public_key_answer',
    ]);
  });
}

/// The shell of a machine whose account database says the account lives in [home], and which runs
/// everything else for real.
final class _AccountAt implements Shell {
  const _AccountAt(this.home);

  final String home;

  static const RealShell _real = RealShell(elevation: Elevation.unconfigured());

  @override
  Future<CommandResult> run(Command command) async {
    if (command.argv.join(' ') == 'getent passwd $operatorUser') {
      return CommandResult(
        exitCode: 0,
        stdout: '$operatorUser:x:1000:1000::$home:/bin/bash\n',
        stderr: '',
        elapsed: Duration.zero,
      );
    }
    return _real.run(command);
  }
}
