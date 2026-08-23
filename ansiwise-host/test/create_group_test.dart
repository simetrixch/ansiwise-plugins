/// A group that has to be on the machine before an account can be named a member of it.
///
///   dart test test/create_group_test.dart
///
/// WHAT IS BEING HELD is that the NUMBER decides and the name does not. A file written onto the host
/// by a process running elsewhere carries a group number and no name — the host was never told one —
/// so a group already carrying that number is the thing, whatever it happens to be called. A step
/// that went by the name would make a second group for a number that already had one, and admit
/// nobody to anything while reporting success.
library;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/src/steps/host/create_group.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

void main() {
  const StepName under = StepName('create_group');
  const CreateGroup step = CreateGroup(name: 'nonroot', gid: '65532');
  // `getent group` answers the same line whether it was asked by name or by number, which is why
  // one reader serves both of this step's questions.
  const String byNumber = 'getent group 65532';
  const String byName = 'getent group nonroot';

  test('a machine with no such group is asked to make one', () async {
    final HostMachine machine = HostMachine()
      ..shell.fails(byNumber)
      ..shell.fails(byName);

    expect(await step.check(machine.contextFor(under)), isA<Ready>());
    expect(await step.plan(machine.contextFor(under)), isA<StepPlan>());
  });

  test('the group is made with the number, and the number is what is asked for', () async {
    final HostMachine machine = HostMachine()
      ..shell.fails(byNumber)
      ..shell.fails(byName);

    await step.apply(machine.contextFor(under));

    expect(machine.changing.single, 'groupadd --gid 65532 nonroot');
  });

  test('a group already carrying the number is the group, under any name', () async {
    final HostMachine machine = HostMachine()..shell.answers(byNumber, 'systemd-journal:x:65532:');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect(answer, isA<Satisfied>());
    expect(
      (answer as Satisfied).because,
      contains('systemd-journal'),
      reason:
          'the machine already admits that number and says so by the name it uses — making a second '
          'group for it would give one number two names and admit nobody to anything',
    );
    expect(machine.changing, isEmpty);
  });

  test('the group this installation asked for is reported plainly when it is there', () async {
    final HostMachine machine = HostMachine()..shell.answers(byNumber, 'nonroot:x:65532:digi1');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Satisfied).because, 'nonroot carries 65532 on this machine');
  });

  // THE NAME TAKEN BY ANOTHER NUMBER, which `groupadd` would fail on anyway — the point of catching
  // it here is that the step can say WHICH two groups are in conflict, where the tool says only
  // that the name is in use.
  test('a name already carrying another number is refused, naming both', () async {
    final HostMachine machine = HostMachine()
      ..shell.fails(byNumber)
      ..shell.answers(byName, 'nonroot:x:1500:');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, allOf(contains('1500'), contains('65532')));
    expect(machine.changing, isEmpty);
  });

  test('the undo removes only a group this run made', () async {
    final HostMachine kept = HostMachine();
    await step.undo(kept.contextFor(under), true);
    expect(kept.changing, isEmpty);

    final HostMachine made = HostMachine();
    await step.undo(made.contextFor(under), false);
    expect(made.changing.single, 'groupdel nonroot');
  });
}
