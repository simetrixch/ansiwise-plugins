import 'package:ansiwise_core/ansiwise_core.dart';
import 'kubectl.dart';

/// Puts the rendered certificate issuer into the cluster.
///
/// Whether it can then actually issue anything is a different question, asked by the step after
/// this: the object is accepted long before the account behind it is registered.
///
/// **WHAT IS COMPARED IS THE ISSUER, NOT ITS NAME.** Reporting satisfied the moment an object of
/// this name stands in the cluster makes an installation unable to change its mind. The two things
/// the manifest decides — which authority the account is registered with, and the mailbox that
/// authority writes to — are ANSWERS, so a run given different ones renders a different manifest.
/// An installation whose answers have moved goes on being told there is nothing to do, and its
/// certificates keep coming from the authority it moved away from: they all still appear, so
/// nothing anywhere reports it.
///
/// The name is no evidence at all, and cannot be made into any. What an issuer is CALLED is a fact
/// about the installation, written by a program row and stable across every answer the operator
/// might change — so a name matching means only that this step has run here before.
///
/// It is the second sighting of one shape: a step that reads "something of this name is here" as
/// "the right thing is here" cannot converge, and what an operator is left with is hand surgery on
/// a live cluster — which is the one thing a declared program exists to make unnecessary.
///
/// The whole of what a run does to the issuer is undone through [ClusterIssuerBefore].
final class ApplyClusterIssuer extends ReversibleStep<ClusterIssuerBefore> {
  /// Applies the issuer [name] out of the file at [manifestPath].
  const ApplyClusterIssuer({
    required this.name,
    required this.manifestPath,
    this.kubectl = const Kubectl(),
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory ApplyClusterIssuer.fromArguments(Arguments arguments) => ApplyClusterIssuer(
    name: arguments.text('name'),
    manifestPath: arguments.text('issuer_manifest_path'),
    kubectl: Kubectl.fromArguments(arguments),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes:
          'the issuer every certificate on this cluster is issued by — what it is called is a '
          'fact about the installation',
    ),
    // The WHOLE path, and no base name composed here. cert-manager mandates none, so a base name
    // in this package would agree with whatever renders the file only by accident: rename it on
    // the rendering side and this step goes on looking for the old one, finds nothing, and reports
    // that the renderer has not run.
    ArgumentSpec(
      name: 'issuer_manifest_path',
      kind: ArgumentKind.text,
      describes:
          'the file the rendered issuer stands in, as the step that renders it writes it — one '
          'value, so the writer and this cannot come to name different files',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
    elevationArgument,
  ];

  /// The issuer certificates are issued by.
  final String name;

  /// The manifest this step applies.
  final String manifestPath;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(manifestPath, elevated: elevated)) {
      return CheckResult.blocked(
        '$manifestPath is not there, so the step that renders the issuer has not run',
      );
    }
    final ({String server, String email}) wanted = _issuerIn(
      await context.files.read(manifestPath, elevated: elevated),
    );
    final ({({String server, String email})? issuer, String? refusal}) reading = await _live(
      context,
    );
    if (reading.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ({String server, String email})? live = reading.issuer;
    if (live == null) {
      return const CheckResult.ready();
    }
    if (live == wanted) {
      return CheckResult.satisfied(
        '$name is in the cluster, registered with ${wanted.server} for ${wanted.email}',
      );
    }
    // SAID OUT LOUD, because "ready" on its own reads as "there is nothing here yet" and what is
    // actually about to happen is that a live registration is written over. The record is the only
    // place an operator can afterwards see WHICH authority the cluster was moved off.
    context.log.info(
      '$name is in the cluster but registered with ${live.server} for ${live.email}, where the '
      'rendered issuer says ${wanted.server} for ${wanted.email} — applying moves it',
    );
    return const CheckResult.ready();
  }

  /// The authority and the mailbox the issuer in the cluster carries, null where there is no such
  /// issuer, or why neither could be read.
  ///
  /// A cluster that could not be asked must not come back as the same null a cluster without the
  /// issuer does: [capture] reads that null as "this run created it" — which sends the undo to
  /// DELETE an issuer that was already there, and every certificate on the cluster is issued by it.
  /// See [Kubectl.readOne].
  Future<({({String server, String email})? issuer, String? refusal})> _live(
    StepContext context,
  ) async {
    final ({String? answer, String? refusal}) read = await kubectl.readOne(
      context,
      kind: 'clusterissuer',
      name: name,
      output: r'jsonpath={.spec.acme.server}{"\n"}{.spec.acme.email}',
    );
    if (read.refusal case final String refusal) {
      return (issuer: null, refusal: refusal);
    }
    final List<String> lines = (read.answer ?? '').trim().split('\n');
    if (lines.length != 2 || lines.first.isEmpty) {
      return (issuer: null, refusal: null);
    }
    return (issuer: (server: lines.first.trim(), email: lines.last.trim()), refusal: null);
  }

  /// The authority and the mailbox [manifest] names.
  ///
  /// READ AS LINES rather than as YAML, which is what the rest of this package does with a file it
  /// wrote itself: the two keys stand one per line under `acme:` because the template beside this
  /// puts them there, and a parser would be a dependency bought for two strings. A key the template
  /// stopped writing comes back empty, and an empty wanted value can never equal a live one — so
  /// the step asks to run rather than reporting a match it did not make.
  static ({String server, String email}) _issuerIn(String manifest) {
    String valueOf(String key) {
      for (final String line in manifest.split('\n')) {
        final String trimmed = line.trim();
        if (trimmed.startsWith('$key:')) {
          return trimmed.substring(key.length + 1).trim();
        }
      }
      return '';
    }

    return (server: valueOf('server'), email: valueOf('email'));
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(kubectl.argv(_apply));

  @override
  Future<void> apply(StepContext context) async {
    final Command apply = kubectl.command(_apply);
    final CommandResult applied = await context.shell.run(apply);
    if (!applied.ok) {
      throw CommandFailed(
        argv: apply.argv,
        exitCode: applied.exitCode,
        stdout: '',
        stderr: applied.stderr,
      );
    }
  }

  /// What the issuer in the cluster carried before this ran, or null where there was none.
  ///
  /// The two values and not a yes-or-no, because this step now ACTS on an issuer that is already
  /// there: it writes the rendered authority and mailbox over whatever stood in them. An undo that
  /// only knew whether the object existed would leave the new registration in place and call the
  /// cluster restored.
  @override
  Future<ClusterIssuerBefore> capture(StepContext context) async {
    final ({({String server, String email})? issuer, String? refusal}) reading = await _live(
      context,
    );
    if (reading.refusal case final String refusal) {
      context.log.warn(
        'what $name carried before this ran could not be read, so an undo will leave the issuer as '
        'it stands rather than delete one this run may not have created: $refusal',
      );
      return const ClusterIssuerBefore.unmeasured();
    }
    if (reading.issuer case final ({String server, String email}) registration) {
      return ClusterIssuerBefore.of(registration);
    }
    return const ClusterIssuerBefore.none();
  }

  /// Deletes an issuer that this step created, and puts back the two values it overwrote.
  ///
  /// An issuer that was there before this ran is one every certificate on the cluster is issued by,
  /// so it is never deleted while cleaning up after something else — what is undone is the change,
  /// which is the pair of values.
  @override
  Future<void> undo(StepContext context, ClusterIssuerBefore captured) async {
    if (captured.unmeasured) {
      return;
    }
    if (captured.registration == null) {
      await context.shell.run(kubectl.command(<String>['delete', 'clusterissuer', name]));
      return;
    }
    await context.shell.run(
      kubectl.command(<String>[
        'patch',
        'clusterissuer',
        name,
        '--type=merge',
        '-p',
        '{"spec":{"acme":{"server":"${captured.registration!.server}",'
            '"email":"${captured.registration!.email}"}}}',
      ]),
    );
  }

  List<String> get _apply => <String>['apply', '-f', manifestPath];
}

/// What the issuer in the cluster carried before a run applied over it, as far as it could be read.
///
/// **Three states, because the undo does three different things.** An issuer that was not there is
/// one this run created and the undo deletes it; an issuer that was there is one every certificate
/// on the cluster is issued by, so what the undo puts back is the pair of values this run wrote
/// over. The third is neither, and it is the one easiest to lose: a cluster that could not be
/// asked, read as the same null a cluster without the issuer gives, sends the undo to delete a live
/// issuer while cleaning up after some other step failed.
final class ClusterIssuerBefore {
  /// Records that the cluster held no such issuer, so this run created it.
  const ClusterIssuerBefore.none() : registration = null, unmeasured = false;

  /// Records the authority and the mailbox the issuer carried.
  const ClusterIssuerBefore.of(({String server, String email}) this.registration)
    : unmeasured = false;

  /// Records that neither could be read, so an undo has nothing it may act on.
  const ClusterIssuerBefore.unmeasured() : registration = null, unmeasured = true;

  /// What the issuer was registered with, or null where there was no issuer or no reading.
  final ({String server, String email})? registration;

  /// Whether the cluster could not be asked at all, which is not the same as holding no issuer.
  final bool unmeasured;
}
