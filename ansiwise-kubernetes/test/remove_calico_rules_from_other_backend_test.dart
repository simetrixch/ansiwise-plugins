import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

/// The rules the network agent abandoned in the backend it no longer writes to.
///
/// **What these tests assert is the RULESET the machine is left holding, not the commands issued.**
/// The fake below is a packet-filtering backend in memory: `iptables-<backend>-save` renders what it
/// holds, and `-D`, `-F` and `-X` change it the way the real programs do, including refusing to
/// delete a chain something still jumps to. So a test reads chains and rules afterwards, and a step
/// that issued a beautiful sequence of commands that did not take effect fails here.
void main() {
  const StepName under = StepName('remove_calico_rules_from_other_backend');

  test('the abandoned backend loses every agent chain, and keeps everything else', () async {
    final _Backend legacy = _Backend()
      ..builtIn('filter', 'FORWARD', <String>[
        '-s 10.244.0.0/16 -m comment --comment "generated for the distribution pods" -j ACCEPT',
        '-m comment --comment "cali:wUHhoiAYhphO9Mso" -j cali-FORWARD',
        '-d 10.244.0.0/16 -m comment --comment "generated for the distribution pods" -j ACCEPT',
      ])
      ..chain('filter', 'cali-FORWARD', <String>['-j cali-from-wl-dispatch'])
      ..chain('filter', 'cali-from-wl-dispatch', <String>['-j DROP'])
      ..builtIn('nat', 'POSTROUTING', <String>[
        '-m comment --comment "CNI portfwd requiring masquerade" -j CNI-HOSTPORT-MASQ',
        '-m comment --comment "cali:0i8pjzKKPyA34aQD" -j cali-POSTROUTING',
      ])
      ..chain('nat', 'cali-POSTROUTING', <String>['-j MASQUERADE']);
    final _Machine machine = _machine(legacy, pinnedTo: 'NFT');

    const RemoveCalicoRulesFromOtherBackend step = RemoveCalicoRulesFromOtherBackend(
      backend: 'nft',
    );
    expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());

    expect(
      legacy.chainNames('filter'),
      isEmpty,
      reason: 'an agent chain left standing is a chain the kernel still evaluates',
    );
    expect(legacy.chainNames('nat'), isEmpty);
    expect(
      legacy.rulesOf('filter', 'FORWARD'),
      <String>[
        '-s 10.244.0.0/16 -m comment --comment "generated for the distribution pods" -j ACCEPT',
        '-d 10.244.0.0/16 -m comment --comment "generated for the distribution pods" -j ACCEPT',
      ],
      reason:
          'THE INNOCENT NEIGHBOURS: the distribution\'s own forwarding rules for the pod network '
          'sit in the same chain, one on each side of the jump that goes, and both stay — '
          'emptying the table would take them with it',
    );
    expect(
      legacy.rulesOf('nat', 'POSTROUTING'),
      <String>['-m comment --comment "CNI portfwd requiring masquerade" -j CNI-HOSTPORT-MASQ'],
      reason:
          'the translation rule for a published port is what an emptied table breaks silently, so '
          'it is asserted by name',
    );
  });

  test('EVERY packet-filter call waits for the lock, dump and rule alike', () async {
    // THE RACE THIS STEP LOSES. Both programs take /run/xtables.lock for one call, and so does the
    // network agent, which is writing its own rules the whole time this runs. Measured on a real
    // machine: the step ran green twice and failed on the third, seventy chains into the sweep —
    // `iptables-legacy -t nat -X cali-fip-dnat returned 4`, "Resource temporarily unavailable". The
    // install stopped at three of five programs, and a retry would very likely have passed and
    // taught nothing. So the check is not "does it clean up" — the cases above ask that — but "did
    // it ever ask to wait", of every single call.
    final _Backend legacy = _Backend()
      ..builtIn('filter', 'FORWARD', <String>[
        '-m comment --comment "cali:wUHhoiAYhphO9Mso" -j cali-FORWARD',
      ])
      ..chain('filter', 'cali-FORWARD', <String>['-j cali-from-wl-dispatch'])
      ..chain('filter', 'cali-from-wl-dispatch', <String>['-j DROP']);
    final _Machine machine = _machine(legacy, pinnedTo: 'NFT');

    const RemoveCalicoRulesFromOtherBackend step = RemoveCalicoRulesFromOtherBackend(
      backend: 'nft',
    );
    expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());

    expect(machine.ruled, isNotEmpty, reason: 'the step made no rule call at all');
    expect(
      machine.ruled.every((bool each) => each),
      isTrue,
      reason:
          '${machine.ruled.where((bool e) => !e).length} of '
          '${machine.ruled.length} rule calls went at the lock without waiting',
    );
    expect(
      machine.dumped.any((bool each) => each),
      isFalse,
      reason: 'a dump asked to wait, and iptables-save refuses the whole call when it is handed -w',
    );
  });

  test('the backend the agent DOES write to is untouched', () async {
    final _Backend nft = _Backend()
      ..builtIn('filter', 'FORWARD', <String>[
        '-m comment --comment "cali:wUHhoiAYhphO9Mso" -j cali-FORWARD',
      ])
      ..chain('filter', 'cali-FORWARD', <String>['-j DROP']);
    // The machine filters with nft, so nft is what the agent is pinned to and legacy is what would
    // be cleaned. Nothing here answers for legacy at all, so nothing is found there.
    final _Machine machine = _machine(nft, pinnedTo: 'NFT', backend: 'nft');

    const RemoveCalicoRulesFromOtherBackend step = RemoveCalicoRulesFromOtherBackend(
      backend: 'nft',
    );
    expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());

    expect(nft.chainNames('filter'), <String>[
      'cali-FORWARD',
    ], reason: 'the live set is the one the cluster\'s whole network runs through');
  });

  test('an agent still on the other backend blocks the step instead of being taken apart', () async {
    final _Backend legacy = _Backend()
      ..builtIn('filter', 'FORWARD', <String>[
        '-m comment --comment "cali:wUHhoiAYhphO9Mso" -j cali-FORWARD',
      ])
      ..chain('filter', 'cali-FORWARD', <String>['-j DROP']);
    // The machine filters with nft, but the pin has not landed: the agent still says Legacy, so the
    // rules in legacy are the ones it is writing.
    final _Machine machine = _machine(legacy, pinnedTo: 'Legacy');

    const RemoveCalicoRulesFromOtherBackend step = RemoveCalicoRulesFromOtherBackend(
      backend: 'nft',
    );
    expect(await step.check(machine.contextFor(under)), isA<Blocked>());
    expect(legacy.chainNames('filter'), <String>[
      'cali-FORWARD',
    ], reason: 'removing the set an unpinned agent is still writing takes the cluster off the air');
  });

  test('an agent carrying no pin at all blocks it too', () async {
    final _Backend legacy = _Backend()
      ..builtIn('filter', 'FORWARD', <String>[
        '-m comment --comment "cali:wUHhoiAYhphO9Mso" -j cali-FORWARD',
      ])
      ..chain('filter', 'cali-FORWARD', <String>['-j DROP']);
    final _Machine machine = _machine(legacy, pinnedTo: '');

    const RemoveCalicoRulesFromOtherBackend step = RemoveCalicoRulesFromOtherBackend(
      backend: 'nft',
    );
    expect(
      await step.check(machine.contextFor(under)),
      isA<Blocked>(),
      reason:
          'an agent working the backend out for itself may pick this one again at its next start, '
          'so what stands there is not abandoned',
    );
  });

  test('a backend that holds nothing of the agent is already satisfied', () async {
    final _Backend legacy = _Backend()..builtIn('filter', 'FORWARD', <String>['-j ACCEPT']);
    final _Machine machine = _machine(legacy, pinnedTo: 'NFT');

    const RemoveCalicoRulesFromOtherBackend step = RemoveCalicoRulesFromOtherBackend(
      backend: 'nft',
    );
    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
  });

  test('nothing measured the machine, so nothing is removed on a guess', () async {
    final _Backend legacy = _Backend()
      ..builtIn('filter', 'FORWARD', <String>[
        '-m comment --comment "cali:wUHhoiAYhphO9Mso" -j cali-FORWARD',
      ])
      ..chain('filter', 'cali-FORWARD', <String>['-j DROP']);
    final _Machine machine = _machine(legacy, pinnedTo: 'NFT');

    const RemoveCalicoRulesFromOtherBackend step = RemoveCalicoRulesFromOtherBackend();
    expect(await step.check(machine.contextFor(under)), isA<Blocked>());
    expect(legacy.chainNames('filter'), <String>['cali-FORWARD']);
  });

  test('two jumps in one chain both go, and the rules between them keep their places', () async {
    // Position is the whole mechanism: a jump is removed by its NUMBER, and every delete shifts the
    // numbers below it. Removing the lower one first would take the wrong rule.
    final _Backend legacy = _Backend()
      ..builtIn('filter', 'INPUT', <String>[
        '-m comment --comment "cali:Cz_u1IQiXIMmKD4c" -j cali-INPUT',
        '-j KUBE-FIREWALL',
        '-m comment --comment "cali:S93hcgKJrXEqnTfs" -m mark --mark 0x10000/0x10000 -j ACCEPT',
        '-p tcp --dport 22 -j ACCEPT',
      ])
      ..chain('filter', 'cali-INPUT', <String>['-j DROP']);
    final _Machine machine = _machine(legacy, pinnedTo: 'NFT');

    const RemoveCalicoRulesFromOtherBackend step = RemoveCalicoRulesFromOtherBackend(
      backend: 'nft',
    );
    expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());

    expect(
      legacy.rulesOf('filter', 'INPUT'),
      <String>['-j KUBE-FIREWALL', '-p tcp --dport 22 -j ACCEPT'],
      reason:
          'both agent rules go and both neighbours stay, which only holds if the deletes run from '
          'the highest position down',
    );
  });

  test('a chain the agent jumps to from its own chains is emptied before it is deleted', () async {
    // The agent's chains reference EACH OTHER. A delete before the flush answers "chain is not
    // empty" and the set survives, so the order inside a table is asserted by the outcome.
    final _Backend legacy = _Backend()
      ..builtIn('filter', 'FORWARD', <String>[
        '-m comment --comment "cali:wUHhoiAYhphO9Mso" -j cali-FORWARD',
      ])
      ..chain('filter', 'cali-FORWARD', <String>['-j cali-to-wl-dispatch'])
      ..chain('filter', 'cali-to-wl-dispatch', <String>['-j cali-tw-cali123', '-j DROP'])
      ..chain('filter', 'cali-tw-cali123', <String>['-j ACCEPT']);
    final _Machine machine = _machine(legacy, pinnedTo: 'NFT');

    const RemoveCalicoRulesFromOtherBackend step = RemoveCalicoRulesFromOtherBackend(
      backend: 'nft',
    );
    expect(await _drive(step, machine.contextFor(under)), isA<Satisfied>());
    expect(legacy.chainNames('filter'), isEmpty);
  });

  test('it says it cannot be taken back, in words about the change', () {
    const RemoveCalicoRulesFromOtherBackend step = RemoveCalicoRulesFromOtherBackend(
      backend: 'nft',
    );
    expect(step.irreversibleReason, contains('nothing on this machine holds a copy'));
  });
}

/// Runs the step the way the engine does: check, apply, check again.
Future<CheckResult> _drive(Step step, StepContext context) async {
  final CheckResult before = await step.check(context);
  if (before is! Ready) {
    return before;
  }
  await step.apply(context);
  return step.check(context);
}

/// A machine whose [backend] side is [ruleset] and whose agent is pinned to [pinnedTo].
///
/// The OTHER backend answers as one holding nothing, which is what a machine that never painted
/// there looks like.
_Machine _machine(_Backend ruleset, {required String pinnedTo, String backend = 'legacy'}) =>
    _Machine(ruleset, pinnedTo: pinnedTo, backend: backend);

/// A machine holding one packet-filtering backend and one agent setting.
final class _Machine implements Shell {
  _Machine(this.ruleset, {required this.pinnedTo, required this.backend});

  /// The backend that holds rules.
  final _Backend ruleset;

  /// What the agent's settings say it writes to.
  final String pinnedTo;

  /// Which of the two programs [ruleset] answers for.
  final String backend;

  /// Everything the log was told.
  final List<String> said = <String>[];

  /// The context a step is run in on this machine.
  StepContext contextFor(StepName step) => StepContext(
    shell: this,
    files: FakeFiles(),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: _CollectingLog(said),
    step: step,
    arguments: Arguments.none,
    answers: Arguments.none,
    facts: Facts.none,
  );

  @override
  Future<CommandResult> run(Command command) async {
    if (command.executable == 'kubectl') {
      return CommandResult(exitCode: 0, stdout: pinnedTo, stderr: '', elapsed: Duration.zero);
    }
    if (command.executable == 'iptables-$backend-save') {
      dumped.add(_waits(command.arguments));
      // THE DUMP PROGRAM HAS NO `-w`, AND REFUSES THE WHOLE CALL WHEN HANDED ONE. It is a different
      // program from the rule program beside it, with its own options. A fake that accepted the
      // flag would let a step which had stopped sweeping anything at all still go green here: it
      // reads an empty ruleset from a refused dump, concludes there is nothing to remove, and says
      // so. A fake that is kinder than the tool it stands for proves nothing.
      if (_waits(command.arguments)) {
        return const CommandResult(
          exitCode: 2,
          stdout: '',
          stderr: "iptables-save: unrecognized option -w",
          elapsed: Duration.zero,
        );
      }
      return CommandResult(
        exitCode: 0,
        stdout: ruleset.dump(command.arguments.last),
        stderr: '',
        elapsed: Duration.zero,
      );
    }
    if (command.executable == 'iptables-$backend') {
      ruled.add(_waits(command.arguments));
      return ruleset.apply(_withoutWait(command.arguments)) ??
          const CommandResult(exitCode: 0, stdout: '', stderr: '', elapsed: Duration.zero);
    }
    // The other backend's programs: a machine that never painted there answers with an empty dump.
    if (command.executable.startsWith('iptables-')) {
      dumped.add(_waits(command.arguments));
      return CommandResult(
        exitCode: 0,
        stdout: '*${command.arguments.last}\nCOMMIT\n',
        stderr: '',
        elapsed: Duration.zero,
      );
    }
    return const CommandResult(exitCode: 0, stdout: '', stderr: '', elapsed: Duration.zero);
  }

  /// Whether each RULE call asked to wait for the lock, in the order they were made. The rule
  /// program takes `-w`; every one of its calls should carry it.
  final List<bool> ruled = <bool>[];

  /// The same for each DUMP call — where the flag must never appear, because that program does not
  /// know it and refuses the whole call when handed one.
  final List<bool> dumped = <bool>[];

  /// Whether [argv] opens with the wait flag and a bound.
  static bool _waits(List<String> argv) =>
      argv.length >= 2 && argv[0] == '-w' && int.tryParse(argv[1]) != null;

  /// [argv] with the wait flag taken off, which is what the real program parses past.
  static List<String> _withoutWait(List<String> argv) => _waits(argv) ? argv.sublist(2) : argv;
}

/// A log that keeps what it was told.
final class _CollectingLog implements Logger {
  const _CollectingLog(this.said);

  final List<String> said;

  @override
  void debug(String message) => said.add(message);

  @override
  void info(String message) => said.add(message);

  @override
  void warn(String message) => said.add(message);

  @override
  void error(String message) => said.add(message);
}

/// One packet-filtering backend, in memory.
final class _Backend {
  final Map<String, Map<String, List<String>>> _tables = <String, Map<String, List<String>>>{};
  final Set<String> _builtIns = <String>{};

  /// Gives [chain] of [table] the rules [rules], as a chain the kernel owns.
  void builtIn(String table, String chain, List<String> rules) {
    _builtIns.add('$table/$chain');
    (_tables[table] ??= <String, List<String>>{})[chain] = <String>[...rules];
  }

  /// Gives [chain] of [table] the rules [rules], as a chain the agent owns.
  void chain(String table, String chain, List<String> rules) =>
      (_tables[table] ??= <String, List<String>>{})[chain] = <String>[...rules];

  /// The agent's chains in [table], in the order they were declared.
  List<String> chainNames(String table) => <String>[
    for (final String name in (_tables[table] ?? <String, List<String>>{}).keys)
      if (!_builtIns.contains('$table/$name')) name,
  ];

  /// What [chain] of [table] holds now.
  List<String> rulesOf(String table, String chain) => <String>[
    ...?(_tables[table] ?? <String, List<String>>{})[chain],
  ];

  /// What this backend's dump program answers for [table], rendered fresh on every reading.
  ///
  /// Fresh, because the step reads the dump more than once and a fixture answering the first
  /// reading for ever would hide a step that removed nothing.
  String dump(String table) {
    final Map<String, List<String>> chains = _tables[table] ?? <String, List<String>>{};
    final StringBuffer out = StringBuffer('*$table\n');
    for (final String name in chains.keys) {
      out.writeln(_builtIns.contains('$table/$name') ? ':$name ACCEPT [0:0]' : ':$name - [0:0]');
    }
    for (final MapEntry<String, List<String>> chain in chains.entries) {
      for (final String rule in chain.value) {
        out.writeln('-A ${chain.key} $rule');
      }
    }
    out.writeln('COMMIT');
    return out.toString();
  }

  /// What `iptables-<backend> -t <table> …` does to this ruleset.
  CommandResult? apply(List<String> argv) {
    if (argv.length < 4 || argv[0] != '-t') {
      return null;
    }
    final String table = argv[1];
    final String verb = argv[2];
    final String chain = argv[3];
    final Map<String, List<String>> chains = _tables[table] ??= <String, List<String>>{};
    switch (verb) {
      case '-D':
        final int at = int.parse(argv[4]);
        final List<String>? rules = chains[chain];
        if (rules == null || at < 1 || at > rules.length) {
          return _refused('index of deletion too big');
        }
        rules.removeAt(at - 1);
      case '-F':
        chains[chain]?.clear();
      case '-X':
        final List<String>? rules = chains[chain];
        if (rules == null) {
          return _refused('No chain/target/match by that name');
        }
        if (rules.isNotEmpty) {
          return _refused('Directory not empty');
        }
        // What the real program refuses: a chain something still jumps to.
        final bool referenced = chains.entries.any(
          (MapEntry<String, List<String>> other) =>
              other.key != chain && other.value.any((String rule) => rule.contains('-j $chain')),
        );
        if (referenced) {
          return _refused('Too many links');
        }
        chains.remove(chain);
      default:
        return null;
    }
    return const CommandResult(exitCode: 0, stdout: '', stderr: '', elapsed: Duration.zero);
  }

  static CommandResult _refused(String why) =>
      CommandResult(exitCode: 1, stdout: '', stderr: '$why\n', elapsed: Duration.zero);
}
