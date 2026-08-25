import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The network agent's masquerade, held to the source ports this machine opens its own connections
/// from.
///
/// **What these tests assert is which source ports a rewritten connection can END UP with, not what
/// the settings object says.** The two come apart exactly where this step earns its keep: an agent
/// that was never told a range carries a perfectly valid configuration and still hands out ports the
/// network the machine hangs on has no way back for. So the fake cluster below models the outcome —
/// [_Calico] holds the setting AND the ports its masquerade may hand out, and moves the second when
/// the first changes — and the tests read the ports.
///
/// The numbers are the ones measured on a machine that had this defect: the machine opened its own
/// connections from 32768 through 60999, the network carried the answer back for exactly those, and
/// a pod behind an agent that was never told a range scored 11 of 20 to a public address on 443
/// while the machine itself scored 20 of 20. Every unanswered attempt had been given a source port
/// below 32768.
void main() {
  const StepName under = StepName('align_calico_nat_port_range');

  test(
    'an agent nothing narrowed hands out ports the network never answers, and is narrowed',
    () async {
      final _Calico calico = _Calico(setting: '');
      final ClusterMachine machine = calico.on(ClusterMachine());
      const AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: _hostRange);

      expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());
      expect(
        _unanswered(calico.handsOut, machine: _hostPorts),
        isEmpty,
        reason:
            'every source port the agent may give a rewritten connection is one this machine opens '
            'its own connections from, or the answer to that connection has no way back',
      );
      expect(calico.handsOut, _hostPorts);
    },
  );

  test('a machine tuned to other ports hands those on, so no range is written down here', () async {
    // The same step on a machine whose kernel is set differently. Nothing here knows 32768: what a
    // pod masquerades out of is whatever the row above measured, which is what makes this a rule
    // about any network rather than about the one it was found on.
    final _Calico calico = _Calico(setting: '');
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: '10000 20000');

    expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());
    expect(calico.handsOut, const _Ports(10000, 20000));
    expect(_unanswered(calico.handsOut, machine: const _Ports(10000, 20000)), isEmpty);
  });

  test('an agent on a range this machine does not use is narrowed to the one it does', () async {
    final _Calico calico = _Calico(setting: _wideRange);
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: _hostRange);

    expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());
    expect(_unanswered(calico.handsOut, machine: _hostPorts), isEmpty);
    expect(calico.handsOut, _hostPorts);
  });

  test(
    "an agent already on this machine's ports is left alone, whichever way it is spelled",
    () async {
      // The machine writes its two port numbers with whitespace between and the agent writes them
      // with a colon. Compared as text, an agent that had already been narrowed would be patched
      // again on every run and the step would never be finished.
      final _Calico calico = _Calico(setting: _agentRange);
      final ClusterMachine machine = calico.on(ClusterMachine());
      const AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: _hostRange);

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Satisfied).because, allOf(contains(_agentRange), contains(_hostRange)));
      expect(machine.changing, isEmpty);
      expect(calico.handsOut, _hostPorts);
    },
  );

  test('what it did is said at a level the run writes', () async {
    final ClusterMachine machine = _Calico(setting: '').on(ClusterMachine());
    const AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: _hostRange);

    await step.apply(machine.contextFor(under));

    expect(
      machine.said.join('\n'),
      contains('out of ports $_agentRange'),
      reason: 'a run whose network depends on this carries the ports it narrowed the agent to',
    );
  });

  test('a machine nothing measured is refused, not narrowed to a guess', () async {
    // Nothing here is a defect of the cluster: the row above this one measures the machine and
    // publishes the value, and it is allowed to fail. Narrowing the masquerade to a range nobody
    // read would cut off whatever the guess left out and report it as an alignment.
    final ClusterMachine machine = _Calico(setting: '').on(ClusterMachine());
    const AlignCalicoNatPortRange step = AlignCalicoNatPortRange();

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('nothing measured'));
    expect(machine.changing, isEmpty);
  });

  // Five shapes a row could hand over that are not a range of ports, each refused rather than
  // written into the cluster: a word, one number, three numbers, a number that is no port, and two
  // ports the wrong way round.
  for (final String refused in <String>[
    'x',
    '32768',
    '32768 60999 61000',
    '0 60999',
    '60999 32768',
  ]) {
    test(
      '"$refused" is no port range and is refused rather than written into the cluster',
      () async {
        final ClusterMachine machine = _Calico(setting: '').on(ClusterMachine());
        final AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: refused);

        final CheckResult answer = await step.check(machine.contextFor(under));
        expect((answer as Blocked).reason, contains('"$refused" is no port range'));
        expect(machine.changing, isEmpty);
      },
    );
  }

  test('an agent that is not up yet is refused', () async {
    final ClusterMachine machine = ClusterMachine()..shell.fails(_Calico.readSetting);
    const AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: _hostRange);

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('has to be up'));
  });

  test('an agent started with the ports of this machine needs no patch at all', () async {
    // The value the agent STARTS with outranks the settings object, so an agent started on this
    // machine's ports is aligned however its settings object reads.
    final _Calico calico = _Calico(setting: '', startedWith: _agentRange);
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: _hostRange);

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Satisfied).because, contains('FELIX_NATPORTRANGE=$_agentRange'));
    expect(machine.changing, isEmpty);
  });

  test(
    'an agent started against this machine is refused, because the patch would do nothing',
    () async {
      final _Calico calico = _Calico(setting: '', startedWith: _wideRange);
      final ClusterMachine machine = calico.on(ClusterMachine());
      const AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: _hostRange);

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect(
        (answer as Blocked).reason,
        allOf(contains('FELIX_NATPORTRANGE=$_wideRange'), contains('outranks')),
      );
      expect(machine.changing, isEmpty, reason: 'a patch that cannot take is not issued');
    },
  );

  test('the range the agent carried is what an undo puts back', () async {
    final _Calico calico = _Calico(setting: _wideRange);
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: _hostRange);

    final StepContext context = machine.contextFor(under);
    final String? captured = await step.capture(context);
    await step.apply(context);
    await step.undo(context, captured);

    expect(
      calico.handsOut,
      const _Ports(1024, 65535),
      reason: 'the range read before the change is what goes back',
    );
  });

  test('an agent that carried no range is left carrying none', () async {
    // Putting the widest range back instead would leave a field standing on the settings object
    // that was not there before the run, and the next reader could not tell it from one somebody set
    // on purpose.
    final _Calico calico = _Calico(setting: '');
    final ClusterMachine machine = calico.on(ClusterMachine());
    const AlignCalicoNatPortRange step = AlignCalicoNatPortRange(portRange: _hostRange);

    final StepContext context = machine.contextFor(under);
    final String? captured = await step.capture(context);
    await step.apply(context);
    await step.undo(context, captured);

    expect(calico.setting, isEmpty);
    expect(calico.handsOut, _wholePortSpace);
  });
}

/// What the machine opens its own connections from, as the row that measured it hands it over.
const String _hostRange = '32768 60999';

/// The same two numbers as the agent spells a range.
const String _agentRange = '32768:60999';

/// A range these tests find an agent already carrying, which is not this machine's.
const String _wideRange = '1024:65535';

/// The ports the machine of these tests opens its own connections from.
const _Ports _hostPorts = _Ports(32768, 60999);

/// What an agent that was never told a range may hand out.
const _Ports _wholePortSpace = _Ports(1, 65535);

/// The ports [handsOut] carries that [machine] does not, as the ranges they form.
///
/// Empty is the whole of what this step is for: every source port the agent may give a rewritten
/// connection is one the network carries the answer back for, because it is one the machine itself
/// opens. An agent that was never told a range produces `1:32767` and `61000:65535` here against the
/// machine of these tests, and the first of those two is where every timed-out connection of the
/// measurement sat.
List<String> _unanswered(_Ports handsOut, {required _Ports machine}) => <String>[
  if (handsOut.low < machine.low) '${handsOut.low}:${machine.low - 1}',
  if (handsOut.high > machine.high) '${machine.high + 1}:${handsOut.high}',
];

/// Runs [step] against [context] the way the engine runs it, and answers what it says afterwards.
///
/// A step is applied only where its check has work, and its check is asked again once it has been —
/// so a check that answers Satisfied over an agent that has not been narrowed leaves the machine
/// exactly as it found it. That is why the tests above assert which PORTS the agent may hand out: a
/// verdict cannot tell "there was nothing to do" from "nothing was done", and the machine can.
Future<CheckResult> _drive(AlignCalicoNatPortRange step, StepContext context) async {
  if (await step.check(context) is Ready) {
    await step.apply(context);
  }
  return step.check(context);
}

/// A network agent on a fake cluster, holding BOTH its setting and the ports its masquerade hands
/// out.
///
/// The setting is what a step reads. The ports are what a packet leaving this machine carries, and
/// they are what these tests assert on — the two are only the same fact once something has narrowed
/// the setting, which is the whole of what the step under test is for.
final class _Calico {
  _Calico({required this.setting, this.startedWith = ''});

  /// How the agent's settings object is read.
  static const String readSetting =
      'kubectl get felixconfiguration/default -o jsonpath={.spec.natPortRange}';

  /// How the value the agent is STARTED with is read off the set it runs as.
  static const String readStarted =
      'kubectl -n kube-system get daemonset calico-node -o '
      'jsonpath={.spec.template.spec.containers[0].env[?(@.name=="FELIX_NATPORTRANGE")].value}';

  /// Every range these tests write, so the fake carries the patch out the way a cluster would.
  ///
  /// A fake shell answers a command by its exact words, so each patch this step could issue is
  /// arranged here. Null is the field being taken away again, which is what an undo writes onto an
  /// agent that carried no range.
  static const List<String?> _written = <String?>[_agentRange, _wideRange, '10000:20000', null];

  /// What the agent's settings object says, empty where it names no range at all.
  String setting;

  /// What the set the agent runs as declares in its environment, empty where it declares nothing.
  final String startedWith;

  /// The source ports the masquerade may give a rewritten connection.
  ///
  /// An agent carrying no range picks out of the whole port space, which is the state the machine
  /// with this defect was found in; the moment the setting names a range, that is what it picks
  /// from.
  _Ports get handsOut => _Ports.read(setting) ?? _wholePortSpace;

  /// Arranges [machine] to answer for this agent, and returns it.
  ClusterMachine on(ClusterMachine machine) {
    machine.shell
      ..answers(readSetting, '$setting\n')
      ..answers(readStarted, startedWith);
    for (final String? range in _written) {
      machine.shell.changes(_patch(range), () => _write(machine, range));
    }
    return machine;
  }

  void _write(ClusterMachine machine, String? range) {
    setting = range ?? '';
    machine.shell.answers(readSetting, '$setting\n');
  }

  static String _patch(String? range) =>
      'kubectl patch felixconfiguration/default --type merge -p '
      '{"spec":{"natPortRange":${range == null ? 'null' : '"$range"'}}}';
}

/// Two port numbers, the lower one first.
final class _Ports {
  /// Names the range from [low] to [high].
  const _Ports(this.low, this.high);

  /// The range [value] names, or null where it names none.
  static _Ports? read(String value) {
    final List<String> numbers = value.split(':').where((String each) => each.isNotEmpty).toList();
    if (numbers.length != 2) {
      return null;
    }
    final int? low = int.tryParse(numbers.first);
    final int? high = int.tryParse(numbers.last);
    return low == null || high == null ? null : _Ports(low, high);
  }

  /// The lowest port of the range.
  final int low;

  /// The highest port of the range.
  final int high;

  @override
  bool operator ==(Object other) => other is _Ports && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(low, high);

  @override
  String toString() => '$low:$high';
}
