import 'package:ansiwise_core/ansiwise_core.dart';

import 'tailnet_client.dart';

/// Joins this machine to the private network, with a credential minted at the coordinator.
///
/// **Already on a network is not the same as already on OURS.** The backend state alone would let
/// a machine that belongs to another coordinator pass as joined and never reach this one — so the
/// client's own login server decides, and only an equal one satisfies. A machine logged in
/// somewhere else is refused rather than moved: moving a machine between networks is not something
/// a run may do silently.
///
/// **The key is passed by PATH, never by value.** `file:` is the client's own way of reading a
/// credential off disk; a value in the arguments would sit in the process listing for every
/// account on the machine to read. The step stages the key into a file only root can read, hands
/// the client the path, and removes the file whatever happens — its whole life is one apply.
///
/// **DNS is declined unless the row says otherwise.** With DNS accepted the client rewrites the
/// machine's resolver configuration, and on a machine that runs its own name service that takes
/// that service's resolution with it — a failure that surfaces as everything else breaking.
final class TailnetJoin extends IrreversibleStep {
  /// Joins with the credential the run's answers carry.
  const TailnetJoin({
    required this.stagedKeyPath,
    required this.acceptDns,
    required this.waitSeconds,
  });

  /// Builds the step from what the program gave it.
  factory TailnetJoin.fromArguments(Arguments arguments) => TailnetJoin(
    stagedKeyPath: arguments.text('staged_key_path'),
    acceptDns: arguments.has('accept_dns') && arguments.flag('accept_dns'),
    waitSeconds: arguments.integer('wait_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'staged_key_path',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: '/tmp/ansiwise-tailnet-authkey',
      describes:
          'where the credential is staged for the client to read — a file only root can read, '
          'created for the join and removed whatever the join answers',
    ),
    ArgumentSpec(
      name: 'accept_dns',
      kind: ArgumentKind.flag,
      required: false,
      describes:
          'whether the client may take over this machine\'s name resolution. Leave it off on any '
          'machine that runs a name service of its own — accepted, the client rewrites the '
          'resolver configuration and takes that service\'s resolution with it',
    ),
    ArgumentSpec(
      name: 'wait_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 86400,
        because:
            'a bound of zero seconds gives up before it looks, and one longer than a day outlives the run it bounds',
      ),
      required: false,
      defaultValue: 180,
      describes:
          'how long the join may take before it is cut short — a join that reaches its '
          'coordinator settles in seconds, and what this bound cuts is the wait for a person a '
          'spent credential falls into',
    ),
  ];

  /// The name of the answer that holds where the coordinator serves.
  static const String loginServerAnswer = 'login_server';

  /// The name of the answer that holds the credential — declared secret by the program, which is
  /// what keeps its value out of every record and every log.
  static const String authKeyAnswer = 'auth_key';

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>[loginServerAnswer, authKeyAnswer];

  /// Where the credential is staged for the client to read.
  final String stagedKeyPath;

  /// Whether the client may take over this machine's name resolution.
  final bool acceptDns;

  /// How long the join may take.
  final int waitSeconds;

  /// The staged file's mode: readable by its owner alone (0600, written in the hexadecimal Dart
  /// can spell), because the file holds a credential that puts a machine of the holder's choosing
  /// on the network.
  static const int _keyFileMode = 0x180;

  @override
  String get irreversibleReason =>
      'the credential this join redeems is single-use — the coordinator marks it spent the moment '
      'the machine registers, so logging out again cannot hand it back';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? state = await tailnetState(context);
    if (state == null) {
      return const CheckResult.blocked(
        'the client\'s own state cannot be read, so whether this machine is on a network cannot '
        'be known — is the client installed and its daemon running?',
      );
    }
    if (state != tailnetRunning) {
      return const CheckResult.ready();
    }
    final String ours = tailnetCoordinatorSpelling(context.answers.text(loginServerAnswer));
    final String current = await tailnetLoginServer(context);
    if (current.isEmpty) {
      // On a network, and the client does not say which. Nothing local can settle it, and taking
      // the membership away on a guess is worse than keeping it: the coordinator's own node list
      // is where the doubt is resolved, and that reading lives on the machine that runs it.
      return const CheckResult.satisfied(
        'already on a network; the client does not report which coordinator, so this membership '
        'is left standing — the coordinator\'s node list is where to confirm it',
      );
    }
    if (current == ours) {
      return CheckResult.satisfied('already on the network at $ours');
    }
    return CheckResult.blocked(
      'this machine is on a DIFFERENT network: its client is logged in to $current, this run\'s '
      'coordinator is $ours. Moving a machine between networks is not something a run may do '
      'silently — log it out deliberately and run this again',
    );
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_argv(context));

  @override
  Future<void> apply(StepContext context) async {
    // Whitespace is stripped here rather than carried into the protocol: the credential travels
    // as an answer somebody or something composed, and a trailing newline is the most ordinary
    // thing in the world for it to have picked up on the way.
    final String key = context.answers.text(authKeyAnswer).trim();
    if (key.isEmpty) {
      throw StateError(
        'the "$authKeyAnswer" answer is empty — it must hold the join credential minted at the '
        'coordinator, and joining with nothing would wait for a person this run does not have',
      );
    }
    await context.files.write(stagedKeyPath, '$key\n', mode: _keyFileMode, elevated: true);
    try {
      final List<String> argv = _argv(context);
      final CommandResult joined = await context.shell.run(
        Command.detailed(
          argv.first,
          arguments: argv.sublist(1),
          elevated: true,
          timeout: Duration(seconds: waitSeconds),
        ),
      );
      if (joined.exitCode != 0) {
        throw CommandFailed(
          argv: argv,
          exitCode: joined.exitCode,
          stdout: joined.stdout,
          stderr: joined.stderr,
        );
      }
    } finally {
      await context.files.delete(stagedKeyPath, elevated: true);
    }
  }

  /// The join as the client is invoked, with the credential as a path and never a value.
  List<String> _argv(StepContext context) => <String>[
    tailnetTool,
    'up',
    '--login-server',
    tailnetCoordinatorSpelling(context.answers.text(loginServerAnswer)),
    '--auth-key',
    'file:$stagedKeyPath',
    '--accept-dns=$acceptDns',
  ];
}
