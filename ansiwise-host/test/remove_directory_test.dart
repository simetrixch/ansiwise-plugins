/// A directory the platform no longer uses, removed with everything in it.
///
///   dart test test/remove_directory_test.dart
///
/// WHAT IS BEING HELD: absent is done, so the row can stand in a program every machine runs; and a
/// path that is relative, walks with "." or "..", or stands fewer than two levels deep is refused
/// before the machine is asked anything, because removing `/srv` or `/` takes the machine with it.
library;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/src/steps/host/remove_directory.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

void main() {
  const StepName under = StepName('remove_directory');
  const String path = '/srv/ansiwise-catalog';

  test(
    'the directory has work, the removal takes it, and a second run finds nothing to do',
    () async {
      final HostMachine machine = HostMachine();
      machine.files.directories.add(path);
      const RemoveDirectory step = RemoveDirectory(path: path, elevated: true);

      expect(await step.check(machine.contextFor(under)), isA<Ready>());
      expect((await step.plan(machine.contextFor(under)) as ArgvPlan).argv, <String>[
        'rm',
        '-rf',
        '--',
        path,
      ]);
      await step.apply(machine.contextFor(under));
      expect(machine.files.deleted, <String>[path]);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    },
  );

  test('a machine without it has nothing to do', () async {
    final HostMachine machine = HostMachine();
    const RemoveDirectory step = RemoveDirectory(path: path);

    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.files.deleted, isEmpty);
  });

  test(
    'refuses a relative path, a walking segment and a path fewer than two levels deep',
    () async {
      for (final String refused in <String>[
        'srv/ansiwise-catalog',
        '/srv/../etc',
        '/srv/./x',
        '/srv',
        '/',
      ]) {
        final HostMachine machine = HostMachine(
          files: FakeFiles(<String, String>{'$refused/a': 'b'}),
        );
        expect(
          await RemoveDirectory(path: refused).check(machine.contextFor(under)),
          isA<Blocked>(),
          reason: refused,
        );
      }
    },
  );
}
