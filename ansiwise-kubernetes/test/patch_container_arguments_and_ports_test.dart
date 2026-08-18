import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';
import 'support/workloads.dart';

/// Arguments and ports on a container, compared against the RUNNING pods and not only the
/// declaration.
void main() {
  const StepName under = StepName('patch_container_arguments_and_ports');
  const String crossNamespaceArgument = '--providers.kubernetescrd.allowCrossNamespace=true';
  const String entrypointArgument = '--entryPoints.postgres.address=:5432/tcp';
  const String traefikDaemonSet = 'kubectl -n ingress get daemonset traefik -o json';
  const String traefikPods =
      'kubectl -n ingress get pods -l app.kubernetes.io/name=traefik -o json';

  PatchContainerArgumentsAndPorts asking({
    List<String> arguments = const <String>[crossNamespaceArgument],
    List<String> ports = const <String>[],
    String container = 'traefik',
  }) => PatchContainerArgumentsAndPorts(
    namespace: 'ingress',
    kind: 'daemonset',
    name: 'traefik',
    container: container,
    containerArguments: arguments,
    ports: ports,
    rolloutTimeoutSeconds: 90,
  );

  /// A machine whose controller is declared with [declared] and whose pods are [pods].
  ClusterMachine withController({
    required List<String> declared,
    Map<String, int> declaredPorts = const <String, int>{},
    Map<String, PodState> pods = const <String, PodState>{},
    String container = 'traefik',
  }) {
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers(
        traefikDaemonSet,
        workloadJson(container: container, arguments: declared, ports: declaredPorts),
      )
      ..answers(traefikPods, podsJson(pods, container: container));
    return machine;
  }

  test('a controller that is not there is a skip and not a failure', () async {
    final ClusterMachine machine = ClusterMachine()..shell.fails(traefikDaemonSet);
    expect(await asking().check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test('a workload with no container of that name is refused, and says what it has', () async {
    final ClusterMachine machine = withController(
      declared: const <String>[],
      container: 'controller',
    );
    final CheckResult answer = await asking().check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('controller'));
    expect(machine.changing, isEmpty);
  });

  test('the argument is added once, and a second run adds nothing', () async {
    final ClusterMachine machine = withController(
      declared: const <String>['--entrypoints.web.address=:8000/tcp'],
      pods: const <String, PodState>{
        'traefik-old': PodState(
          phase: 'Running',
          arguments: <String>['--entrypoints.web.address=:8000/tcp'],
        ),
      },
    );
    machine.shell.changes('kubectl -n ingress patch daemonset traefik --type=json -p '
        '[{"op":"add","path":"/spec/template/spec/containers/0/args/-",'
        '"value":"$crossNamespaceArgument"}]', () {
      machine.shell
        ..answers(
          traefikDaemonSet,
          workloadJson(
            container: 'traefik',
            arguments: const <String>[
              '--entrypoints.web.address=:8000/tcp',
              crossNamespaceArgument,
            ],
          ),
        )
        ..answers(
          traefikPods,
          podsJson(const <String, PodState>{
            'traefik-new': PodState(
              phase: 'Running',
              arguments: <String>['--entrypoints.web.address=:8000/tcp', crossNamespaceArgument],
            ),
          }),
        );
    });

    final StepContext context = machine.contextFor(under);
    expect(await asking().check(context), isA<Ready>());
    await asking().apply(context);
    expect(await asking().check(context), isA<Satisfied>());
    final int done = machine.changing.length;
    expect(await asking().check(context), isA<Satisfied>());
    expect(machine.changing, hasLength(done), reason: 'a re-run duplicates the argument otherwise');
  });

  test('a port produces BOTH the argument and the published port, in one patch', () async {
    final ClusterMachine machine = withController(
      declared: const <String>[crossNamespaceArgument],
      pods: const <String, PodState>{
        'traefik-old': PodState(phase: 'Running', arguments: <String>[crossNamespaceArgument]),
      },
    );

    final StepContext context = machine.contextFor(under);
    final PatchContainerArgumentsAndPorts step = asking(
      arguments: const <String>[crossNamespaceArgument, entrypointArgument],
      ports: const <String>['postgres:5432'],
    );
    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    final String patch = machine.changing.first;
    expect(patch, contains(entrypointArgument));
    expect(patch, contains('"hostPort":5432'));
    expect(patch, contains('"containerPort":5432'));
    expect(patch, contains('"name":"postgres"'));
  });

  test('an argument that is there but a port that is not gets only the port', () async {
    // The argument alone gives an address nothing can connect to.
    final ClusterMachine machine = withController(
      declared: const <String>[crossNamespaceArgument, entrypointArgument],
      pods: const <String, PodState>{
        'traefik-old': PodState(
          phase: 'Running',
          arguments: <String>[crossNamespaceArgument, entrypointArgument],
        ),
      },
    );

    await asking(
      arguments: const <String>[crossNamespaceArgument, entrypointArgument],
      ports: const <String>['postgres:5432'],
    ).apply(machine.contextFor(under));

    final String patch = machine.changing.first;
    expect(patch, contains('"hostPort":5432'));
    expect(
      patch,
      isNot(contains('args/-')),
      reason: 'the argument is already there and adding it again would duplicate it',
    );
  });

  test('a port written wrong blocks the row, naming the entry', () async {
    // Left out and reported green, the port is never published and nothing downstream says
    // otherwise — a plain-TCP entry point simply does not answer.
    final ClusterMachine machine = withController(
      declared: const <String>[crossNamespaceArgument],
      pods: const <String, PodState>{
        'traefik-old': PodState(phase: 'Running', arguments: <String>[crossNamespaceArgument]),
      },
    );
    final CheckResult answer = await asking(
      ports: const <String>['postgres'],
    ).check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('"postgres" is not a port'));
    expect(machine.changing, isEmpty);
  });

  test('the plan of a machine short of the argument names the pod deletion', () async {
    // On a fresh install the declaration is short of the argument AND the serving pod lags it:
    // the apply patches and then deletes that pod, so the plan has to name the deletion — the
    // half that cannot be taken back — and say the rest beside it.
    final ClusterMachine machine = withController(
      declared: const <String>['--entrypoints.web.address=:8000/tcp'],
      pods: const <String, PodState>{
        'traefik-old': PodState(
          phase: 'Running',
          arguments: <String>['--entrypoints.web.address=:8000/tcp'],
        ),
      },
    );
    final StepContext context = machine.contextFor(under);
    expect(await asking().check(context), isA<Ready>());
    final StepPlan plan = await asking().plan(context);
    expect(plan.summary, 'kubectl -n ingress delete pod traefik-old --grace-period=10');
    expect(
      machine.said.join('\n'),
      contains('patch daemonset traefik'),
      reason: 'the patch that precedes the deletion is said in the log the plan leaves behind',
    );
    expect(machine.said.join('\n'), contains('nothing answers on the ports'));
  });

  test('a workload with no pod to delete plans the patch itself', () async {
    final ClusterMachine machine = withController(
      declared: const <String>['--entrypoints.web.address=:8000/tcp'],
    );
    final StepPlan plan = await asking().plan(machine.contextFor(under));
    expect(plan.summary, contains('patch daemonset traefik'));
    expect(plan.summary, contains(crossNamespaceArgument));
  });

  test('asking for nothing is a step with nothing to do', () async {
    expect(
      await asking(arguments: const <String>[]).check(ClusterMachine().contextFor(under)),
      isA<Satisfied>(),
    );
  });

  test('a pod still serving with what it was started with is replaced, stuck ones first', () async {
    // Patching the declaration reports success and does not reach the pod: on one machine the
    // replacement cannot be created while the old pod holds the machine's ports. Reversed, the
    // replacement lands while a stuck pod still claims them and the whole deadlock happens again.
    final ClusterMachine machine = withController(
      declared: const <String>[crossNamespaceArgument],
      pods: const <String, PodState>{
        'traefik-wedged': PodState(phase: 'Pending'),
        'traefik-old': PodState(
          phase: 'Running',
          arguments: <String>['--entrypoints.web.address=:8000/tcp'],
        ),
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
      'kubectl -n ingress delete pod traefik-wedged --grace-period=0 --force',
      'kubectl -n ingress delete pod traefik-old --grace-period=10',
      'kubectl -n ingress rollout status daemonset/traefik --timeout=90s',
    ]);
  });

  test('a pod running with the same value under a different port is replaced too', () async {
    final ClusterMachine machine = withController(
      declared: const <String>[crossNamespaceArgument, entrypointArgument],
      declaredPorts: const <String, int>{'postgres': 5432},
      pods: const <String, PodState>{
        'traefik-old': PodState(
          phase: 'Running',
          arguments: <String>[crossNamespaceArgument, entrypointArgument],
        ),
      },
    );
    final PatchContainerArgumentsAndPorts step = asking(
      arguments: const <String>[crossNamespaceArgument, entrypointArgument],
      ports: const <String>['postgres:5432'],
    );
    expect(
      await step.check(machine.contextFor(under)),
      isA<Ready>(),
      reason: 'the declaration publishes the port and the running pod does not',
    );
  });

  test('no pod at all is a skip, not a failure', () async {
    final ClusterMachine machine = withController(declared: const <String>[crossNamespaceArgument]);
    expect(await asking().check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test(
    'what was already there is left alone, and only what this run added comes back out',
    () async {
      final ClusterMachine machine = withController(
        declared: const <String>[crossNamespaceArgument],
        pods: const <String, PodState>{
          'traefik-old': PodState(phase: 'Running', arguments: <String>[crossNamespaceArgument]),
        },
      );
      final PatchContainerArgumentsAndPorts step = asking(
        arguments: const <String>[crossNamespaceArgument, entrypointArgument],
      );
      final StepContext context = machine.contextFor(under);

      final ContainerAdditions added = await step.capture(context);
      expect(
        added.arguments,
        <String>[entrypointArgument],
        reason:
            'an argument the controller carried before this ran belongs to whoever put it there',
      );

      machine.shell.answers(
        traefikDaemonSet,
        workloadJson(
          container: 'traefik',
          arguments: const <String>[crossNamespaceArgument, entrypointArgument],
        ),
      );
      await step.undo(context, added);
      expect(
        machine.changing.first,
        contains('{"op":"remove","path":"/spec/template/spec/containers/0/args/1"}'),
      );
    },
  );

  test('an undo whose removal patch is rejected throws and deletes no pod', () async {
    // Recorded as taken back over a rejected patch, the pods that come back still carry what
    // the record says was removed.
    final ClusterMachine machine = withController(
      declared: const <String>[crossNamespaceArgument, entrypointArgument],
      pods: const <String, PodState>{
        'traefik-old': PodState(
          phase: 'Running',
          arguments: <String>[crossNamespaceArgument, entrypointArgument],
        ),
      },
    );
    machine.shell.fails(
      'kubectl -n ingress patch daemonset traefik --type=json -p '
      '[{"op":"remove","path":"/spec/template/spec/containers/0/args/1"}]',
    );
    await expectLater(
      asking().undo(
        machine.contextFor(under),
        const ContainerAdditions(arguments: <String>[entrypointArgument], ports: <int>[]),
      ),
      throwsA(isA<CommandFailed>()),
    );
    expect(machine.changing.join('\n'), isNot(contains('delete pod')));
  });

  test('an undo removes a published port by its place in the whole ports list', () async {
    // The container declares an entry publishing nothing ahead of the published one, and the
    // patch path resolves against the whole list — a position counted among the published ports
    // alone would remove the wrong element, one this step never added.
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers(
        traefikDaemonSet,
        jsonEncode(<String, Object>{
          'spec': <String, Object>{
            'selector': <String, Object>{
              'matchLabels': <String, Object>{'app.kubernetes.io/name': 'traefik'},
            },
            'template': <String, Object>{
              'spec': <String, Object>{
                'containers': <Object>[
                  <String, Object>{
                    'name': 'traefik',
                    'args': <String>[crossNamespaceArgument],
                    'ports': <Object>[
                      <String, Object>{'name': 'metrics', 'containerPort': 9100},
                      <String, Object>{
                        'name': 'postgres',
                        'containerPort': 5432,
                        'hostPort': 5432,
                        'protocol': 'TCP',
                      },
                    ],
                  },
                ],
              },
            },
          },
        }),
      )
      ..answers(traefikPods, podsJson(const <String, PodState>{}));

    await asking().undo(
      machine.contextFor(under),
      const ContainerAdditions(arguments: <String>[], ports: <int>[5432]),
    );
    expect(
      machine.changing.first,
      contains('{"op":"remove","path":"/spec/template/spec/containers/0/ports/1"}'),
    );
  });
}
