import 'package:ansiwise_core/ansiwise_core.dart';

/// How every kubectl command line of this plugin is put together.
///
/// **kubectl is the client, and this is its one caller.** Every step that reaches the cluster
/// composes its command line here, out of the words the client is invoked with and the subcommand
/// the step is about. What matters is not the choice of client but the shape: with one caller, how
/// the client is invoked is answered once, instead of differently in different files — which is how
/// a plugin ends up with steps running a plain `kubectl` beside steps running a wrapped one.
///
/// **The invocation is an argument, and the default is the tool's own answer.** A plain `kubectl`
/// on the path is the only invocation kubectl itself defines. A distribution that wraps the client
/// behind another command is one installation's arrangement, so its words stand in that
/// installation's program row — every word of the wrapping invocation, in order — and never in a
/// default here.
///
/// **What stays in the steps is everything after the invocation.** The subcommand, the object and
/// the flags ARE the step's own work, and moving them here would make this file a second copy of
/// every step. What no step may do is spell the invocation itself — a check turns the tree red when
/// one does.
final class Kubectl {
  /// The client invoked as [invocation], word by word, as root where [elevated].
  const Kubectl([this.invocation = _plain, this.elevated = false]);

  /// Builds the composer from what the program gave the step carrying it.
  ///
  /// An empty list is refused here, before anything runs: it would name no word to start at all,
  /// and every step is constructed before the first one runs, so the refusal reaches the operator
  /// as a broken program rather than as a step failing halfway through an installation.
  factory Kubectl.fromArguments(Arguments arguments) {
    final List<String> invocation = arguments.textList('kubectl');
    if (invocation.isEmpty) {
      throw ArgumentError.value(
        invocation,
        'kubectl',
        'names no word at all, so there is nothing to invoke the client with',
      );
    }
    return Kubectl(
      invocation,
      arguments.has('kubectl_needs_root') && arguments.flag('kubectl_needs_root'),
    );
  }

  /// The client as kubectl itself is invoked: one word, found on the path.
  static const List<String> _plain = <String>['kubectl'];

  /// The argument every step that reaches the cluster declares.
  static const ArgumentSpec argument = ArgumentSpec(
    name: 'kubectl',
    kind: ArgumentKind.textList,
    required: false,
    defaultValue: _plain,
    describes:
        'the words kubectl is invoked with, in front of every subcommand — the default is a plain '
        'kubectl on the path, and a cluster reached through a wrapped client names every word of '
        'the wrapping invocation instead',
  );

  /// The second argument every step that reaches the cluster declares.
  ///
  /// **Whether the client answers an ordinary account is a property of the INVOCATION**, which is
  /// why it stands beside it rather than on each step. A plain kubectl reads a kubeconfig its own
  /// account owns and needs nothing; a client wrapped by a distribution usually keeps its
  /// configuration where only root may read it, and refuses everyone else.
  ///
  /// **The refusal is what makes this necessary rather than convenient.** Such a client says
  /// "insufficient permissions" on its OUTPUT and exits ZERO. So a step reading the answer sees an
  /// answer, and the failure arrives as whatever that step concluded from it — measured on a
  /// machine as "the pods on this cluster could not be counted", three steps away from the reason.
  ///
  /// Running the client as root does not make a reading command change anything, so an observing
  /// call stays observing and a dry run still performs it.
  static const ArgumentSpec elevationArgument = ArgumentSpec(
    name: 'kubectl_needs_root',
    kind: ArgumentKind.flag,
    required: false,
    describes:
        'whether the client has to be invoked as root to reach the cluster at all. Leave it off '
        'for a client whose configuration this account owns',
  );

  /// The words the client is invoked with, in front of every subcommand.
  final List<String> invocation;

  /// Whether the client is invoked as root.
  final bool elevated;

  /// The whole command line for [arguments], for a plan and for a failure that has to name it.
  List<String> argv(List<String> arguments) => <String>[...invocation, ...arguments];

  /// The command that runs [arguments] against the cluster and may change it.
  Command command(List<String> arguments, {Duration? timeout}) => Command.detailed(
    invocation.first,
    arguments: <String>[...invocation.sublist(1), ...arguments],
    elevated: elevated,
    timeout: timeout,
  );

  /// The command that runs [arguments] against the cluster and only reads.
  Command observing(List<String> arguments) => Command.observing(
    invocation.first,
    arguments: <String>[...invocation.sublist(1), ...arguments],
    elevated: elevated,
  );

  /// What the cluster answers about the one object [kind]/[name], as [output] asks for it.
  ///
  /// Three states, and the client gives two of them the same exit code:
  ///
  /// | `answer` | `refusal` | what it means |
  /// |---|---|---|
  /// | the output | null | the object is there, and this is what it holds |
  /// | null | null | the cluster answered, and it holds no such object |
  /// | null | why | the cluster could not be asked, so neither of the above was measured |
  ///
  /// **A GET OF A NAMED OBJECT EXITS ONE FOR AN OBJECT THAT IS NOT THERE AND FOR A CLUSTER THAT
  /// NEVER ANSWERED**, and folded into the second the first is what several steps of this package
  /// reported: "there is no such thing, so there is nothing to delete", "there is nothing to patch",
  /// and a capture reading "this run created it" that sends an undo to delete an object somebody
  /// else's cluster was already running on. The rows this matters most for are the ones that run
  /// straight after a cluster comes up, which is precisely the moment an API server does not answer.
  ///
  /// **A LIST tells them apart, and it does it on the exit code alone.** `get <kind>` over a cluster
  /// holding none of them writes nothing and exits ZERO — absence is not an error for a list — while
  /// a cluster that cannot be reached, a client with no credentials, and a kind the cluster does not
  /// serve at all each exit non-zero. So the list is asked only where the get failed, and what it
  /// answers is the whole distinction. Nothing here reads a message: the words a client writes are
  /// its own to change, and a check built on them goes quietly green when they do.
  Future<({String? answer, String? refusal})> readOne(
    StepContext context, {
    required String kind,
    required String name,
    required String output,
    String? namespace,
  }) async {
    final List<String> within = <String>[
      if (namespace case final String each) ...<String>['-n', each],
    ];
    final CommandResult asked = await context.shell.run(
      observing(<String>[...within, 'get', kind, name, '-o', output]),
    );
    if (asked.ok) {
      return (answer: asked.stdout, refusal: null);
    }
    final CommandResult listed = await context.shell.run(
      observing(<String>[...within, 'get', kind, '-o', 'name']),
    );
    if (listed.ok) {
      return (answer: null, refusal: null);
    }
    return (
      answer: null,
      refusal:
          'the cluster would not say whether $kind "$name" is there, so nothing here knows whether '
          'it is: ${argv(<String>[...within, 'get', kind, name]).join(' ')} answered '
          '${asked.exitCode} and ${argv(<String>[...within, 'get', kind]).join(' ')} answered '
          '${listed.exitCode}'
          '${listed.stderr.trim().isEmpty ? '' : ' — ${listed.stderr.trim()}'}',
    );
  }
}
