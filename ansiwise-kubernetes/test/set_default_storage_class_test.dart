import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The class a claim gets when it names none.
void main() {
  const StepName under = StepName('set_default_storage_class');
  const String storageClasses =
      'kubectl get storageclass -o '
      r'jsonpath={range .items[*]}{.metadata.name}{" "}'
      r'{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}';
  const SetDefaultStorageClass step = SetDefaultStorageClass(
    timeoutSeconds: 120,
    intervalSeconds: 5,
  );

  test(
    'the one class the provisioner produced is marked, and its name is never configured',
    () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(storageClasses, 'local-hostpath \n')
        ..changes(
          'kubectl patch storageclass local-hostpath --type merge -p '
          '{"metadata":{"annotations":{"${SetDefaultStorageClass.annotation}":"true"}}}',
          () => machine.shell.answers(storageClasses, 'local-hostpath true\n'),
        );

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    },
  );

  test('a class already marked is left alone', () async {
    final ClusterMachine machine = ClusterMachine()
      ..shell.answers(storageClasses, 'local-hostpath true\n');
    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test('a cluster with no class yet is waited for rather than left without a default', () async {
    // A step that looked once and moved on would leave a first install with no default class until
    // somebody came back and ran the whole thing a second time.
    final ClusterMachine machine = ClusterMachine();
    int looks = 0;
    machine.shell
      ..answers(storageClasses, '')
      ..changes(storageClasses, () {
        looks++;
        if (looks >= 3) {
          machine.shell.answers(storageClasses, 'local-hostpath \n');
        }
      });

    await step.apply(machine.contextFor(under));
    expect(machine.changing.join('\n'), contains('patch storageclass local-hostpath'));
    expect(machine.clock.elapsed.inSeconds, greaterThan(0));
  });

  test('a cluster that never produces one ends in a reported failure', () async {
    final ClusterMachine machine = ClusterMachine()..shell.answers(storageClasses, '');
    await expectLater(step.apply(machine.contextFor(under)), throwsA(isA<WaitedTooLong>()));
  });

  group('a cluster carrying several classes and no default', () {
    // Which of several catches every claim that names none is a decision. Taking whichever the API
    // server listed first would make it silently, and the order is the API server's — so two
    // readings of the same cluster can produce two different clusters with nothing saying why.
    ClusterMachine withTwoClasses() =>
        ClusterMachine()..shell.answers(storageClasses, 'local-hostpath \nnetwork-block \n');

    test('is refused by the check, with both of them named', () async {
      final CheckResult answer = await step.check(withTwoClasses().contextFor(under));
      expect((answer as Blocked).reason, contains('local-hostpath'));
      expect(answer.reason, contains('network-block'));
    });

    test('is refused by the apply rather than marked at random', () async {
      final ClusterMachine machine = withTwoClasses();
      await expectLater(step.apply(machine.contextFor(under)), throwsA(isA<StateError>()));
      expect(
        machine.changing,
        isEmpty,
        reason: 'a refusal that had already patched one of them is not a refusal',
      );
    });

    test('one of them already marked is left exactly as it is', () async {
      // The other side of the refusal: several classes are not a problem in themselves, and a
      // cluster where somebody already decided is satisfied rather than refused.
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers(storageClasses, 'local-hostpath \nnetwork-block true\n');
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });
  });
}
