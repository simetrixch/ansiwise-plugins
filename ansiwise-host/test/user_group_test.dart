import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Putting the answered account into a group of the machine.
///
/// Which group is a program row's to say — the tool that guards something behind a group is the one
/// that knows its name — and the account is answered, never written into a program file.
void main() {
  const StepName under = StepName('under_test');
  const AddUserToGroup step = AddUserToGroup(group: 'operators');

  test('the account is appended to the group, and the run says when it takes effect', () async {
    // The membership is read again from the machine rather than assumed from the command having
    // returned zero, and what the run says about it matters as much: it takes effect at the next
    // login, so an operator typing the next command in the session already open still meets the
    // refusal.
    final HostMachine machine = HostMachine();
    machine.shell
      ..answers('getent passwd $operatorUser', '$operatorUser:x:1000:1000::$operatorHome:/bin/sh\n')
      ..answers('groups $operatorUser', '$operatorUser : $operatorUser sudo\n')
      ..changes('usermod --append --groups operators $operatorUser', () {
        machine.shell.answers(
          'groups $operatorUser',
          '$operatorUser : $operatorUser sudo operators\n',
        );
      });

    final StepContext context = machine.contextFor(under);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);
    expect(await step.check(context), isA<Satisfied>());
    expect(machine.said.join('\n'), contains('next login'));
  });

  test('a machine carrying no such account is refused', () async {
    // Refused and not created. An account this run invented would hold the group and none of the
    // credentials the operator reaches the machine through, and the real account would still be
    // outside the group with nothing reporting it.
    final HostMachine machine = HostMachine()..shell.fails('getent passwd $operatorUser');
    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('no account'));
  });
}
