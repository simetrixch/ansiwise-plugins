import 'package:ansiwise_api/ansiwise_api.dart';

/// Asking whether a command is on the path, in the one way that works on a machine.
///
/// **`command` IS NOT AN EXECUTABLE.** It is a POSIX shell builtin, and on Linux there is no
/// `/usr/bin/command` to start. Three steps used to ask by running it directly, and every one of them
/// failed on every machine with `ProcessException: No such file or directory` — including the first
/// step of the first program, which carries `on_failure: exit`, so nothing behind it ever ran.
///
/// It went unseen for as long as it did because a fake shell answers an argv without executing it: a
/// suite can be wholly green over a command that cannot exist. The lesson is not about this builtin.
/// It is that a step naming an executable has made a claim about a machine, and only a machine can
/// answer it.
///
/// **Why the builtin rather than `which`.** `command -v` is in POSIX and is therefore in every shell
/// the product supports; `which` is a separate program that a minimal image is free not to carry, and
/// asking for it would put a second thing on the path to check the first.
///
/// **The name is passed as an ARGUMENT and never written into the script.** `sh -c '…' sh <name>`
/// puts it in `$1`, so a name carrying a space, a quote or a semicolon is one word to the shell.
/// Composed into the script text it would be shell input, and the name comes off a program row.
Command onThePath(String name) => Command.observing(
  'sh',
  arguments: <String>[
    '-c',
    // $1 and not the name: see above. `sh` fills argv[0], which -c wants and never runs.
    'command -v "\$1"',
    'sh',
    name,
  ],
);

/// [onThePath] as a fake shell keys it: the command joined by spaces.
///
/// Exported so a test answers the question the STEP asks rather than a string somebody typed. The
/// two drifting apart is how the builtin above went unnoticed — a fixture keyed on the old call
/// answered it happily, and a suite keyed on the code cannot.
String onThePathKey(String name) {
  final Command asked = onThePath(name);
  return <String>[asked.executable, ...asked.arguments].join(' ');
}

/// Whether [answer] to [onThePath] says the command is there.
///
/// `command -v` answers with the path and exit 0 when it finds one, and with nothing and a non-zero
/// exit when it does not. Both halves are read: a shell that exits 0 while printing nothing has not
/// found anything.
bool foundOnThePath(CommandResult answer) => answer.ok && answer.trimmed.isNotEmpty;
