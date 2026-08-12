import 'package:ansiwise_api/ansiwise_api.dart';

/// How helm is reached on the machine in front of the run.
///
/// **This package knows the TOOL and never how it was installed.** Helm is one program on one
/// machine and two words on another: a cluster distribution that ships it inside its own package
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
/// So the row says it, with `helm` as the default because that is what a machine carrying the
/// program itself has. One name, given once in a program's `defaults:` block, reaches every helm row
/// of that program.
const ArgumentSpec helmCommandArgument = ArgumentSpec(
  name: 'helm_command',
  kind: ArgumentKind.textList,
  required: false,
  defaultValue: <String>['helm'],
  describes:
      'how helm is started on this machine, as the program and any arguments before helm\'s own. '
      'One entry where helm is installed by itself; two or more where it ships inside another '
      'command and is reached through it. A shell alias is not enough: nothing here runs through a '
      'shell, and a non-interactive one would not load the alias anyway',
);

/// Builds one helm invocation out of [helm] and the arguments of the call.
///
/// The two lists are joined here rather than at each call site, so a step writes what it wants helm
/// to do and never how helm is reached.
Command helmCommand(
  List<String> helm,
  List<String> arguments, {
  bool observes = false,
  Duration? timeout,
}) => Command.detailed(
  helm.first,
  arguments: <String>[...helm.skip(1), ...arguments],
  observes: observes,
  timeout: timeout,
);
