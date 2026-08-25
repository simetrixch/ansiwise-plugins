import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Taking off a machine what nothing on it depends on any more.
///
/// **What the step is asked, and what it may conclude.** apt is asked with `--dry-run` what it
/// WOULD remove, and the count of `Remv ` lines is the answer. Zero is a real answer: apt exits zero
/// and names no such line on a machine that carries nothing unused. A NON-ZERO exit is not an
/// answer at all — another process holding the lock, package lists that are broken, no apt on the
/// machine — and folded into the same zero it became "nothing on this machine is unused", which is
/// a statement about the machine composed out of a reading nobody took.
void main() {
  const StepName under = StepName('remove_unused_packages');
  const RemoveUnusedPackages step = RemoveUnusedPackages();
  const String asking = 'apt-get --dry-run autoremove';

  test(
    'THE PLANTED DEFECT: an apt that would not answer is not a machine with nothing unused',
    () async {
      final HostMachine machine = HostMachine();
      machine.shell.fails(asking, stderr: 'E: Could not get lock /var/lib/dpkg/lock-frontend');

      final CheckResult answer = await step.check(machine.contextFor(under));

      expect(answer, isA<Blocked>(), reason: '$answer');
      expect(machine.changing, isEmpty);
    },
  );

  test('THE PLANTED DEFECT: the dry run says so rather than planning a removal', () async {
    final HostMachine machine = HostMachine();
    machine.shell.fails(asking, stderr: 'E: Unable to locate package lists');

    expect(await step.plan(machine.contextFor(under)), isA<NothingPlan>());
  });

  test('THE INNOCENT CASE: an apt that answers and names nothing is satisfied', () async {
    // The state the refusal must not swallow, and it is the ordinary one on a converged machine.
    final HostMachine machine = HostMachine();
    machine.shell.answers(asking, 'Reading package lists...\nDone\n');

    final CheckResult answer = await step.check(machine.contextFor(under));

    expect(answer, isA<Satisfied>(), reason: answer is Blocked ? answer.reason : '$answer');
  });

  test('THE INNOCENT CASE: an apt that names packages is work to do', () async {
    final HostMachine machine = HostMachine();
    machine.shell.answers(asking, 'Remv linux-headers-6.8.0-31 [6.8.0-31.31]\nRemv libfoo1\n');

    expect(await step.check(machine.contextFor(under)), isA<Ready>());
    expect(machine.said.join('\n'), isNot(contains('0 packages')));
  });
}
