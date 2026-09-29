import 'package:ansiwise_core/ansiwise_core.dart';

/// Makes one host name resolve to one address on this machine, through its hosts file.
///
/// **What it is for.** A name whose public address this machine must not use: a service of this
/// same cluster that is reachable by its public name only from where it is admitted, while a
/// request from the machine itself reaches that address through its router and arrives from an
/// address that is not. Pointing the name at an address of the machine, or of the private network
/// the service is reached over, sends the request where it is admitted.
///
/// **The name stands in one line, and in the first one that names it.** A resolver takes the first
/// line naming a host, so a second mapping further down would decide nothing. Every other line
/// naming the host loses the name, and a line left with no name goes; then the line this row states
/// is appended. Lines naming other hosts, and comments, stay as they are.
///
/// **The undo writes the file back as it was read before the apply**, which is right for a file
/// nothing else writes while the run stands; a change somebody made to it in between would be
/// taken back with it.
final class SetHostAddress extends ReversibleStep<String?> {
  /// Makes [host] resolve to [address] in [hostsFile].
  const SetHostAddress({
    required this.host,
    required this.address,
    this.hostsFile = defaultHostsFile,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory SetHostAddress.fromArguments(Arguments arguments) => SetHostAddress(
    host: arguments.optionalText('host'),
    address: arguments.optionalText('address'),
    hostsFile: arguments.optionalText('hosts_file') ?? defaultHostsFile,
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// The hosts file every resolver of this operating system reads.
  static const String defaultHostsFile = '/etc/hosts';

  /// What this step accepts.
  ///
  /// The host and the address are declared optional because a row may take either from a
  /// measurement, which does not exist yet while the program is examined. A row without either is
  /// refused by the check.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'host',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the host name that is made to resolve to the address, written or taken from the row '
          'that measured it',
    ),
    ArgumentSpec(
      name: 'address',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the IPv4 or IPv6 address the name resolves to on this machine, written or taken from '
          'the row that measured it',
    ),
    ArgumentSpec(
      name: 'hosts_file',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: defaultHostsFile,
      describes: 'the hosts file that is written; the operating system reads /etc/hosts',
    ),
    elevationArgument,
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>[];

  /// The host name, or null where the row gave none.
  final String? host;

  /// The address it resolves to, or null where the row gave none.
  final String? address;

  /// The hosts file that is written.
  final String hostsFile;

  /// Whether the hosts file belongs to root, so every read and write of it is elevated.
  final bool elevated;

  /// Why this row cannot be carried out, or null where it can.
  String? get _refusal {
    final String? address = this.address;
    final String? host = this.host;
    if (address == null || host == null) {
      return 'this row names no ${address == null ? 'address' : 'host name'}, neither written nor '
          'measured, and a hosts file line needs both';
    }
    if (!_isAddress(address)) {
      return '"$address" is no IPv4 or IPv6 address, and a hosts file line needs one';
    }
    if (host.isEmpty || host.contains(RegExp(r'[\s#]'))) {
      return '"$host" is no host name a hosts file can carry';
    }
    return null;
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    if (_refusal case final String refusal) return CheckResult.blocked(refusal);
    final String current = await _read(context);
    if (current == _written(current)) {
      return CheckResult.satisfied('$host resolves to $address in $hostsFile');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    if (_refusal case final String refusal) return StepPlan.nothing(refusal);
    final String current = await _read(context);
    return StepPlan.diff(hostsFile, before: current, after: _written(current));
  }

  @override
  Future<void> apply(StepContext context) async {
    if (_refusal case final String refusal) throw StateError(refusal);
    final String current = await _read(context);
    final String next = _written(current);
    if (next != current) {
      await context.files.write(hostsFile, next, mode: _hostsFileMode, elevated: elevated);
    }
  }

  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(hostsFile, elevated: elevated) ? _read(context) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) return;
    if (await _read(context) == captured) return;
    await context.files.write(hostsFile, captured, mode: _hostsFileMode, elevated: elevated);
  }

  Future<String> _read(StepContext context) async =>
      await context.files.exists(hostsFile, elevated: elevated)
      ? context.files.read(hostsFile, elevated: elevated)
      : '';

  /// [current] with [host] resolving to [address] in the first line that names it: taken out of
  /// every other line, and appended where no line maps it so already.
  String _written(String current) {
    final String name = host!;
    final String address = this.address!;
    final List<String> lines = current.isEmpty ? <String>[] : current.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final int first = lines.indexWhere((String line) => _names(line).contains(name));
    if (first != -1 && _fields(lines[first]).first == address) {
      final bool elsewhere = lines
          .skip(first + 1)
          .any((String line) => _names(line).contains(name));
      if (!elsewhere) return current;
    }
    final List<String> kept = <String>[
      for (final String line in lines)
        if (!_names(line).contains(name))
          line
        else if (_names(line).length > 1)
          _without(line, name),
    ];
    return '${<String>[...kept, '$address $name'].join('\n')}\n';
  }

  /// The fields of a line before its comment: the address, then its names.
  static List<String> _fields(String line) {
    final int hash = line.indexOf('#');
    final String body = hash == -1 ? line : line.substring(0, hash);
    return body.trim().split(RegExp(r'\s+')).where((String f) => f.isNotEmpty).toList();
  }

  /// The host names a line maps, none for a comment or a blank line.
  static List<String> _names(String line) {
    final List<String> fields = _fields(line);
    return fields.length < 2 ? const <String>[] : fields.sublist(1);
  }

  /// [line] with [name] taken out of its names; its address, the other names and its comment stay.
  static String _without(String line, String name) {
    final List<String> fields = _fields(line);
    final int hash = line.indexOf('#');
    return <String>[
      fields.first,
      ...fields.sublist(1).where((String each) => each != name),
      if (hash != -1) line.substring(hash),
    ].join(' ');
  }

  /// Whether [text] is an IPv4 or an IPv6 address, as the language's own URI parser reads one.
  static bool _isAddress(String text) {
    for (final void Function(String) parse in <void Function(String)>[
      Uri.parseIPv4Address,
      Uri.parseIPv6Address,
    ]) {
      try {
        parse(text);
        return true;
      } on FormatException {
        continue;
      }
    }
    return false;
  }

  /// `0644`, the mode the operating system gives its hosts file.
  static const int _hostsFileMode = 0x1a4;
}
