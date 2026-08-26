/// A directory a workload requires, left at the numbers that workload writes as.
///
///   dart test test/create_directory_test.dart
///
/// WHAT IS BEING HELD is that the OWNER IS A NUMBER all the way through. The process that writes
/// into such a directory runs inside a container image and carries the number that image runs as,
/// and the machine has no account for it — so `install -d -o 65532` refuses that number and
/// `chown 65532:65532` takes it. The kind of the two arguments keeps a name out before a run
/// starts, and the step's own check is what proves the three values really landed on the machine.
///
/// THE UNDO IS THE OTHER HALF. A directory this run MADE is removed; one it found and only
/// re-owned is put back to what it was carrying; and one it could not read before it acted is left
/// standing, because removing that one takes away what somebody else put there.
library;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/src/steps/host/create_directory.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// 0770 and 0755 as the machine stores them, which is what a program row writes.
const int ownAndGroupOnly = 504;

/// See [ownAndGroupOnly].
const int everybodyReads = 493;

void main() {
  const StepName under = StepName('create_directory');
  const String path = '/var/lib/example';
  const String parent = '/var/lib';
  const CreateDirectory step = CreateDirectory(
    path: path,
    owner: 65532,
    group: 65532,
    mode: ownAndGroupOnly,
    elevated: true,
  );

  const String asked = 'stat -c %u %g %f $path';
  const String listed = 'ls -A -- $parent';

  test('a machine with nothing there has work, and the plan names the directory', () async {
    final HostMachine machine = HostMachine()..shell.fails(asked);

    expect(await step.check(machine.contextFor(under)), isA<Ready>());
    expect((await step.plan(machine.contextFor(under)) as ArgvPlan).argv, <String>[
      'mkdir',
      '-p',
      path,
    ]);
    expect(machine.changing, isEmpty);
  });

  test('the directory is made, handed over by NUMBER, and set to the mode', () async {
    final HostMachine machine = HostMachine()..shell.fails(asked);

    await step.apply(machine.contextFor(under));

    expect(machine.changing, <String>['chown 65532:65532 $path', 'chmod 0770 $path']);
    expect(
      machine.files.modes[path],
      ownAndGroupOnly,
      reason: 'the directory is made with the mode the row states and not with a tool default',
    );
  });

  test('a directory already at the three the row states has nothing to do', () async {
    final HostMachine machine = HostMachine()
      ..shell.answers(asked, '65532 65532 ${_directoryAt(ownAndGroupOnly)}');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Satisfied).because, allOf(contains('65532:65532'), contains('0770')));
    expect(machine.changing, isEmpty);
  });

  // The case this step exists for: something else on the machine reached the path first and made it
  // root-owned at 0755. Nothing about that directory looks wrong, and a workload started against it
  // cannot write a byte into it.
  test('a directory owned by root has work, and the plan names the handover', () async {
    final HostMachine machine = HostMachine()
      ..shell.answers(asked, '0 0 ${_directoryAt(everybodyReads)}');

    expect(await step.check(machine.contextFor(under)), isA<Ready>());
    expect((await step.plan(machine.contextFor(under)) as ArgvPlan).argv, <String>[
      'chown',
      '65532:65532',
      path,
    ]);
  });

  test('a directory at the right numbers and the wrong mode has the mode named', () async {
    final HostMachine machine = HostMachine()
      ..shell.answers(asked, '65532 65532 ${_directoryAt(everybodyReads)}');

    expect(await step.check(machine.contextFor(under)), isA<Ready>());
    expect((await step.plan(machine.contextFor(under)) as ArgvPlan).argv, <String>[
      'chmod',
      '0770',
      path,
    ]);
  });

  // A regular file at the path would take the chown and the chmod and then read back with exactly
  // the owner, the group and the mode the row asked for — only the kind bits say it is not a
  // directory, and whatever mounts it as one goes on failing. A symbolic link fails in the other
  // direction: `chown` and `chmod` follow one, so they would reach whatever it points at.
  test('something that is not a directory is refused, and says what it is', () async {
    final HostMachine file = HostMachine()..shell.answers(asked, '0 0 81a4');
    final CheckResult aboutFile = await step.check(file.contextFor(under));
    expect((aboutFile as Blocked).reason, allOf(contains(path), contains('a regular file')));

    final HostMachine link = HostMachine()..shell.answers(asked, '0 0 a1ff');
    final CheckResult aboutLink = await step.check(link.contextFor(under));
    expect((aboutLink as Blocked).reason, contains('a symbolic link'));

    expect(file.changing, isEmpty);
    expect(link.changing, isEmpty);
  });

  test('a reading that was not taken is never a done, in either of its shapes', () async {
    final HostMachine denied = HostMachine()
      ..shell.fails(asked, stderr: "stat: cannot stat '$path': Permission denied");
    expect(await step.check(denied.contextFor(under)), isA<Ready>());

    // Exit zero and nothing on the output is the shape that reads like an answer and is none.
    final HostMachine silent = HostMachine()..shell.answers(asked, '');
    expect(await step.check(silent.contextFor(under)), isA<Ready>());
  });

  test('the undo removes only a directory this run made, and never recursively', () async {
    final HostMachine machine = HostMachine()
      ..shell.fails(asked)
      ..shell.answers(listed, '');

    final DirectoryBefore before = await step.capture(machine.contextFor(under));
    expect(before.absent, isTrue);

    await step.undo(machine.contextFor(under), before);
    expect(
      machine.changing,
      <String>['rmdir $path'],
      reason:
          'a workload writes into this directory between the apply and the undo, and rmdir refuses '
          'one that is not empty where rm -r would take that workload data with it',
    );
  });

  test('the undo reports a directory it made that something has written into', () async {
    final HostMachine machine = HostMachine()
      ..shell.fails(asked)
      ..shell.answers(listed, '')
      ..shell.fails('rmdir $path', stderr: "rmdir: failed to remove '$path': Directory not empty");

    final DirectoryBefore before = await step.capture(machine.contextFor(under));

    await expectLater(
      step.undo(machine.contextFor(under), before),
      throwsA(isA<CommandFailed>()),
      reason:
          'the unwind writes "taken back" for an undo that returns, and this one left the '
          'directory standing',
    );
  });

  test('the undo puts back what a directory it found was carrying', () async {
    final HostMachine machine = HostMachine()
      ..shell.answers(asked, '0 0 ${_directoryAt(everybodyReads)}');

    final DirectoryBefore before = await step.capture(machine.contextFor(under));
    expect(<int?>[before.owner, before.group, before.mode], <int>[0, 0, everybodyReads]);

    await step.undo(machine.contextFor(under), before);
    expect(machine.changing, <String>['chown 0:0 $path', 'chmod 0755 $path']);
  });

  test('the undo leaves a path standing whose parent could not be read', () async {
    final HostMachine machine = HostMachine()
      ..shell.fails(asked)
      ..shell.fails(listed, stderr: "ls: cannot open directory '$parent': Permission denied")
      ..files.directories.add(parent);

    final DirectoryBefore before = await step.capture(machine.contextFor(under));
    expect(before.refusal, contains('Permission denied'));

    await expectLater(step.undo(machine.contextFor(under), before), throwsStateError);
    expect(machine.changing, isEmpty);
  });

  test('the undo leaves a path the parent shows was already there', () async {
    final HostMachine machine = HostMachine()
      ..shell.fails(asked, stderr: "stat: cannot stat '$path': Permission denied")
      ..shell.answers(listed, 'example\nother\n');

    final DirectoryBefore before = await step.capture(machine.contextFor(under));
    expect(before.absent, isFalse);
    expect(before.refusal, contains('stat'));

    await expectLater(step.undo(machine.contextFor(under), before), throwsStateError);
    expect(machine.changing, isEmpty);
  });

  // The measured failure this step was written for: `install -d -o 65532` resolves an owner through
  // the machine's account database and refuses a number no account carries. A TEXT argument would
  // let a row write a name, which no reading of the machine can ever match — `stat -c %u` answers a
  // number — so such a row would be applied on every run and never once be satisfied.
  test('the owner and the group are whole numbers, so a name is refused before a run', () {
    expect(
      <ArgumentKind>[
        for (final ArgumentSpec spec in CreateDirectory.arguments)
          if (spec.name == 'owner' || spec.name == 'group') spec.kind,
      ],
      <ArgumentKind>[ArgumentKind.integer, ArgumentKind.integer],
    );
  });
}

/// What `stat -c %f` prints for a directory carrying [bits]: the kind of the thing over its
/// permissions, in hex, exactly as the machine stores the two together.
String _directoryAt(int bits) => (0x4000 | bits).toRadixString(16);
