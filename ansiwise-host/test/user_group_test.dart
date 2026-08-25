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

  test('THE PLANTED DEFECT: an undo leaves a membership it could not read alone', () async {
    // capture answers "the account was already in the group", and its false half is what runs
    // `gpasswd --delete`. Answered false out of a refused `id -G`, the clean-up after some other
    // step failed takes away a membership the account already had.
    final HostMachine machine = HostMachine();
    machine.shell
      ..answers('getent passwd $operatorUser', '$operatorUser:x:1000:1000::$operatorHome:/bin/sh\n')
      ..answers('getent group operators', 'operators:x:3000:\n')
      ..fails('id -G $operatorUser', stderr: 'id: $operatorUser: no such user');

    final StepContext context = machine.contextFor(under);
    final bool captured = await step.capture(context);
    await step.undo(context, captured);

    expect(captured, isTrue, reason: 'a reading nobody took must not read as "not a member"');
    expect(
      machine.changing,
      isEmpty,
      reason: 'the undo ran gpasswd --delete over a membership it never measured',
    );
    expect(machine.said.join('\n'), contains('could not be read'));
  });

  test('THE INNOCENT CASE: a membership this run really gave is taken back', () async {
    // The state the refusal above must not swallow: the reading answers, the account was not a
    // member, so the undo takes out exactly what this step put in.
    final HostMachine machine = HostMachine();
    machine.shell
      ..answers('getent passwd $operatorUser', '$operatorUser:x:1000:1000::$operatorHome:/bin/sh\n')
      ..answers('getent group operators', 'operators:x:3000:\n')
      ..answers('id -G $operatorUser', '1000 27\n');

    final StepContext context = machine.contextFor(under);
    final bool captured = await step.capture(context);
    await step.undo(context, captured);

    expect(captured, isFalse);
    expect(machine.changing, contains('gpasswd --delete $operatorUser operators'));
  });

  test('the account is appended to the group, and the run says when it takes effect', () async {
    // The membership is read again from the machine rather than assumed from the command having
    // returned zero, and what the run says about it matters as much: it takes effect at the next
    // login, so an operator typing the next command in the session already open still meets the
    // refusal.
    final HostMachine machine = HostMachine();
    machine.shell
      ..answers('getent passwd $operatorUser', '$operatorUser:x:1000:1000::$operatorHome:/bin/sh\n')
      ..answers('getent group operators', 'operators:x:3000:\n')
      ..answers('id -G $operatorUser', '1000 27\n')
      ..changes('usermod --append --groups operators $operatorUser', () {
        machine.shell.answers('id -G $operatorUser', '1000 27 3000\n');
      });

    final StepContext context = machine.contextFor(under);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);
    expect(await step.check(context), isA<Satisfied>());
    expect(machine.said.join('\n'), contains('next login'));
  });

  // THE ROW MAY STATE A NUMBER, and until this was held it could not. A group that belongs to
  // something outside this machine is known to it by number only — a process elsewhere writes a
  // file onto the host carrying a group number, and the host was never told a name. The membership
  // used to be read out of `groups`, which prints NAMES, so a row stating a number was compared
  // against a list the number can never appear in: `usermod` succeeded, the account WAS a member,
  // and the framework reported "the step ran and the machine is still not in the state it produces"
  // on that run and on every run after it.
  test('a row naming the group by number reads the membership it produced', () async {
    const AddUserToGroup byNumber = AddUserToGroup(group: '65532');
    final HostMachine machine = HostMachine();
    machine.shell
      ..answers('getent passwd $operatorUser', '$operatorUser:x:1000:1000::$operatorHome:/bin/sh\n')
      ..answers('getent group 65532', 'nonroot:x:65532:\n')
      ..answers('id -G $operatorUser', '1000 27\n')
      ..changes('usermod --append --groups 65532 $operatorUser', () {
        machine.shell.answers('id -G $operatorUser', '1000 27 65532\n');
      });

    final StepContext context = machine.contextFor(under);

    expect(await byNumber.check(context), isA<Ready>());
    await byNumber.apply(context);
    expect(
      await byNumber.check(context),
      isA<Satisfied>(),
      reason:
          'the machine answers the membership as the number 65532 under the name nonroot, and the '
          'row said the number — reading only the names would miss what the step just did',
    );
  });

  test('a group no machine carries is refused before usermod is asked', () async {
    final HostMachine machine = HostMachine()
      ..shell.answers(
        'getent passwd $operatorUser',
        '$operatorUser:x:1000:1000::$operatorHome:/bin/sh\n',
      )
      ..shell.fails('getent group operators');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('nothing for'));
    expect(machine.changing, isEmpty);
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
