import 'package:ansiwise_core/ansiwise_core.dart';

/// How every helm invocation of this plugin is put together.
///
/// **helm is the tool, and this is its one caller.** Every step that drives helm composes its
/// command line here, out of the words helm is started with and the subcommand the step is about.
/// With one caller, how helm is reached is answered once instead of differently in different
/// files — and the two facts that answer it, the words and whether they need root, travel together
/// and cannot come apart at a call site.
///
/// **This package knows the TOOL and never how it was installed.** helm is one program on one
/// machine and two words on another: a cluster distribution that ships helm inside its own package
/// reaches it through that package's command, and a deployment may put `helm` on the machine only as
/// a SHELL ALIAS for a person at a prompt. A step that started `helm` therefore worked on the first
/// kind of machine and could never work on the second — and nothing said so, because a
/// non-interactive shell does not load aliases and a fake shell answers an argv without needing the
/// executable to exist at all.
///
/// That is how it was found, on a real machine: a program demanded `helm`, the program before it had
/// written the alias, and the gate passed while every release below it would have failed on a
/// command that is not a command.
///
/// So the row says it, and one answer given once in a program's `defaults:` block reaches every helm
/// row of that program.
final class Helm {
  /// helm started as [invocation], word by word, as root where [elevated].
  const Helm([this.invocation = _plain, this.elevated = false]);

  /// Builds the composer from what the program gave the step carrying it.
  factory Helm.fromArguments(Arguments arguments) => Helm(
    arguments.textList('helm_command'),
    arguments.has('helm_needs_root') && arguments.flag('helm_needs_root'),
  );

  /// helm as helm itself is started: one word, found on the path.
  static const List<String> _plain = <String>['helm'];

  /// The argument every step that drives helm declares.
  static const ArgumentSpec argument = ArgumentSpec(
    name: 'helm_command',
    kind: ArgumentKind.textList,
    required: false,
    defaultValue: _plain,
    describes:
        'how helm is started on this machine, as the program and any arguments before helm\'s own. '
        'One entry where helm is installed by itself; two or more where it ships inside another '
        'command and is reached through it. A shell alias is not enough: nothing here runs through a '
        'shell, and a non-interactive one would not load the alias anyway',
  );

  /// The second argument every step that drives helm declares.
  ///
  /// **Whether helm answers an ordinary account is a property of the INVOCATION**, which is why it
  /// stands beside the words rather than on each step. helm started as itself reads a cluster
  /// configuration the account owns and needs nothing; helm reached through a cluster distribution's
  /// own command is admitted by a GROUP that distribution keeps, and refuses every account outside
  /// it.
  ///
  /// **A supplementary group is read once, when a session starts.** An installation that puts the
  /// operating account into that group runs from a session started before it did so, so the account
  /// is in the group and the session is not — every helm invocation of that run meets the refusal
  /// while the machine is configured correctly, and a second run started later succeeds. Root is
  /// admitted without any group, so a row saying the distribution admits only root reaches helm in
  /// that same session.
  ///
  /// Running helm as root does not make a reading command change anything, so an observing call
  /// stays observing and a dry run still performs it.
  static const ArgumentSpec elevationArgument = ArgumentSpec(
    name: 'helm_needs_root',
    kind: ArgumentKind.flag,
    required: false,
    describes:
        'whether helm has to be started as root to answer at all. Leave it off where the command '
        'that starts helm admits the account the run started as',
  );

  /// The words helm is started with, in front of every subcommand.
  final List<String> invocation;

  /// Whether helm is started as root.
  final bool elevated;

  /// The whole command line for [arguments], for a plan and for a failure that has to name it.
  List<String> argv(List<String> arguments) => <String>[...invocation, ...arguments];

  /// The command that runs [arguments] through helm and may change what is installed.
  Command command(List<String> arguments, {Duration? timeout}) => Command.detailed(
    invocation.first,
    arguments: <String>[...invocation.skip(1), ...arguments],
    elevated: elevated,
    timeout: timeout,
  );

  /// The command that runs [arguments] through helm and only reads.
  Command observing(List<String> arguments) => Command.observing(
    invocation.first,
    arguments: <String>[...invocation.skip(1), ...arguments],
    elevated: elevated,
  );
}
