import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';
import 'support/workloads.dart';

/// A CPU request on a container, compared against the RUNNING pods and not only the declaration.
void main() {
  const StepName under = StepName('patch_container_resources');
  const String traefikDaemonSet = 'kubectl -n ingress get daemonset traefik -o json';
  const String traefikPods =
      'kubectl -n ingress get pods -l app.kubernetes.io/name=traefik -o json';
  const String requestPatch =
      'kubectl -n ingress patch daemonset traefik --type=strategic -p '
      '{"spec":{"template":{"spec":{"containers":[{"name":"traefik","resources":'
      '{"requests":{"cpu":"400m"}}}]}}}}';
  const String removalPatch =
      'kubectl -n ingress patch daemonset traefik --type=strategic -p '
      '{"spec":{"template":{"spec":{"containers":[{"name":"traefik","resources":'
      '{"requests":{"cpu":null}}}]}}}}';
  const String rolloutStatus = 'kubectl -n ingress rollout status daemonset/traefik --timeout=90s';

  PatchContainerResources asking({String cpuRequest = '400m', String container = 'traefik'}) =>
      PatchContainerResources(
        namespace: 'ingress',
        kind: 'daemonset',
        name: 'traefik',
        container: container,
        cpuRequest: cpuRequest,
        rolloutTimeoutSeconds: 90,
      );

  /// A machine whose controller declares [declared] of CPU, or `resources: {}` where that is null,
  /// and whose pods are [pods].
  ClusterMachine withController({
    String? declared,
    Map<String, PodState> pods = const <String, PodState>{},
    String container = 'traefik',
  }) {
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers(
        traefikDaemonSet,
        workloadJson(container: container, arguments: const <String>[], cpuRequest: declared),
      )
      ..answers(traefikPods, podsJson(pods, container: container));
    return machine;
  }

  test('a controller that is not there is a skip and nothing changes', () async {
    final ClusterMachine machine = ClusterMachine()..shell.fails(traefikDaemonSet);
    expect(await asking().check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test('a workload with no container of that name is refused, and says what it has', () async {
    final ClusterMachine machine = withController(container: 'controller');
    final CheckResult answer = await asking().check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('controller'));
    expect(machine.changing, isEmpty);
  });

  test('a request written as no quantity of CPU blocks the row, naming it', () async {
    final ClusterMachine machine = withController();
    final CheckResult answer = await asking(cpuRequest: 'plenty').check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('"plenty" is not a quantity of CPU'));
    expect(machine.changing, isEmpty);
  });

  test(
    'pods that cannot be read block the check once the declaration carries the request',
    () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(
          traefikDaemonSet,
          workloadJson(container: 'traefik', arguments: const <String>[], cpuRequest: '400m'),
        )
        ..fails(traefikPods);
      final CheckResult answer = await asking().check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('could not be read'));
    },
  );

  test('a declaration of no request is patched, the serving pod replaced, and a second run '
      'changes nothing', () async {
    final ClusterMachine machine = withController(
      pods: const <String, PodState>{'traefik-old': PodState(phase: 'Running')},
    );
    machine.shell
      ..changes(requestPatch, () {
        machine.shell.answers(
          traefikDaemonSet,
          workloadJson(container: 'traefik', arguments: const <String>[], cpuRequest: '400m'),
        );
      })
      ..changes('kubectl -n ingress delete pod traefik-old --grace-period=10', () {
        machine.shell.answers(
          traefikPods,
          podsJson(const <String, PodState>{
            'traefik-new': PodState(phase: 'Running', cpuRequest: '400m'),
          }),
        );
      });

    final StepContext context = machine.contextFor(under);
    expect(await asking().check(context), isA<Ready>());
    final StepPlan plan = await asking().plan(context);
    expect(plan.summary, 'kubectl -n ingress delete pod traefik-old --grace-period=10');
    expect(
      machine.said.join('\n'),
      contains(requestPatch),
      reason: 'the patch that precedes the deletion is said in the log the plan leaves behind',
    );

    await asking().apply(context);
    expect(machine.changing, <String>[
      requestPatch,
      'kubectl -n ingress delete pod traefik-old --grace-period=10',
      rolloutStatus,
    ]);
    expect(await asking().check(context), isA<Satisfied>());
    final int done = machine.changing.length;
    expect(await asking().check(context), isA<Satisfied>());
    expect(machine.changing, hasLength(done), reason: 'a second run must change nothing');
  });

  test('a surge pod left pending beside a serving pod without the request is cleared, then the '
      'serving pod replaced, with no patch', () async {
    // A run that patched and then timed out: the declaration carries the request, the surge pod
    // cannot bind the ports the serving pod holds, and the serving pod still has no request.
    final ClusterMachine machine = withController(
      declared: '400m',
      pods: const <String, PodState>{
        'traefik-surge': PodState(phase: 'Pending'),
        'traefik-old': PodState(phase: 'Running'),
      },
    );

    final StepContext context = machine.contextFor(under);
    expect(
      await asking().check(context),
      isA<Ready>(),
      reason: 'the declaration carries it and what is serving does not',
    );
    await asking().apply(context);

    expect(machine.changing, <String>[
      'kubectl -n ingress delete pod traefik-surge --grace-period=0 --force',
      'kubectl -n ingress delete pod traefik-old --grace-period=10',
      rolloutStatus,
    ]);
  });

  test('a declaration and a serving pod that both carry the request are satisfied', () async {
    final ClusterMachine machine = withController(
      declared: '400m',
      pods: const <String, PodState>{'traefik-old': PodState(phase: 'Running', cpuRequest: '400m')},
    );
    expect(await asking().check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test('a request spelled as the cluster stores it is the same request', () async {
    // The cluster hands 1000m back as 1.
    final ClusterMachine machine = withController(
      declared: '1',
      pods: const <String, PodState>{'traefik-old': PodState(phase: 'Running', cpuRequest: '1')},
    );
    expect(await asking(cpuRequest: '1000m').check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test('a declaration of another request is patched to this one', () async {
    final ClusterMachine machine = withController(
      declared: '200m',
      pods: const <String, PodState>{'traefik-old': PodState(phase: 'Running', cpuRequest: '200m')},
    );

    final StepContext context = machine.contextFor(under);
    expect(await asking().check(context), isA<Ready>());
    await asking().apply(context);

    expect(machine.changing.first, requestPatch);
    expect(machine.changing.first, contains('"cpu":"400m"'));
  });

  test('no pod at all is a skip once the declaration carries the request', () async {
    final ClusterMachine machine = withController(declared: '400m');
    expect(await asking().check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test(
    'an undo after a capture of none removes the request and replaces the pod carrying it',
    () async {
      final ClusterMachine machine = withController(
        pods: const <String, PodState>{'traefik-old': PodState(phase: 'Running')},
      );
      final PatchContainerResources step = asking();
      final StepContext context = machine.contextFor(under);

      final ContainerCpuRequest before = await step.capture(context);
      expect(before.request, isNull);

      machine.shell
        ..answers(
          traefikDaemonSet,
          workloadJson(container: 'traefik', arguments: const <String>[], cpuRequest: '400m'),
        )
        ..answers(
          traefikPods,
          podsJson(const <String, PodState>{
            'traefik-new': PodState(phase: 'Running', cpuRequest: '400m'),
          }),
        );
      await step.undo(context, before);

      expect(machine.changing, <String>[
        removalPatch,
        'kubectl -n ingress delete pod traefik-new --grace-period=10',
        rolloutStatus,
      ]);
    },
  );

  test('an undo puts back the request the container carried before the run', () async {
    final ClusterMachine machine = withController(
      declared: '200m',
      pods: const <String, PodState>{'traefik-old': PodState(phase: 'Running', cpuRequest: '200m')},
    );
    final PatchContainerResources step = asking();
    final StepContext context = machine.contextFor(under);

    final ContainerCpuRequest before = await step.capture(context);
    expect(before.request, '200m');

    machine.shell
      ..answers(
        traefikDaemonSet,
        workloadJson(container: 'traefik', arguments: const <String>[], cpuRequest: '400m'),
      )
      ..answers(
        traefikPods,
        podsJson(const <String, PodState>{
          'traefik-new': PodState(phase: 'Running', cpuRequest: '400m'),
        }),
      );
    await step.undo(context, before);

    expect(machine.changing.first, contains('"cpu":"200m"'));
    expect(
      machine.changing,
      contains('kubectl -n ingress delete pod traefik-new --grace-period=10'),
    );
  });

  test('an undo of a run that asked for what was already there changes nothing', () async {
    final ClusterMachine machine = withController(
      declared: '400m',
      pods: const <String, PodState>{'traefik-old': PodState(phase: 'Running', cpuRequest: '400m')},
    );
    await asking().undo(machine.contextFor(under), const ContainerCpuRequest('400m'));
    expect(machine.changing, isEmpty, reason: 'replacing the pods would interrupt what they serve');
  });

  test('an undo whose patch is rejected throws and deletes no pod', () async {
    final ClusterMachine machine = withController(
      declared: '400m',
      pods: const <String, PodState>{'traefik-old': PodState(phase: 'Running', cpuRequest: '400m')},
    );
    machine.shell.fails(removalPatch);
    await expectLater(
      asking().undo(machine.contextFor(under), const ContainerCpuRequest(null)),
      throwsA(isA<CommandFailed>()),
    );
    expect(machine.changing.join('\n'), isNot(contains('delete pod')));
  });

  test('an undo over a cluster nobody could ask throws and changes nothing', () async {
    final ClusterMachine machine = ClusterMachine()
      ..cannotBeReached('daemonset', namespace: 'ingress', stderr: 'connection refused');
    await expectLater(
      asking().undo(machine.contextFor(under), const ContainerCpuRequest(null)),
      throwsA(isA<StateError>()),
    );
    expect(machine.changing, isEmpty);
  });

  test('a capture over a cluster nobody could ask throws and does not claim none', () async {
    final ClusterMachine machine = ClusterMachine()
      ..cannotBeReached('daemonset', namespace: 'ingress', stderr: 'connection refused');
    await expectLater(asking().capture(machine.contextFor(under)), throwsA(isA<StateError>()));
  });
}
