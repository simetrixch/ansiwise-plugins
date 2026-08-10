import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Where the volumes land: the mount, the directory, and the link the volume provider writes
/// through.
void main() {
  const StepName under = StepName('under_test');
  const String storagePath = '/mnt/data';
  const String storageDirectory = '$storagePath/microk8s';

  /// The path MicroK8s really writes through, as a program row would state it.
  const String linkPath = '/var/snap/microk8s/common/default-storage';

  /// A run on a machine with a separate filesystem, or on one without where both are empty.
  ///
  /// The two paths are answered rather than constructed into the steps: whether a machine has a
  /// separate filesystem, and where, is one machine's fact.
  StepContext withStorage(
    HostMachine machine, {
    String path = storagePath,
    String directory = storageDirectory,
  }) => machine.contextFor(
    under,
    Arguments.none,
    hostAnswering(<String, Object>{'storage_path': path, 'storage_directory': directory}),
  );

  group('the data filesystem', () {
    test('a path that is an ordinary directory rather than a mount is refused', () async {
      // Everything the cluster writes through it would land on the machine's own filesystem, fill
      // it, and be missing from whatever the data filesystem is backed up by.
      final HostMachine machine = HostMachine();
      machine.files.directories.add(storagePath);
      machine.shell.fails('mountpoint -q $storagePath');

      const CheckStorageMount step = CheckStorageMount();
      final CheckResult answer = await step.check(withStorage(machine));
      expect((answer as Blocked).reason, contains('ordinary directory'));
    });

    test('a machine with no separate filesystem keeps the default and is not refused', () async {
      const CheckStorageMount step = CheckStorageMount();
      expect(
        await step.check(withStorage(HostMachine(), path: '', directory: '')),
        isA<Satisfied>(),
      );
    });

    test('a mounted path passes', () async {
      final HostMachine machine = HostMachine();
      machine.files.directories.add(storagePath);
      const CheckStorageMount step = CheckStorageMount();
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
      expect(machine.files.modes[storageDirectory], 493);
    });

    test('it says what is lost, because removing it destroys every volume under it', () {
      const CreateStorageDirectory step = CreateStorageDirectory(mode: 493);
      expect(step.irreversibleReason, contains('destroys the data'));
    });
  });

  group('the link the volume provider writes through', () {
    LinkMicrok8sStoragePath link({bool force = false}) =>
        LinkMicrok8sStoragePath(microk8sStoragePath: linkPath, force: force);

    test('a real directory already there is moved aside before the link is made', () async {
      // The cluster may already have written volumes into it, and replacing it with a link would
      // leave that data with nothing pointing at it and no note of where it went.
      final HostMachine machine = HostMachine();
      machine.shell
        ..fails('test -L $linkPath')
        ..answers('test -d $linkPath', '');

      await link().apply(withStorage(machine));
      expect(machine.changing.first, startsWith('mv $linkPath $linkPath.orig.'));
      expect(machine.changing.last, 'ln -s $storageDirectory $linkPath');
      expect(machine.said.join('\n'), contains('is at $linkPath.orig.'));
    });

    test('a link already pointing at the right place is left alone', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers('test -L $linkPath', '')
        ..answers('readlink -f $linkPath', '$storageDirectory\n');

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
      expect(machine.changing, <String>['rm $linkPath', 'ln -s $storageDirectory $linkPath']);
    });

    test('a machine with no separate filesystem is not linked at all', () async {
      const LinkMicrok8sStoragePath none = LinkMicrok8sStoragePath(
        microk8sStoragePath: linkPath,
        force: false,
      );
      final HostMachine machine = HostMachine();
      expect(await none.check(withStorage(machine, path: '', directory: '')), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });
  });
}
