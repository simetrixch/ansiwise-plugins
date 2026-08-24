import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Where the volumes land: the mount, the directory, and the link the volume provider writes
/// through.
void main() {
  const StepName under = StepName('under_test');
  const String storageMount = '/mnt/data';
  const String storageSubdirectory = '$storageMount/volumes';

  /// The path the cluster's volume provider really writes through, as a program row would state it.
  const String linkPath = '/var/lib/cluster/default-storage';

  /// A run on a machine with a separate filesystem, or on one without where both are empty.
  ///
  /// The two paths are answered rather than constructed into the steps: whether a machine has a
  /// separate filesystem, and where, is one machine's fact.
  StepContext withStorage(
    HostMachine machine, {
    String mount = storageMount,
    String subdirectory = storageSubdirectory,
  }) => machine.contextFor(
    under,
    Arguments.none,
    hostAnswering(<String, Object>{'storage_mount': mount, 'storage_subdirectory': subdirectory}),
  );

  group('the data filesystem', () {
    test('a path that is an ordinary directory rather than a mount is refused', () async {
      // Everything the cluster writes through it would land on the machine's own filesystem, fill
      // it, and be missing from whatever the data filesystem is backed up by.
      final HostMachine machine = HostMachine();
      machine.files.directories.add(storageMount);
      machine.shell.fails('mountpoint -q $storageMount');

      const RequireStorageMount step = RequireStorageMount();
      final CheckResult answer = await step.check(withStorage(machine));
      expect((answer as Blocked).reason, contains('ordinary directory'));
    });

    test('a machine with no separate filesystem keeps the default and is not refused', () async {
      const RequireStorageMount step = RequireStorageMount();
      expect(
        await step.check(withStorage(HostMachine(), mount: '', subdirectory: '')),
        isA<Satisfied>(),
      );
    });

    test('a mounted path passes', () async {
      final HostMachine machine = HostMachine();
      machine.files.directories.add(storageMount);
      const RequireStorageMount step = RequireStorageMount();
      expect(await step.check(withStorage(machine)), isA<Satisfied>());
    });
  });

  group('the directory every volume lives under', () {
    test('is made once, and a machine that has it is left exactly as it is', () async {
      final HostMachine machine = HostMachine();
      const CreateStorageDirectory step = CreateStorageDirectory(mode: 493);
      final StepContext context = withStorage(machine);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.files.modes[storageSubdirectory], 493);
    });

    test('it says what is lost, because removing it destroys every volume under it', () {
      const CreateStorageDirectory step = CreateStorageDirectory(mode: 493);
      expect(step.irreversibleReason, contains('destroys the data'));
    });
  });

  group('the link the volume provider writes through', () {
    LinkStoragePath link({bool force = false}) => LinkStoragePath(linkPath: linkPath, force: force);

    test('a real directory already there is moved aside before the link is made', () async {
      // The cluster may already have written volumes into it, and replacing it with a link would
      // leave that data with nothing pointing at it and no note of where it went.
      final HostMachine machine = HostMachine();
      machine.shell
        ..fails('test -L $linkPath')
        ..answers('test -d $linkPath', '');

      await link().apply(withStorage(machine));
      expect(machine.changing.first, startsWith('mv $linkPath $linkPath.orig.'));
      expect(machine.changing.last, 'ln -s $storageSubdirectory $linkPath');
      expect(machine.said.join('\n'), contains('is at $linkPath.orig.'));
    });

    test('a link already pointing at the right place is left alone', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers('test -L $linkPath', '')
        ..answers('readlink -f $linkPath', '$storageSubdirectory\n');

      expect(await link().check(withStorage(machine)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test(
      'a link pointing somewhere else is left alone and the step still reports success',
      () async {
        // It is the only thing saying where this cluster's volumes are, and repointing it silently
        // would strand every one of them.
        final HostMachine machine = HostMachine();
        machine.shell
          ..answers('test -L $linkPath', '')
          ..answers('readlink -f $linkPath', '/srv/elsewhere\n');

        expect(await link().check(withStorage(machine)), isA<Satisfied>());
        expect(machine.changing, isEmpty);
        expect(machine.said.join('\n'), contains('Set force to repoint it'));
      },
    );

    test('asked for by name, the wrong link is repointed', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers('test -L $linkPath', '')
        ..answers('readlink -f $linkPath', '/srv/elsewhere\n');

      expect(await link(force: true).check(withStorage(machine)), isA<Ready>());
      await link(force: true).apply(withStorage(machine));
      expect(machine.changing, <String>['rm $linkPath', 'ln -s $storageSubdirectory $linkPath']);
    });

    test('a machine with no separate filesystem is not linked at all', () async {
      const LinkStoragePath none = LinkStoragePath(linkPath: linkPath, force: false);
      final HostMachine machine = HostMachine();
      expect(await none.check(withStorage(machine, mount: '', subdirectory: '')), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });
  });
}
