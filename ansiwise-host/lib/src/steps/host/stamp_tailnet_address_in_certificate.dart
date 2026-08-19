import 'package:ansiwise_core/ansiwise_core.dart';

import 'tailnet_client.dart';

/// Puts this machine's private-network address into a serving certificate, and PROVES it is there.
///
/// **Why the address has to be in a certificate at all.** Everything that dials this machine on its
/// private-network address does so over verified TLS, and a serving certificate that does not NAME
/// the address is refused in the handshake — a failure that presents as an unreachable machine
/// rather than as a missing name. The distribution signs that certificate from a request template
/// it renders on its own schedule, so the address goes into the TEMPLATE, at the marker the
/// renderer reads, and the re-sign is what carries it into the certificate.
///
/// **A changed template re-signs even when the certificate already carries the address** — which it
/// often does, because the renderer also lists the addresses of whatever interfaces are up at the
/// moment it runs. The distribution's own watcher compares its fresh render against the request on
/// disk and, on a difference, tears the node down to re-sign it — so a template edit left
/// unaccounted for is a node-wide teardown queued a few seconds out, after this step has reported
/// success and everything has moved on. Re-signing here is what settles that comparison. The
/// interface scan is also why the renderer's own pickup is no substitute for the template line: one
/// render taken while the client is down signs the certificate WITHOUT the address, and a template
/// line does not depend on an interface being up.
///
/// **Any OTHER address out of the network's range is REMOVED from the template.** A machine that
/// rejoins is handed a fresh address, and a line left behind keeps this machine presenting a
/// certificate for an address it no longer holds — one the coordinator is free to hand to a
/// different machine, whose identity this one would then satisfy in a verified handshake.
///
/// **The certificate is the proof, never the re-sign's exit code.** The check that runs after the
/// apply reads the names out of the signed certificate itself; a re-sign that reported success over
/// a request that was never regenerated cannot survive it.
final class StampTailnetAddressInCertificate extends ReversibleStep<String?> {
  /// Stamps the address into [template] and re-signs [certificate].
  const StampTailnetAddressInCertificate({
    required this.template,
    required this.certificate,
    required this.marker,
    required this.addressRange,
    required this.resign,
    required this.settledBy,
    required this.waitSeconds,
    required this.elevated,
  });

  /// Builds the step from what the program gave it.
  factory StampTailnetAddressInCertificate.fromArguments(Arguments arguments) =>
      StampTailnetAddressInCertificate(
        template: arguments.text('template'),
        certificate: arguments.text('certificate'),
        marker: arguments.text('marker'),
        addressRange: arguments.text('address_range'),
        resign: arguments.textList('resign'),
        settledBy: arguments.has('settled_by')
            ? arguments.textList('settled_by')
            : const <String>[],
        waitSeconds: arguments.integer('wait_seconds'),
        elevated: arguments.has('elevated') && arguments.flag('elevated'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'template',
      kind: ArgumentKind.text,
      describes:
          'the certificate request template the distribution renders and re-renders — the one '
          'editable file whose names survive its refreshes',
    ),
    ArgumentSpec(
      name: 'certificate',
      kind: ArgumentKind.text,
      describes: 'the signed serving certificate the proof is read out of',
    ),
    ArgumentSpec(
      name: 'marker',
      kind: ArgumentKind.text,
      describes:
          'the line that ends the template\'s name section — the address line goes directly in '
          'front of it, because after it the file is read for other things and a name there is '
          'never seen',
    ),
    ArgumentSpec(
      name: 'address_range',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: '100.64.0.0/10',
      describes:
          'the range the network\'s addresses come from, so a stale one can be told apart from '
          'the machine\'s own interfaces — the default is the carrier-grade range the client '
          'family assigns from',
    ),
    ArgumentSpec(
      name: 'resign',
      kind: ArgumentKind.textList,
      describes:
          'the distribution\'s own command that re-renders the request from the template and '
          're-signs the serving certificate — and ONLY that certificate: a re-sign that replaces '
          'the authority breaks the very verification the name is being added for',
    ),
    ArgumentSpec(
      name: 'settled_by',
      kind: ArgumentKind.textList,
      required: false,
      describes:
          'the command that answers once the machine is serving again after the re-sign, run '
          'once and required to succeed — a re-sign restarts what serves, and reporting done '
          'while it is still coming back turns the caller\'s next act into a failure about the '
          'wrong thing. Leave it off where the re-sign itself waits',
    ),
    ArgumentSpec(
      name: 'wait_seconds',
      kind: ArgumentKind.integer,
      required: false,
      defaultValue: 600,
      describes: 'how long the re-sign, and the settling command after it, may each take',
    ),
    ArgumentSpec(
      name: 'elevated',
      kind: ArgumentKind.flag,
      required: false,
      describes:
          'whether the template and the certificate belong to root, so reading and writing them '
          'and running the re-sign need elevation. Leave it off for paths this account owns',
    ),
  ];

  /// The certificate request template the distribution renders.
  final String template;

  /// The signed serving certificate.
  final String certificate;

  /// The line the address goes in front of.
  final String marker;

  /// The range the network's addresses come from, as `a.b.c.d/prefix`.
  final String addressRange;

  /// The distribution's re-sign command.
  final List<String> resign;

  /// The command that answers once the machine serves again, or empty for a re-sign that waits.
  final List<String> settledBy;

  /// How long the re-sign and the settling command may each take.
  final int waitSeconds;

  /// Whether the paths belong to root.
  final bool elevated;

  /// The template's mode when this step writes it: the distribution ships it world-readable, and
  /// it holds no secret — only names.
  static const int _templateMode = 0x1a4;

  /// The address in the certificate is put there by the join that ran earlier in the same
  /// program, so a dry run on a machine that has not joined yet reports what this WOULD do rather
  /// than failing the machine for the join not having happened.
  @override
  bool get restsOnAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? address = await _held(context);
    if (address == null) {
      return const CheckResult.blocked(
        'this machine holds no address on the private network — the join is what hands one out, '
        'and without it there is nothing to put into the certificate',
      );
    }
    if (!await context.files.exists(template, elevated: elevated)) {
      return CheckResult.blocked(
        '$template is not on this machine — the distribution keeps its editable certificate '
        'request there, so either the distribution is missing or it changed its layout',
      );
    }
    final String content = await context.files.read(template, elevated: elevated);
    if (!_carriesMarker(content)) {
      return CheckResult.blocked(
        '$template carries no "$marker" line — that marker is where the name section ends, and '
        'without it there is no place to add a name the renderer will read',
      );
    }
    final bool templateRight = _stamped(content, address) == content;
    return templateRight && await _certificateNames(context, address)
        ? CheckResult.satisfied('$certificate names $address, and $template says to keep it so')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? address = await _held(context);
    if (address == null || !await context.files.exists(template, elevated: elevated)) {
      return StepPlan.argv(resign);
    }
    final String before = await context.files.read(template, elevated: elevated);
    final String after = _carriesMarker(before) ? _stamped(before, address) : before;
    // The certificate may already carry the address while the template does not say to keep it —
    // the renderer lists whatever interfaces were up — so the plan is the template change where
    // there is one, and the bare re-sign where the template already stands.
    return after == before
        ? StepPlan.argv(resign)
        : StepPlan.diff(template, before: before, after: after);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? address = await _held(context);
    if (address == null) {
      throw StateError(
        'this machine reports no address on the private network, so there is nothing to put '
        'into $certificate',
      );
    }
    final String before = await context.files.read(template, elevated: elevated);
    final String after = _stamped(before, address);
    if (after != before) {
      await context.files.write(template, after, mode: _templateMode, elevated: elevated);
    }
    // A CHANGED template re-signs even when the certificate already carries the address — see the
    // class comment: the edit has to be carried into the request on disk, or the distribution's
    // watcher tears the node down for it moments after this reports success.
    if (after != before || !await _certificateNames(context, address)) {
      await _mustRun(context, resign);
      if (settledBy.isNotEmpty) {
        await _mustRun(context, settledBy);
      }
    }
  }

  /// What [template] said before this ran, or null when it was not there — which the check refuses,
  /// so an apply never follows.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(template, elevated: elevated)
      ? context.files.read(template, elevated: elevated)
      : null;

  /// Puts the template back as it was and re-signs, so the certificate on disk agrees with the
  /// request again — leaving the two apart would hand the distribution's watcher a difference to
  /// tear the node down over.
  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      return;
    }
    final String current = await context.files.exists(template, elevated: elevated)
        ? await context.files.read(template, elevated: elevated)
        : '';
    if (current == captured) {
      return;
    }
    await context.files.write(template, captured, mode: _templateMode, elevated: elevated);
    await _mustRun(context, resign);
    if (settledBy.isNotEmpty) {
      await _mustRun(context, settledBy);
    }
  }

  /// The address this machine holds on the network, or null when it is not a member or cannot say.
  Future<String?> _held(StepContext context) async {
    if (await tailnetState(context) != tailnetRunning) {
      return null;
    }
    return tailnetAddress(context);
  }

  /// Whether [content] carries the marker as a line of its own.
  bool _carriesMarker(String content) =>
      content.split('\n').any((String line) => line.trim() == marker);

  /// [content] with [address] the one in-range name the template carries, in front of the marker.
  ///
  /// Stale in-range addresses go, the wanted one is added where it is missing, and everything else
  /// — including addresses outside the range, which are the machine's own interfaces — is left
  /// exactly as the distribution or its operator wrote it. The index is one past the highest the
  /// file already carries; a gap a removed line leaves is not reused, and the request format does
  /// not mind — the suffix only has to be unique within the section.
  String _stamped(String content, String address) {
    final RegExp nameLine = RegExp(r'^IP\.([0-9]+)\s*=\s*([0-9.]+)\s*$');
    final List<String> kept = <String>[];
    int highest = 0;
    bool present = false;
    for (final String line in content.split('\n')) {
      final RegExpMatch? match = nameLine.firstMatch(line);
      if (match != null) {
        final String held = match.group(2)!;
        highest = highest < int.parse(match.group(1)!) ? int.parse(match.group(1)!) : highest;
        if (held == address) {
          present = true;
        } else if (_inRange(held)) {
          // A stale address of the network: dropped, for the identity reason the class comment
          // gives. An index a dropped line held is not reused.
          continue;
        }
      }
      kept.add(line);
    }
    if (present) {
      return kept.join('\n');
    }
    final List<String> stamped = <String>[];
    for (final String line in kept) {
      if (line.trim() == marker) {
        stamped.add('IP.${highest + 1} = $address');
      }
      stamped.add(line);
    }
    return stamped.join('\n');
  }

  /// Whether [address] is one the network hands out — inside [addressRange].
  ///
  /// Compared as NUMBERS under the range's mask: a range like 100.64.0.0/10 spans 100.64.x.x
  /// through 100.127.x.x, which no leading-substring comparison gets right.
  bool _inRange(String address) {
    final int slash = addressRange.indexOf('/');
    final int? held = _asNumber(address);
    final int? base = _asNumber(slash < 0 ? addressRange : addressRange.substring(0, slash));
    final int? prefix = slash < 0 ? 32 : int.tryParse(addressRange.substring(slash + 1));
    if (held == null || base == null || prefix == null || prefix < 0 || prefix > 32) {
      return false;
    }
    final int mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
    return (held & mask) == (base & mask);
  }

  /// [address] as the 32-bit number it spells, or null when it spells none.
  int? _asNumber(String address) {
    final List<String> parts = address.split('.');
    if (parts.length != 4) {
      return null;
    }
    int number = 0;
    for (final String part in parts) {
      final int? octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        return null;
      }
      number = (number << 8) | octet;
    }
    return number;
  }

  /// Whether the signed certificate names [address], matched WHOLE — so 100.64.0.1 does not pass
  /// on a certificate that carries 100.64.0.11. A certificate that is not there, or that the
  /// reader refuses, names nothing — the reader's own exit code says so and nothing is asked twice.
  Future<bool> _certificateNames(StepContext context, String address) async {
    final CommandResult read = await context.shell.run(
      Command.observing(
        'openssl',
        arguments: <String>['x509', '-in', certificate, '-noout', '-text'],
        elevated: elevated,
      ),
    );
    if (read.exitCode != 0) {
      return false;
    }
    return RegExp('IP Address:${RegExp.escape(address)}(?![0-9])').hasMatch(read.stdout);
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(
        argv.first,
        arguments: argv.sublist(1),
        elevated: elevated,
        timeout: Duration(seconds: waitSeconds),
      ),
    );
    if (answer.exitCode != 0) {
      throw CommandFailed(
        argv: argv,
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }
}
