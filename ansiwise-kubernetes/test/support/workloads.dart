import 'dart:convert';

/// One pod of a fixture: which phase it is in and what its container is running with.
final class PodState {
  /// A pod in [phase], running with [arguments] and publishing [ports].
  const PodState({
    required this.phase,
    this.arguments = const <String>[],
    this.ports = const <String, int>{},
  });

  /// Which phase the pod is in.
  final String phase;

  /// What its container was started with.
  final List<String> arguments;

  /// What it publishes on the machine.
  final Map<String, int> ports;
}

/// A workload holding one container called [container], started with [arguments].
///
/// [ports] are the ports it publishes on the machine, each written as its name and the port it
/// answers on — the shape a container declares them in, so a step reads this the way it reads a real
/// one. [selector] is what the workload says its own pods are labelled with.
String workloadJson({
  required String container,
  required List<String> arguments,
  Map<String, int> ports = const <String, int>{},
  Map<String, String> selector = const <String, String>{'app.kubernetes.io/name': 'traefik'},
}) => jsonEncode(<String, Object>{
  'spec': <String, Object>{
    'selector': <String, Object>{'matchLabels': selector},
    'template': <String, Object>{
      'spec': <String, Object>{
        'containers': <Object>[containerJson(container, arguments, ports)],
      },
    },
  },
});

/// The pods of a workload: one per entry of [pods], in the phase and with the container that entry
/// names.
String podsJson(Map<String, PodState> pods, {String container = 'traefik'}) => jsonEncode(
  <String, Object>{
    'items': <Object>[
      for (final MapEntry<String, PodState> pod in pods.entries)
        <String, Object>{
          'metadata': <String, Object>{'name': pod.key},
          'status': <String, Object>{'phase': pod.value.phase},
          'spec': <String, Object>{
            'containers': <Object>[containerJson(container, pod.value.arguments, pod.value.ports)],
          },
        },
    ],
  },
);

/// One container as the cluster declares it, publishing every port of [ports] on the machine.
Map<String, Object> containerJson(
  String container,
  List<String> arguments,
  Map<String, int> ports,
) => <String, Object>{
  'name': container,
  'args': arguments,
  'ports': <Object>[
    for (final MapEntry<String, int> port in ports.entries)
      <String, Object>{
        'name': port.key,
        'containerPort': port.value,
        'hostPort': port.value,
        'protocol': 'TCP',
      },
  ],
};
