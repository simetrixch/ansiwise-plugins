import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Where the volumes land: the data disk read off the mount table, the directory on it, and the
/// link the volume provider writes through.
void main() {
  const StepName under = StepName('under_test');
  const String dataDisk = '/mnt/data';
  const String subdirectory = 'volumes';
  const String storageDirectory = '$dataDisk/$subdirectory';

  /// The path the cluster's volume provider really writes through, as a program row would state it.
  const String linkPath = '/var/lib/cluster/default-storage';

  /// The mount table of a machine with a data disk beside its boot disk, and of one without.
  const String withDataDisk = '/ /dev/sda2\n/boot/efi /dev/sda1\n$dataDisk /dev/sdb1\n';
  const String withoutDataDisk = '/ /dev/sda2\n/boot/efi /dev/sda1\n';
  final String mountTable = mountTableCommand.argv.join(' ');

  /// A machine whose mount table reads [table]. Nobody answers anything about its disks.
  HostMachine machineWith(String table) => HostMachine()..shell.answers(mountTable, table);

  group('the data disk out of the mount table', () {
    const List<(String, String, String?)> readings = <(String, String, String?)>[
      (
        'a machine with nothing mounted beside the boot disk has no data disk',
        withoutDataDisk,
        null,
      ),
      ('one disk mounted beside the boot disk is the data disk', withDataDisk, dataDisk),
      (
        'a mount nested under the disk is a part of it, and the disk wins',
        '/ /dev/sda2\n$dataDisk/nested /dev/sdc1\n$dataDisk /dev/sdb1\n',
        dataDisk,
      ),
      (
        "a mount under the snap tree is the cluster's own volume, or a snap image, and not a disk",
        '/ /dev/sda2\n/snap/core/1 /dev/loop0\n/var/snap/x/common/volume /dev/sdb1\n',
        null,
      ),
      (
        'two disks at one depth: the first by name',
        '/ /dev/sda2\n/mnt/b /dev/sdc1\n/mnt/a /dev/sdb1\n',
        '/mnt/a',
      ),
      (
        'a network share or a memory filesystem is no block device, and not a disk',
        '/ /dev/sda2\n/mnt/share 10.0.0.1:/share\n/run tmpfs\n',
        null,
      ),
    ];
    for (final (String why, String table, String? disk) in readings) {
      test(why, () => expect(dataDiskMountFrom(table), disk));
    }
  });

  group('the data disk', () {
    const RequireStorageMount step = RequireStorageMount();

    test('a path the mount table names and mountpoint denies is refused', () async {
      // Everything the cluster writes through it would land on the machine's own filesystem, fill
      // it, and be missing from whatever the data disk is backed up by.
      final HostMachine machine = machineWith(withDataDisk);
      machine.shell.fails('mountpoint -q $dataDisk');

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('ordinary directory'));
    });

    test('a machine with no data disk keeps the default and is not refused', () async {
      final CheckResult answer = await step.check(machineWith(withoutDataDisk).contextFor(under));
      expect((answer as Satisfied).because, contains('no data disk'));
    });

    test('a mounted data disk passes, and the row says where it is', () async {
      final CheckResult answer = await step.check(machineWith(withDataDisk).contextFor(under));
      expect((answer as Satisfied).because, 'the data disk is mounted at $dataDisk');
    });

    test('a mount table that cannot be read is a failure, not a machine with no disk', () async {
      final HostMachine machine = HostMachine();
      machine.shell.fails(mountTable, stderr: 'findmnt: not found');
      expect(() => step.check(machine.contextFor(under)), throwsA(isA<CommandFailed>()));
    });
  });

  group('the directory every volume lives under', () {
    const CreateStorageDirectory step = CreateStorageDirectory(
      subdirectory: subdirectory,
      mode: 493,
    );

    test('is made under the data disk once, and a machine that has it is left as it is', () async {
      final HostMachine machine = machineWith(withDataDisk);
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      final CheckResult again = await step.check(context);
      expect((again as Satisfied).because, contains('$storageDirectory is there'));
      expect(machine.files.modes[storageDirectory], 493);
    });

    test('a machine with no data disk has no directory to make', () async {
      final HostMachine machine = machineWith(withoutDataDisk);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.files.directories, isEmpty);
    });

    test('it says what is lost, because removing it destroys every volume under it', () {
      expect(step.irreversibleReason, contains('destroys the data'));
    });
  });

  group('the link the volume provider writes through', () {
    LinkStoragePath link({bool force = false}) =>
        LinkStoragePath(linkPath: linkPath, subdirectory: subdirectory, force: force);

    test('an empty directory already there is moved aside before the link is made', () async {
      // It holds nothing to strand, so it goes aside with a stamp rather than being written over.
      final HostMachine machine = machineWith(withDataDisk);
      machine.shell
        ..fails('test -L $linkPath')
        ..answers('test -d $linkPath', '');

      expect(await link().check(machine.contextFor(under)), isA<Ready>());
      await link().apply(machine.contextFor(under));
      expect(machine.changing.first, startsWith('mv $linkPath $linkPath.orig.'));
      expect(machine.changing.last, 'ln -s $storageDirectory $linkPath');
      expect(machine.said.join('\n'), contains('is at $linkPath.orig.'));
    });

    test('a directory holding volumes is refused, and nothing is moved', () async {
      // Every volume the cluster has handed out lives in it: moved aside, every pod holding a mount
      // keeps it on the moved directory and every pod started afterwards gets an empty one.
      final HostMachine machine = machineWith(withDataDisk);
      machine.shell
        ..fails('test -L $linkPath')
        ..answers('test -d $linkPath', '')
        ..answers('ls -A -- $linkPath', 'pvc-one\npvc-two\n');

      final CheckResult answer = await link().check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('$linkPath is a directory holding 2 entries'));
      expect(answer.reason, contains("force is the operator's word"));
      expect(machine.changing, isEmpty);
    });

    test('asked for by name, the directory holding volumes is moved aside with a stamp', () async {
      final HostMachine machine = machineWith(withDataDisk);
      machine.shell
        ..fails('test -L $linkPath')
        ..answers('test -d $linkPath', '')
        ..answers('ls -A -- $linkPath', 'pvc-one\npvc-two\n');

      expect(await link(force: true).check(machine.contextFor(under)), isA<Ready>());
      await link(force: true).apply(machine.contextFor(under));
      expect(machine.changing.first, startsWith('mv $linkPath $linkPath.orig.'));
      expect(machine.changing.last, 'ln -s $storageDirectory $linkPath');
    });

    test('a link already pointing at the right place is left alone', () async {
      final HostMachine machine = machineWith(withDataDisk);
      machine.shell
        ..answers('test -L $linkPath', '')
        ..answers('readlink -f $linkPath', '$storageDirectory\n');

      final CheckResult answer = await link().check(machine.contextFor(under));
      expect(
        (answer as Satisfied).because,
        'the data disk is mounted at $dataDisk, and $linkPath points at $storageDirectory',
      );
      expect(machine.changing, isEmpty);
    });

    test(
      'a link pointing somewhere else is left alone and the step still reports success',
      () async {
        // It is the only thing saying where this cluster's volumes are, and repointing it silently
        // would strand every one of them.
        final HostMachine machine = machineWith(withDataDisk);
        machine.shell
          ..answers('test -L $linkPath', '')
          ..answers('readlink -f $linkPath', '/srv/elsewhere\n');

        expect(await link().check(machine.contextFor(under)), isA<Satisfied>());
        expect(machine.changing, isEmpty);
        expect(machine.said.join('\n'), contains('Set force to repoint it'));
      },
    );

    test('asked for by name, the wrong link is repointed', () async {
      final HostMachine machine = machineWith(withDataDisk);
      machine.shell
        ..answers('test -L $linkPath', '')
        ..answers('readlink -f $linkPath', '/srv/elsewhere\n');

      expect(await link(force: true).check(machine.contextFor(under)), isA<Ready>());
      await link(force: true).apply(machine.contextFor(under));
      expect(machine.changing, <String>['rm $linkPath', 'ln -s $storageDirectory $linkPath']);
    });

    test('a machine with no data disk is not linked at all', () async {
      final HostMachine machine = machineWith(withoutDataDisk);
      expect(await link().check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });
  });
}
