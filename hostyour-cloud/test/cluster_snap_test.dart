import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// The four states a machine can be found in before MicroK8s is on it, and one that killed a run.
///
/// The one that killed a run is the snap that is installed and switched off: it is off the path, so
/// a presence test finds nothing, while the install refuses it as already installed and the whole
/// run dies there.
void main() {
  const String channel = '1.35/stable';
  const StepName under = StepName('under_test');

  const List<String> snapListHeader = <String>[
    'Name      Version  Rev   Tracking     Publisher   Notes',
  ];

  String snapList({required String tracking, bool disabled = false}) =>
      '${snapListHeader.first}\n'
      'microk8s  v1.35.0  7964  $tracking  canonical   classic${disabled ? ',disabled' : ''}\n';

  group('a snap that is installed and switched off', () {
    test('is switched back on rather than installed over', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..fails('command -v microk8s')
        ..answers('snap list microk8s', snapList(tracking: channel, disabled: true))
        ..changes('snap enable microk8s', () {
          machine.shell
            ..answers('command -v microk8s', '/snap/bin/microk8s\n')
            ..answers('snap list microk8s', snapList(tracking: channel));
        });

      const EnableDisabledMicrok8sSnap step = EnableDisabledMicrok8sSnap();
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.changing, <String>['snap enable microk8s']);
    });

    test('is refused by the install rather than installed over', () async {
      // `snap install` answers "already installed" for exactly this state, and the run used to die
      // on it with nothing saying which state the machine was in.
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..fails('command -v microk8s')
        ..answers('snap list microk8s', snapList(tracking: channel, disabled: true));

      const InstallMicrok8sSnap step = InstallMicrok8sSnap(channel: channel);
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('snap enable microk8s'));
      expect(machine.changing, isEmpty);
    });
  });

  group('the channel', () {
    test('a snap already on the pinned channel is not refreshed at all', () async {
      // A plain refresh with nothing to update exits non-zero, so a step that refreshed
      // unconditionally would report a failure on every machine that is already right.
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers('snap list microk8s', snapList(tracking: channel));

      const RefreshMicrok8sChannel step = RefreshMicrok8sChannel(channel: channel);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a snap on another channel is moved onto the pin', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('snap list microk8s', snapList(tracking: '1.34/stable'))
        ..changes('snap refresh microk8s --channel=$channel', () {
          machine.shell.answers('snap list microk8s', snapList(tracking: channel));
        });

      const RefreshMicrok8sChannel step = RefreshMicrok8sChannel(channel: channel);
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('no snap at all is nothing to move', () async {
      final ClusterMachine machine = ClusterMachine()..shell.fails('snap list microk8s');
      const RefreshMicrok8sChannel step = RefreshMicrok8sChannel(channel: channel);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    });
  });

  group('the install', () {
    test('a clean machine is installed at the pinned channel', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..fails('command -v microk8s')
        ..fails('snap list microk8s')
        ..changes('snap install microk8s --classic --channel=$channel', () {
          machine.shell.answers('command -v microk8s', '/snap/bin/microk8s\n');
        });

      const InstallMicrok8sSnap step = InstallMicrok8sSnap(channel: channel);
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.changing, <String>['snap install microk8s --classic --channel=$channel']);
    });

    test('a machine that already carries it is left alone', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('command -v microk8s', '/snap/bin/microk8s\n');
      const InstallMicrok8sSnap step = InstallMicrok8sSnap(channel: channel);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('it says what is lost, because there is no way back from it', () {
      const InstallMicrok8sSnap step = InstallMicrok8sSnap(channel: channel);
      expect(step.irreversibleReason, contains('persistent volume'));
    });
  });

  group('the purge', () {
    test('is not taken unless it was asked for', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('command -v microk8s', '/snap/bin/microk8s\n');
      const RemoveMicrok8sSnapForced step = RemoveMicrok8sSnapForced(force: false);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('takes the snap away when it was', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('command -v microk8s', '/snap/bin/microk8s\n')
        ..answers('snap list microk8s', snapList(tracking: channel))
        ..changes('snap remove microk8s --purge', () {
          machine.shell
            ..fails('command -v microk8s')
            ..fails('snap list microk8s');
        });

      const RemoveMicrok8sSnapForced step = RemoveMicrok8sSnapForced(force: true);
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('the group it created is not deleted here, because the reinstall needs it back', () async {
      // A teardown that claims to leave nothing behind has to delete the group explicitly. Nothing
      // in this program needs it to survive, and nothing here takes it away either.
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('command -v microk8s', '/snap/bin/microk8s\n')
        ..answers('snap list microk8s', snapList(tracking: channel));

      const RemoveMicrok8sSnapForced step = RemoveMicrok8sSnapForced(force: true);
      await step.apply(machine.contextFor(under));
      expect(
        machine.changing.where((String each) => each.contains('groupdel')),
        isEmpty,
        reason: 'the reinstall creates the group again and adds the account to it',
      );
    });
  });

  group('the wait for the node', () {
    test('only looks, so a dry run may run it', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('microk8s status --wait-ready --timeout 300', 'microk8s is running\n');

      const WaitForMicrok8sReady step = WaitForMicrok8sReady(timeoutSeconds: 300);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('the verdict comes from what the node said, not from what the command returned', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('microk8s status --wait-ready --timeout 300', 'microk8s is not running\n');

      const WaitForMicrok8sReady step = WaitForMicrok8sReady(timeoutSeconds: 300);
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('microk8s is not running'));
    });

    test('it is a gate over what an earlier step did, so a dry run does not fail on it', () {
      const WaitForMicrok8sReady step = WaitForMicrok8sReady(timeoutSeconds: 300);
      expect(step.verifiesAnEarlierStep, isTrue);
    });
  });
}
