/// A directory a real account on this machine has to be able to write into.
///
///   dart test test/hand_directory_to_account_test.dart
///
/// WHAT IS BEING HELD is that the account is a NAME all the way through and the NUMBERS ARE READ
/// OFF THE MACHINE. Which number an installation gave its operator is that machine's own fact —
/// 1000 on one, 1001 on the next — so a program file that wrote a number would be right on one
/// machine and silently wrong on the next, and the directory would end up belonging to somebody
/// else while everything reported itself done. This is the whole difference from `create_directory`,
/// whose owner is a number because the process writing there is a container carrying the number its
/// image runs as, for which the machine has no account at all.
///
/// AN ACCOUNT THIS MACHINE DOES NOT CARRY IS A REFUSAL. It is the case worth being sure about: a
/// step that guessed would hand the directory to a number nobody has, which is a directory nobody
/// can write, and the run would report it done.
///
/// THE UNDO IS THE OTHER HALF, and it is the sibling's: a directory this run MADE is removed; one it
/// found and only handed over is put back to the numbers it was carrying; and one it could not read
/// before it acted is left standing.
library;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/src/steps/host/create_directory.dart';
import 'package:ansiwise_host/src/steps/host/hand_directory_to_account.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// 0770 and 0755 as the machine stores them, which is what a program row writes.
const int ownAndGroupOnly = 504;

/// See [ownAndGroupOnly].
const int everybodyReads = 493;

void main() {
  const StepName under = StepName('hand_directory_to_account');
  const String path = '/var/lib/ansiwise';
  const HandDirectoryToAccount step = HandDirectoryToAccount(
    path: path,
    accountAnswer: 'operator_user',
    mode: ownAndGroupOnly,
  );

  const String asked = 'stat -c %u %g %f $path';
  const String askedUid = 'id -u $operatorUser';
  const String askedGid = 'id -g $operatorUser';

  /// A machine carrying [operatorUser] as the numbers this installation gave it.
  HostMachine carrying({int uid = 1000, int gid = 1000}) => HostMachine()
    ..shell.answers(askedUid, '$uid')
    ..shell.answers(askedGid, '$gid');

  test('a machine with nothing there has work, and the plan names the directory', () async {
    final HostMachine machine = carrying()..shell.fails(asked);

    expect(await step.check(machine.contextFor(under)), isA<Ready>());
    expect((await step.plan(machine.contextFor(under)) as ArgvPlan).argv, <String>[
      'mkdir',
      '-p',
      path,
    ]);
    expect(machine.changing, isEmpty);
  });

  test('the directory is made, handed over by the NAME resolved, and set to the mode', () async {
    final HostMachine machine = carrying()..shell.fails(asked);

    await step.apply(machine.contextFor(under));

    expect(machine.changing, <String>['chown 1000:1000 $path', 'chmod 0770 $path']);
    expect(
      machine.files.modes[path],
      ownAndGroupOnly,
      reason: 'the directory is made with the mode the row states and not with a tool default',
    );
  });

  // THE CASE THE STEP EXISTS FOR. The same row, the same answer, the same account name — and a
  // machine that gave that account a different number. A program file carrying 1000 would leave
  // this directory belonging to whoever holds 1000 here, and say it handed it over.
  test('the numbers come from the machine, so a second one gets its own', () async {
    final HostMachine other = carrying(uid: 1001, gid: 1001)..shell.fails(asked);

    await step.apply(other.contextFor(under));

    expect(other.changing, <String>['chown 1001:1001 $path', 'chmod 0770 $path']);
  });

  test('a directory already at the account and the mode has nothing to do', () async {
    final HostMachine machine = carrying()
      ..shell.answers(asked, '1000 1000 ${_directoryAt(ownAndGroupOnly)}');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect(
      (answer as Satisfied).because,
      allOf(contains(operatorUser), contains('1000:1000'), contains('0770')),
    );
    expect(machine.changing, isEmpty);
  });

  // What every one of these directories actually looks like on a machine this platform installed:
  // an installation program ran as root and made it, and the account the Manager reaches the
  // machine as cannot write a byte into it.
  test('a directory owned by root has work, and the plan names the handover', () async {
    final HostMachine machine = carrying()
      ..shell.answers(asked, '0 0 ${_directoryAt(everybodyReads)}');

    expect(await step.check(machine.contextFor(under)), isA<Ready>());
    expect((await step.plan(machine.contextFor(under)) as ArgvPlan).argv, <String>[
      'chown',
      '1000:1000',
      path,
    ]);
  });

  test('a directory at the right account and the wrong mode has the mode named', () async {
    final HostMachine machine = carrying()
      ..shell.answers(asked, '1000 1000 ${_directoryAt(everybodyReads)}');

    expect(await step.check(machine.contextFor(under)), isA<Ready>());
    expect((await step.plan(machine.contextFor(under)) as ArgvPlan).argv, <String>[
      'chmod',
      '0770',
      path,
    ]);
  });

  // A number nobody has is a directory nobody can write, and a run that did it would report it
  // done. The refusal has to come before anything is written, which is why it is the check that
  // carries it and not the apply.
  test('an account this machine does not carry is refused before anything is written', () async {
    final HostMachine machine = HostMachine()
      ..shell.fails(askedUid, stderr: 'id: ‘$operatorUser’: no such user')
      ..shell.fails(askedGid, stderr: 'id: ‘$operatorUser’: no such user')
      ..shell.fails(asked);

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect(
      (answer as Blocked).reason,
      allOf(contains(operatorUser), contains('no such user')),
      reason: 'the operator reads which account was asked for and what the machine said',
    );
    expect(await step.plan(machine.contextFor(under)), isA<NotKnownYetPlan>());
    expect(machine.changing, isEmpty);
  });

  // The answer standing empty is the other half of the same case, and it is a different fault: the
  // installation never stated which account this is, rather than the machine not having it.
  test('an answer naming no account is refused, and says which answer', () async {
    final HostMachine machine = carrying()..shell.fails(asked);

    final CheckResult answer = await step.check(
      machine.contextFor(
        under,
        Arguments.none,
        hostAnswering(<String, Object>{'operator_user': ''}),
      ),
    );
    expect((answer as Blocked).reason, allOf(contains('operator_user'), contains(path)));
    expect(machine.changing, isEmpty);
  });

  test('something that is not a directory is refused, and says what it is', () async {
    final HostMachine file = carrying()..shell.answers(asked, '0 0 81a4');
    final CheckResult aboutFile = await step.check(file.contextFor(under));
    expect((aboutFile as Blocked).reason, allOf(contains(path), contains('a regular file')));

    final HostMachine link = carrying()..shell.answers(asked, '0 0 a1ff');
    final CheckResult aboutLink = await step.check(link.contextFor(under));
    expect((aboutLink as Blocked).reason, contains('a symbolic link'));

    expect(file.changing, isEmpty);
    expect(link.changing, isEmpty);
  });

  test('a reading that was not taken is never a done, in either of its shapes', () async {
    final HostMachine denied = carrying()
      ..shell.fails(asked, stderr: "stat: cannot stat '$path': Permission denied");
    expect(await step.check(denied.contextFor(under)), isA<Ready>());

    // Exit zero and nothing on the output is the shape that reads like an answer and is none.
    final HostMachine silent = carrying()..shell.answers(asked, '');
    expect(await step.check(silent.contextFor(under)), isA<Ready>());
  });

  test('the undo removes only a directory this run made, and never recursively', () async {
    final HostMachine machine = carrying()..shell.fails(asked);

    final DirectoryBefore before = await step.capture(machine.contextFor(under));
    expect(before.absent, isTrue);

    await step.undo(machine.contextFor(under), before);
    expect(machine.changing, <String>['rmdir $path']);
  });

  test('the undo puts back the numbers a directory it found was carrying', () async {
    final HostMachine machine = carrying()
      ..shell.answers(asked, '0 0 ${_directoryAt(everybodyReads)}');

    final DirectoryBefore before = await step.capture(machine.contextFor(under));
    await step.undo(machine.contextFor(under), before);

    expect(machine.changing, <String>['chown 0:0 $path', 'chmod 0755 $path']);
  });

  test('the undo leaves a path standing whose reading was refused', () async {
    final HostMachine machine = carrying()
      ..shell.fails(asked, stderr: "stat: cannot stat '$path': Permission denied")
      ..files.contents[path] = '';

    final DirectoryBefore before = await step.capture(machine.contextFor(under));
    expect(before.refusal, isNotNull);

    await expectLater(
      step.undo(machine.contextFor(under), before),
      throwsA(isA<StateError>()),
      reason:
          'removing a path whose owner was never measured takes away what somebody else put '
          'there',
    );
    expect(machine.changing, isEmpty);
  });

  // THE KIND IS WHAT KEEPS THE TWO STEPS APART, and it is checked before a run starts rather than
  // by anything reading the machine. `answerName` means the row writes the NAME OF AN ANSWER and the
  // account is read out of the run under it; plain text would let a row write the account itself,
  // which is the same installation fact stated twice and free to drift, and an integer would be the
  // sibling step wearing this one's name.
  test('the account is the name of an answer, and the mode is a whole number', () {
    expect(
      <String, ArgumentKind>{
        for (final ArgumentSpec spec in HandDirectoryToAccount.arguments) spec.name: spec.kind,
      },
      <String, ArgumentKind>{
        'path': ArgumentKind.text,
        'account_answer': ArgumentKind.answerName,
        'mode': ArgumentKind.integer,
      },
    );
  });
}

/// [mode] as `stat -c %f` renders a directory carrying it.
String _directoryAt(int mode) => (0x4000 | mode).toRadixString(16);
