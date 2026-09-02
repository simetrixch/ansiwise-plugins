import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The states a machine can be found in before the pinned snap is on it, and the one that killed a
/// run.
///
/// Three of them are ONE end state reached from three starting points — nothing installed, installed
/// on another channel, installed and switched off — and one step answers for all three. That is what
/// the first group proves: the same step is run against a machine in each state, and what the
/// machines answer afterwards has to be one and the same thing. The fourth starting point is the
/// compound of two of them, a snap that is switched off AND tracking something else, and it is here
/// because it is the only one that takes two commands.
///
/// The state that killed a run is the snap that is installed and switched off: it is off the path,
/// so a presence test finds nothing, while the install refuses it as already installed and the whole
/// run dies there.
void main() {
  const String snap = 'somesnap';
  const String channel = '1.35/stable';
  const String anotherChannel = '1.34/stable';
  const StepName under = StepName('under_test');

  /// The step as `deploy-cluster` configures it.
  const InstallSnap install = InstallSnap(snap: snap, channel: channel, classic: true);

  String snapList({required String tracking, bool disabled = false}) =>
      'Name      Version  Rev   Tracking     Publisher   Notes\n'
      '$snap  v1.35.0  7964  $tracking  canonical   classic${disabled ? ',disabled' : ''}\n';

  /// A machine that carries no such snap at all.
  HostMachine nothingInstalled() {
    final HostMachine machine = HostMachine();
    machine.shell
      ..fails(onThePathKey(snap))
      ..fails('snap list $snap')
      ..changes('snap install $snap --classic --channel=$channel', () {
        machine.shell
          ..answers(onThePathKey(snap), '/snap/bin/$snap\n')
          ..answers('snap list $snap', snapList(tracking: channel));
      });
    return machine;
  }

  /// A machine carrying the snap, switched on, tracking something other than the pin.
  HostMachine onAnotherChannel() {
    final HostMachine machine = HostMachine();
    machine.shell
      ..answers(onThePathKey(snap), '/snap/bin/$snap\n')
      ..answers('snap list $snap', snapList(tracking: anotherChannel))
      ..changes('snap refresh $snap --channel=$channel', () {
        machine.shell.answers('snap list $snap', snapList(tracking: channel));
      });
    return machine;
  }

  /// A machine carrying the snap switched off, tracking [tracking].
  ///
  /// `snap disable` takes the entries out of `/snap/bin` and leaves the snap installed, which is why
  /// the path answers nothing here while `snap list` still names a channel.
  HostMachine switchedOff({required String tracking}) {
    final HostMachine machine = HostMachine();
    machine.shell
      ..fails(onThePathKey(snap))
      ..answers('snap list $snap', snapList(tracking: tracking, disabled: true))
      ..changes('snap enable $snap', () {
        machine.shell
          ..answers(onThePathKey(snap), '/snap/bin/$snap\n')
          ..answers('snap list $snap', snapList(tracking: tracking));
      })
      ..changes('snap refresh $snap --channel=$channel', () {
        machine.shell.answers('snap list $snap', snapList(tracking: channel));
      });
    return machine;
  }

  /// A machine the step has nothing left to do to.
  HostMachine alreadyThere() {
    final HostMachine machine = HostMachine();
    machine.shell
      ..answers(onThePathKey(snap), '/snap/bin/$snap\n')
      ..answers('snap list $snap', snapList(tracking: channel));
    return machine;
  }

  /// What a machine answers about the snap: whether its command is on the path, and what it tracks.
  Future<({bool onPath, String? tracked})> snapState(HostMachine machine) async {
    final StepContext context = machine.contextFor(under);
    return (
      onPath: await InstallSnap.onPath(context, snap),
      tracked: (await InstallSnap.trackedChannel(context, snap)).channel,
    );
  }

  final Map<String, HostMachine Function()> startingPoints = <String, HostMachine Function()>{
    'nothing installed': nothingInstalled,
    'installed on another channel': onAnotherChannel,
    'installed and switched off': () => switchedOff(tracking: channel),
    'switched off and on another channel': () => switchedOff(tracking: anotherChannel),
  };

  group('every starting point reaches the same end state', () {
    test('the machines are indistinguishable once the step has run', () async {
      final Set<({bool onPath, String? tracked})> ends = <({bool onPath, String? tracked})>{};
      for (final MapEntry<String, HostMachine Function()> start in startingPoints.entries) {
        final HostMachine machine = start.value();
        final StepContext context = machine.contextFor(under);

        expect(
          await install.check(context),
          isA<Ready>(),
          reason: '${start.key}: this machine has work to do',
        );
        await install.apply(context);
        expect(
          await install.check(context),
          isA<Satisfied>(),
          reason: '${start.key}: the step did not reach the state it produces',
        );
        ends.add(await snapState(machine));
      }

      expect(ends, <({bool onPath, String? tracked})>{
        (onPath: true, tracked: channel),
      }, reason: 'the starting point decides which commands run, never where the machine ends up');
    });

    test('a second run against the machine the first produced does nothing at all', () async {
      for (final MapEntry<String, HostMachine Function()> start in startingPoints.entries) {
        final HostMachine machine = start.value();
        final StepContext context = machine.contextFor(under);
        await install.apply(context);
        final List<String> first = List<String>.of(machine.changing);

        expect(
          await install.check(context),
          isA<Satisfied>(),
          reason: '${start.key}: a satisfied check is what keeps the engine from applying again',
        );
        expect(machine.changing, first, reason: '${start.key}: the check itself changed something');
      }
    });

    test('each starting point is answered with the commands that state calls for', () async {
      final Map<String, List<String>> expected = <String, List<String>>{
        'nothing installed': <String>['snap install $snap --classic --channel=$channel'],
        'installed on another channel': <String>['snap refresh $snap --channel=$channel'],
        'installed and switched off': <String>['snap enable $snap'],
        // The compound one, and the only reason the enable comes first: a refresh is refused while
        // the snap is switched off, so the channel can only be moved once it is back on.
        'switched off and on another channel': <String>[
          'snap enable $snap',
          'snap refresh $snap --channel=$channel',
        ],
      };
      for (final MapEntry<String, HostMachine Function()> start in startingPoints.entries) {
        final HostMachine machine = start.value();
        await install.apply(machine.contextFor(under));
        expect(machine.changing, expected[start.key], reason: start.key);
      }
    });
  });

  group('a snap that is installed and switched off', () {
    test('is switched back on rather than installed over', () async {
      // `snap install` answers "already installed" for exactly this state, and a run installing
      // over it dies there with nothing saying which state the machine was in. The snap on the
      // machine carries its own data directory, so installing over it would be a much larger act
      // than switching it back on.
      final HostMachine machine = switchedOff(tracking: channel);
      final StepContext context = machine.contextFor(under);

      expect(await install.check(context), isA<Ready>());
      await install.apply(context);
      expect(machine.changing, <String>['snap enable $snap']);
      expect(
        machine.changing.where((String each) => each.contains('snap install')),
        isEmpty,
        reason: 'installing over a disabled snap is the failure this check exists to avoid',
      );
    });

    test('a dry run names the command that runs first', () async {
      final HostMachine machine = switchedOff(tracking: anotherChannel);
      final StepPlan plan = await install.plan(machine.contextFor(under));

      expect(plan.summary, 'snap enable $snap');
      expect(machine.changing, isEmpty, reason: 'planning may not touch the machine');
    });
  });

  group('the channel', () {
    test('a snap already on the pinned channel is not refreshed at all', () async {
      // A plain refresh with nothing to update exits non-zero, so a step that refreshed
      // unconditionally would report a failure on every machine that is already right.
      final HostMachine machine = alreadyThere();
      expect(await install.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('it is what a program pins, and the step carries no channel of its own', () async {
      const InstallSnap onto = InstallSnap(snap: snap, channel: anotherChannel, classic: true);
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(onThePathKey(snap), '/snap/bin/$snap\n')
        ..answers('snap list $snap', snapList(tracking: channel));

      final StepPlan plan = await onto.plan(machine.contextFor(under));
      expect(plan.summary, 'snap refresh $snap --channel=$anotherChannel');
    });
  });

  group('the confinement', () {
    test('classic is asked for and is not assumed', () async {
      // snapd refuses --classic for a snap that does not ask for it, so a capability that always
      // passed it would only ever install the one snap it was written for.
      const InstallSnap strict = InstallSnap(snap: snap, channel: channel, classic: false);
      final HostMachine machine = nothingInstalled();
      final StepPlan plan = await strict.plan(machine.contextFor(under));
      expect(plan.summary, 'snap install $snap --channel=$channel');
    });
  });

  group('a machine nothing can be proven about', () {
    test('the snap answers on the path and snapd names no channel for it', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers(onThePathKey(snap), '/snap/bin/$snap\n')
        ..fails('snap list $snap');

      final CheckResult answer = await install.check(machine.contextFor(under));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains(channel));
      expect(machine.changing, isEmpty);
    });
  });

  group('taking the snap away', () {
    const RemoveSnap asked = RemoveSnap(snap: snap, force: true);

    test(
      'THE PLANTED DEFECT: a snapd that would not answer is not a machine without the snap',
      () async {
        // `snap list <name>` exits non-zero for a snap that is not installed AND for a snapd that
        // could not be asked at all. Read as the first, an operator's teardown was reported as done
        // over a machine still carrying the snap - and a DISABLED snap is the state where the
        // presence test beside it cannot stand in, because such a snap is off the path as well.
        final HostMachine machine = HostMachine();
        machine.shell
          ..fails(onThePathKey(snap))
          ..fails('snap list $snap', stderr: 'error: cannot communicate with server')
          ..fails('snap version', stderr: 'error: cannot communicate with server');

        final CheckResult answer = await asked.check(machine.contextFor(under));

        expect(answer, isA<Blocked>(), reason: '$answer');
        expect(machine.changing, isEmpty);
      },
    );

    test('THE INNOCENT CASE: a snapd that answers and carries no such snap is satisfied', () async {
      // The state the refusal above must not swallow. snapd answered; it simply has no such snap.
      final HostMachine machine = HostMachine();
      machine.shell
        ..fails(onThePathKey(snap))
        ..fails('snap list $snap', stderr: 'error: no matching snaps installed')
        ..answers('snap version', 'snap    2.63\nsnapd   2.63\n');

      final CheckResult answer = await asked.check(machine.contextFor(under));

      expect(answer, isA<Satisfied>(), reason: answer is Blocked ? answer.reason : '$answer');
      expect(machine.changing, isEmpty);
    });

    test('is not done unless it was asked for', () async {
      const RemoveSnap notAsked = RemoveSnap(snap: snap, force: false);
      final HostMachine machine = alreadyThere();
      expect(await notAsked.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('takes the snap away when it was', () async {
      final HostMachine machine = alreadyThere();
      machine.shell.changes('snap remove $snap --purge', () {
        machine.shell
          ..fails(onThePathKey(snap))
          ..fails('snap list $snap');
      });

      final StepContext context = machine.contextFor(under);
      expect(await asked.check(context), isA<Ready>());
      await asked.apply(context);
      expect(await asked.check(context), isA<Satisfied>());
      expect(await snapState(machine), (onPath: false, tracked: null));
    });

    test(
      'the group the snap created is not deleted here, because the install needs it back',
      () async {
        // A teardown that claims to leave nothing behind has to delete the group explicitly. Nothing
        // in this program needs it to survive, and nothing here takes it away either.
        final HostMachine machine = alreadyThere();
        await asked.apply(machine.contextFor(under));
        expect(
          machine.changing.where((String each) => each.contains('groupdel')),
          isEmpty,
          reason:
              'installing the snap again creates the group and the account is added to it again',
        );
      },
    );

    test('it says what is lost, because there is no way back from it', () {
      expect(asked.irreversibleReason, contains('data directory'));
      expect(install.irreversibleReason, contains('channel it left'));
    });
  });
}
