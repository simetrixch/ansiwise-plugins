import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The network agent's packet-filtering backend, held to the one this machine filters with.
///
/// **What these tests assert is where the agent's rules END UP, not what its settings say.** The two
/// come apart exactly where this step earns its keep: an agent set to work the backend out for
/// itself carries a perfectly valid setting and can still paint every rule into the table the
/// machine does not filter with. So the fake cluster below models the outcome — [_Calico] holds the
/// setting AND the table the rules are in, and moves the rules when the setting changes — and the
/// tests read the table.
void main() {
  const StepName under = StepName('align_calico_backend');

  test('an agent left to work it out for itself paints into the wrong table, and is pinned', () async {
    // The machine filters with nft. Its agent, on Auto, works the backend out as legacy: measured on
    // a bare machine, 15 cali chains in the legacy tables and none in nft, so the masquerade for the
    // pod network stood where nothing reads it and no pod could reach anything off the machine.
    final _Calico calico = _Calico(setting: 'Auto', paintsInto: 'legacy');
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120, backend: 'nft');

    expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());
    expect(
      calico.paintsInto,
      'nft',
      reason:
          'the pod network is masqueraded in the table this machine filters with, or not at all',
    );
  });

  test('a machine filtering with the older backend ends on the older backend', () async {
    final _Calico calico = _Calico(setting: 'Auto', paintsInto: 'nft');
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoBackend step = AlignCalicoBackend(
      rolloutTimeoutSeconds: 120,
      backend: 'legacy',
    );

    expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());
    expect(
      calico.paintsInto,
      'legacy',
      reason:
          'a machine on the older backend is held to the older backend, never to the modern one',
    );
  });

  test(
    'an agent already on the backend of this machine is left alone, and says which one',
    () async {
      final _Calico calico = _Calico(setting: 'NFT', paintsInto: 'nft');
      final ClusterMachine machine = calico.on(ClusterMachine());
      const AlignCalicoBackend step = AlignCalicoBackend(
        rolloutTimeoutSeconds: 120,
        backend: 'nft',
      );

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Satisfied).because, allOf(contains('NFT'), contains('nft')));
      expect(machine.changing, isEmpty);
      expect(calico.paintsInto, 'nft');
    },
  );

  test('an agent pinned against this machine is repinned, and no rule is touched', () async {
    final _Calico calico = _Calico(setting: 'Legacy', paintsInto: 'legacy');
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120, backend: 'nft');

    expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());
    expect(calico.paintsInto, 'nft');
    expect(
      machine.changing.join('\n'),
      isNot(anyOf(contains('iptables -F'), contains('iptables-legacy'))),
      reason: 'flushing the other backend wiped the ingress translation rules once',
    );
  });

  test('what it did is said at a level the run writes', () async {
    final _Calico calico = _Calico(setting: 'Auto', paintsInto: 'legacy');
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120, backend: 'nft');

    await step.apply(machine.contextFor(under));

    expect(
      machine.said.join('\n'),
      contains('pinned to NFT'),
      reason: 'a run whose network depends on this carries the backend it aligned the agent to',
    );
  });

  test('a replacement that does not converge is written into the record', () async {
    final ClusterMachine machine = _Calico(setting: 'Auto', paintsInto: 'legacy').on(
      ClusterMachine(),
    )..shell.fails('kubectl -n kube-system rollout status daemonset/calico-node --timeout=120s');
    const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120, backend: 'nft');

    await step.apply(machine.contextFor(under));

    expect(
      machine.said.join('\n'),
      contains('not finished being replaced within 120s'),
      reason: 'the pin stands, and what the run did not get to watch is not passed over',
    );
  });

  test('a machine nothing measured is refused, not held to a backend', () async {
    // Nothing here is a defect of the cluster: the row above this one measures the machine and
    // publishes the value, and it is allowed to fail. Pinning the agent to a fallback would set the
    // cluster's packet filtering from a value nobody read and report it as an alignment.
    final ClusterMachine machine = _Calico(
      setting: 'Auto',
      paintsInto: 'legacy',
    ).on(ClusterMachine());
    const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120);

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('nothing measured'));
    expect(machine.changing, isEmpty);
  });

  test('a backend this step does not know is refused rather than read as the modern one', () async {
    final ClusterMachine machine = _Calico(
      setting: 'Auto',
      paintsInto: 'legacy',
    ).on(ClusterMachine());
    const AlignCalicoBackend step = AlignCalicoBackend(
      rolloutTimeoutSeconds: 120,
      backend: 'iptables',
    );

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('"iptables" is not a backend'));
    expect(machine.changing, isEmpty);
  });

  test('an agent that is not up yet is refused', () async {
    final ClusterMachine machine = ClusterMachine()..shell.fails(_Calico.readSetting);
    const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120, backend: 'nft');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('has to be up'));
  });

  test('an agent started with the backend of this machine needs no pin at all', () async {
    // The value the agent STARTS with outranks the settings object, so an agent started on this
    // machine's backend is aligned however its settings object reads.
    final _Calico calico = _Calico(setting: 'Auto', paintsInto: 'nft', startedWith: 'NFT');
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120, backend: 'nft');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Satisfied).because, contains('FELIX_IPTABLESBACKEND=NFT'));
    expect(machine.changing, isEmpty);
  });

  test(
    'an agent started against this machine is refused, because the pin would do nothing',
    () async {
      final _Calico calico = _Calico(setting: 'Auto', paintsInto: 'legacy', startedWith: 'Legacy');
      final ClusterMachine machine = calico.on(ClusterMachine());
      const AlignCalicoBackend step = AlignCalicoBackend(
        rolloutTimeoutSeconds: 120,
        backend: 'nft',
      );

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect(
        (answer as Blocked).reason,
        allOf(contains('FELIX_IPTABLESBACKEND=Legacy'), contains('outranks')),
      );
      expect(machine.changing, isEmpty, reason: 'a patch that cannot take is not issued');
    },
  );

  test('the pin the agent carried is what an undo puts back', () async {
    final _Calico calico = _Calico(setting: 'Legacy', paintsInto: 'legacy');
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120, backend: 'nft');

    final StepContext context = machine.contextFor(under);
    final String? captured = await step.capture(context);
    await step.apply(context);
    await step.undo(context, captured);

    expect(calico.paintsInto, 'legacy', reason: 'the pin read before the change is what goes back');
  });

  test('an agent carrying no pin is put back to working it out for itself', () async {
    final _Calico calico = _Calico(setting: '', paintsInto: 'legacy');
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120, backend: 'nft');

    final StepContext context = machine.contextFor(under);
    final String? captured = await step.capture(context);
    await step.apply(context);
    await step.undo(context, captured);

    expect(calico.setting, 'Auto');
  });
}

/// Runs [step] against [context] the way the engine runs it, and answers what it says afterwards.
///
/// A step is applied only where its check has work, and its check is asked again once it has been —
/// so a check that answers Satisfied over an agent that has not been pinned leaves the machine
/// exactly as it found it. That is why the tests above assert where the RULES ended up: a verdict
/// cannot tell "there was nothing to do" from "nothing was done", and the machine can.
Future<CheckResult> _drive(AlignCalicoBackend step, StepContext context) async {
  if (await step.check(context) is Ready) {
    await step.apply(context);
  }
  return step.check(context);
}

/// A network agent on a fake cluster, holding BOTH its setting and the table its rules are in.
///
/// The setting is what a step reads. The table is what the machine's packets meet, and it is what
/// these tests assert on — the two are only the same fact once something has pinned the setting,
/// which is the whole of what the step under test is for.
///
/// [paintsInto] is where the agent has its rules right now. While the setting is `Auto` the agent
/// works the backend out for itself and nothing here changes that; the moment the setting names a
/// backend, the agent repaints into it.
final class _Calico {
  _Calico({required this.setting, required this.paintsInto, this.startedWith = ''});

  /// How the agent's settings object is read.
  static const String readSetting =
      'kubectl get felixconfiguration/default -o jsonpath={.spec.iptablesBackend}';

  /// How the value the agent is STARTED with is read off the set it runs as.
  static const String readStarted =
      'kubectl -n kube-system get daemonset calico-node -o '
      'jsonpath={.spec.template.spec.containers[0].env[?(@.name=="FELIX_IPTABLESBACKEND")].value}';

  /// What the agent's settings object says: `Auto`, `Legacy`, `NFT`, or nothing at all.
  String setting;

  /// Which of the machine's two rule sets the agent's chains are actually in.
  String paintsInto;

  /// What the set the agent runs as declares in its environment, empty where it declares nothing.
  final String startedWith;

  /// Arranges [machine] to answer for this agent, and returns it.
  ClusterMachine on(ClusterMachine machine) {
    machine.shell
      ..answers(readSetting, '$setting\n')
      ..answers(readStarted, startedWith)
      ..changes(_patch('NFT'), () => _pin(machine, 'NFT', 'nft'))
      ..changes(_patch('Legacy'), () => _pin(machine, 'Legacy', 'legacy'))
      ..changes(_patch('Auto'), () => _pin(machine, 'Auto', paintsInto));
    return machine;
  }

  void _pin(ClusterMachine machine, String pinned, String table) {
    setting = pinned;
    paintsInto = table;
    machine.shell.answers(readSetting, '$setting\n');
  }

  static String _patch(String backend) =>
      'kubectl patch felixconfiguration/default --type merge -p '
      '{"spec":{"iptablesBackend":"$backend"}}';
}
