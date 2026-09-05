import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The pair that turns a machine reached with a password into one reached with a key: the step that
/// installs the key, and the gate that proves the login it makes possible.
///
/// **The key reaches a row by one of two routes, and the cases below are mostly about that.** A
/// person's key is ANSWERED, because the private half is in their keychain and nobody here can
/// produce it. A key minted while the run was going is MEASURED by the row that minted it, because
/// nobody could have been asked for a value that did not exist when the run was started. A row that
/// names both, or neither, means no key at all and is refused rather than installing something.
void main() {
  const String keyLine =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
      'AAAAAAA a-person@their-laptop';
  const String mintedLine =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIO+2B7di7Fis1nNg+vIzqOm4MK0ArFbk'
      'gJzW638kUa0 minted-in-this-run';

  HostMachine machineWithAccount() {
    final HostMachine machine = HostMachine();
    machine.shell.answers(
      'getent passwd $operatorUser',
      '$operatorUser:x:1000:1000::$operatorHome:/bin/bash',
    );
    return machine;
  }

  StepContext contextOf(HostMachine machine, Arguments arguments, {String? answeredKey}) =>
      machine.contextFor(
        const StepName('install_authorized_key'),
        arguments,
        answeredKey == null ? hostAnswers : hostAnswering(<String, Object>{'k': answeredKey}),
      );

  test('the gate proves the key that was installed, not a second one', () {
    // A second way of saying which key is meant would let the gate pass on a key nobody installed:
    // it would read an account and a key the run never wrote, find them in order, and report a
    // login that was never made possible. Both read the account under the same name, and both name
    // the key through the same pair of arguments.
    expect(RequireKeyLoginPossible.answers, same(InstallAuthorizedKey.answers));
    expect(RequireKeyLoginPossible.arguments, containsAll(AuthorizedKeySource.arguments));
    expect(InstallAuthorizedKey.arguments, containsAll(AuthorizedKeySource.arguments));
  });

  test('a key written into the row is installed, which is how a MINTED key gets here', () async {
    // The route a key made during the run takes. Nobody could have answered it: the row that minted
    // it published the value, and the resolver wrote that value into this argument.
    final HostMachine machine = machineWithAccount();
    const InstallAuthorizedKey step = InstallAuthorizedKey(
      key: AuthorizedKeySource(key: mintedLine, answer: null),
    );

    final StepContext context = contextOf(
      machine,
      const Arguments(<String, Object>{'public_key': mintedLine}),
    );
    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    expect(machine.files.contents['$operatorHome/.ssh/authorized_keys'], '$mintedLine\n');
    expect(await step.check(context), isA<Satisfied>());
  });

  test('a key named as an ANSWER is installed, which is how a person\'s key gets here', () async {
    final HostMachine machine = machineWithAccount();
    const InstallAuthorizedKey step = InstallAuthorizedKey(
      key: AuthorizedKeySource(key: null, answer: 'k'),
    );

    final StepContext context = contextOf(machine, Arguments.none, answeredKey: keyLine);
    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    expect(machine.files.contents['$operatorHome/.ssh/authorized_keys'], '$keyLine\n');
  });

  test('a key already in the file is not appended a second time', () async {
    final HostMachine machine = machineWithAccount();
    machine.files.contents['$operatorHome/.ssh/authorized_keys'] = '$keyLine\n';
    const InstallAuthorizedKey step = InstallAuthorizedKey(
      key: AuthorizedKeySource(key: null, answer: 'k'),
    );

    expect(
      await step.check(contextOf(machine, Arguments.none, answeredKey: keyLine)),
      isA<Satisfied>(),
    );
  });

  test('THE PLANTED DEFECT: a row naming NEITHER source installs nothing', () async {
    // Without this the step would read an answer by a name fixed in the package, and a program that
    // never declared it would have the run stop inside the step rather than be refused by the row.
    final HostMachine machine = machineWithAccount();
    const InstallAuthorizedKey step = InstallAuthorizedKey(
      key: AuthorizedKeySource(key: null, answer: null),
    );

    final CheckResult answer = await step.check(contextOf(machine, Arguments.none));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('public_key'));
    expect(machine.files.contents['$operatorHome/.ssh/authorized_keys'], isNull);
  });

  test('THE PLANTED DEFECT: a row naming BOTH sources installs nothing', () async {
    final HostMachine machine = machineWithAccount();
    const InstallAuthorizedKey step = InstallAuthorizedKey(
      key: AuthorizedKeySource(key: mintedLine, answer: 'k'),
    );

    final CheckResult answer = await step.check(
      contextOf(
        machine,
        const Arguments(<String, Object>{'public_key': mintedLine}),
        answeredKey: keyLine,
      ),
    );
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('one key'));
    expect(machine.files.contents['$operatorHome/.ssh/authorized_keys'], isNull);
  });

  test('THE PLANTED DEFECT: an answer this run does not hold is refused by name', () async {
    final HostMachine machine = machineWithAccount();
    const InstallAuthorizedKey step = InstallAuthorizedKey(
      key: AuthorizedKeySource(key: null, answer: 'nobody_declared_this'),
    );

    final CheckResult answer = await step.check(contextOf(machine, Arguments.none));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('nobody_declared_this'));
  });

  test(
    'THE INNOCENT NEIGHBOUR: a key already in the file belonging to somebody else stays',
    () async {
      final HostMachine machine = machineWithAccount();
      machine.files.contents['$operatorHome/.ssh/authorized_keys'] = '$keyLine\n';
      const InstallAuthorizedKey step = InstallAuthorizedKey(
        key: AuthorizedKeySource(key: mintedLine, answer: null),
      );

      final StepContext context = contextOf(
        machine,
        const Arguments(<String, Object>{'public_key': mintedLine}),
      );
      await step.apply(context);

      expect(
        machine.files.contents['$operatorHome/.ssh/authorized_keys'],
        '$keyLine\n$mintedLine\n',
      );
    },
  );

  test('the gate asks sshd AS ROOT, or it cannot read what sshd reads', () async {
    // `sshd -T` does not skip a configuration file it may not read — it refuses the whole answer —
    // and Ubuntu's installer drops in a root-only file. Asked unelevated, the check reports
    // "Permission denied" and can say nothing about a login it has every other means to judge.
    //
    // Observing AND elevated: running as root does not make a command change anything, so this stays
    // something a dry run may perform. The two flags are independent for exactly this case.
    final HostMachine machine = HostMachine();
    machine.shell.answers('sshd -T', 'pubkeyauthentication yes\npermitrootlogin no\n');
    machine.files.contents['/home/subject/.ssh/authorized_keys'] = 'ssh-ed25519 AAAA key\n';

    await const RequireKeyLoginPossible(
      key: AuthorizedKeySource(key: null, answer: 'operator_public_key'),
    ).check(
      machine.contextFor(
        const StepName('under_test'),
        Arguments.none,
        const Arguments(<String, Object>{
          'operator_user': 'subject',
          'operator_public_key': 'ssh-ed25519 AAAA key',
        }),
      ),
    );

    final Command asked = machine.shell.commands.firstWhere((Command c) => c.executable == 'sshd');
    expect(asked.elevated, isTrue, reason: 'it reads files only root may read');
    expect(asked.observes, isTrue, reason: 'and it still only looks, so a dry run may perform it');
  });

  test('the gate refuses where the row names no key, rather than proving nothing', () async {
    final HostMachine machine = HostMachine();
    machine.shell.answers('sshd -T', 'pubkeyauthentication yes\n');

    final CheckResult answer = await const RequireKeyLoginPossible(
      key: AuthorizedKeySource(key: null, answer: null),
    ).check(machine.contextFor(const StepName('under_test')));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('public_key'));
  });
}
