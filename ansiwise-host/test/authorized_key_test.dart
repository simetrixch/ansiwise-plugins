import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The pair that turns a machine reached with a password into one reached with a key: the step that
/// installs the key, and the gate that proves the login it makes possible.
void main() {
  test('the gate proves the key that was installed, not a second one', () {
    // A second pair of names would let the gate pass on a key nobody installed: it would read an
    // account and a key the run never wrote, find them in order, and report a login that was never
    // made possible. It reads what the install wrote, so it reads it under the same two names.
    expect(RequireKeyLoginPossible.answers, same(InstallAuthorizedKey.answers));
  });

  test('the gate asks sshd AS ROOT, or it cannot read what sshd reads', () async {
    // Measured on a machine before it was fixed. `sshd -T` does not skip a configuration file it
    // may not read — it refuses the whole answer — and Ubuntu's installer drops in a root-only file.
    // So the check reported "Permission denied" and could say nothing about a login it had every
    // other means to judge.
    //
    // Observing AND elevated: running as root does not make a command change anything, so this stays
    // something a dry run may perform. The two flags are independent for exactly this case.
    final HostMachine machine = HostMachine();
    machine.shell.answers('sshd -T', 'pubkeyauthentication yes\npermitrootlogin no\n');
    machine.files.contents['/home/subject/.ssh/authorized_keys'] = 'ssh-ed25519 AAAA key\n';

    await const RequireKeyLoginPossible().check(
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
}
