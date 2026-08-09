import 'package:ansiwise_api/ansiwise_api.dart';

/// Puts the mail-DNS publisher's own configuration on the branch, and never overrules it afterwards.
///
/// An installation that sends mail has to publish DNS records for it: the A record of the apex it
/// sends from, the SPF record, the DKIM key and the DMARC policy. `tools/ops/mail-dns-publish.sh`
/// writes those into the zone, and it reads `configs/mail-dns.<stage>.conf` for the handful of
/// public facts it cannot derive — which zone the records live under, which apexes send, what the
/// DMARC policy is. This step is what puts that file on the branch, so that it is versioned with the
/// installation it belongs to and is never authored by hand into a running tree.
///
/// **The single row it writes means "behave exactly as if this file were not here".** `||auto|||||`
/// is the cluster's own domain with every field at its default, and it is the row the publisher
/// synthesises when it finds no file at all. So nothing about what would be published changes when
/// this step runs. What changes is that the file exists: an operator adding a second sender apex has
/// one place to add it to, and a row already standing there to write the second one after.
///
/// **It is create-only, and that is the whole of its postcondition.** A file that is already there
/// is left exactly as it is, whatever it holds. The two steps beside it, write_stage_config and
/// write_stage_secrets, fill VALUES into a template the trunk ships, and what they are finished
/// against is every key carrying an answer. This one writes a whole file the tree does not carry, so
/// what it is finished against is the file being there and the operator not having been overruled.
/// The rows for three further sender apexes are exactly what a rewrite would take away, and they are
/// not anywhere else.
///
/// **Publishing is not part of this and is not a step anywhere.** It changes a DNS zone, which is
/// not part of the machine an installation is deployed to; it is an operation an operator triggers
/// when the records are to change.
final class WriteStageMailDns extends ReversibleStep<bool> {
  /// Writes the mail-DNS configuration of the installation generated in [repository].
  const WriteStageMailDns({required this.repository});

  /// Builds the step from what the program gave it.
  factory WriteStageMailDns.fromArguments(Arguments arguments) =>
      WriteStageMailDns(repository: arguments.text('repository'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout this installation is generated in',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>['stage'];

  /// The checkout the configuration is written in.
  final String repository;

  /// `0644` — the file holds public DNS facts and no credential, and the publisher reads it as the
  /// operator who triggers it rather than as the account that generated the branch.
  static const int mode = 0x1a4;

  /// Where the mail-DNS configuration of [context]'s stage stands.
  ///
  /// Beside `config.<stage>`, and named for the stage the same way, because it is read by the same
  /// operator for the same one installation.
  String pathFor(StepContext context) =>
      '$repository/configs/mail-dns.${context.answers.text('stage')}.conf';

  /// What the file holds when this step creates it.
  ///
  /// The paragraph above the row is not decoration: an operator meeting this file is meeting the row
  /// format for the first time, and what they need is where the format is written down and what the
  /// row already there means.
  static const String _content =
      '# The sender domains of this installation, read by tools/ops/mail-dns-publish.sh.\n'
      '#\n'
      "# The one row below is the cluster's own domain with every field at its default, which is\n"
      '# exactly what the publisher uses when this file does not exist. What gets published is\n'
      '# therefore unchanged until a row is added here.\n'
      '#\n'
      '# Add one row per EXTRA sender apex. The row format and the meaning of every field in it are\n'
      '# documented in tools/ops/mail-dns.conf.example.\n'
      'MAIL_DNS_DOMAINS=(\n'
      '"||auto|||||"\n'
      ')\n';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String path = pathFor(context);
    // What the file HOLDS is deliberately not looked at. Comparing it against what this step writes
    // is the rewrite this step exists to not perform: an operator's extra sender apexes read as a
    // difference to be corrected, and correcting it removes them.
    if (await context.files.exists(path)) {
      return CheckResult.satisfied(
        '$path is on this branch, and what stands in it is the operator\'s to decide',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.diff(pathFor(context), before: '', after: _content);

  @override
  Future<void> apply(StepContext context) async {
    final String path = pathFor(context);
    // Create-only HERE and not only in the check. The engine applies a step only after its check
    // answered ready, so this can never run over a file that is already there — but what it writes
    // is fixed content rather than the file re-derived, so a call out of order would take an
    // operator's extra sender apexes with it. The step beside this one cannot do that damage
    // whatever order it is called in, because it fills the file it read; this one has to say so.
    if (await context.files.exists(path)) {
      return;
    }
    await context.files.write(path, _content, mode: mode);
  }

  /// Whether the branch already carried this file before the run.
  ///
  /// It is the whole of what a create-only step's undo needs: a file that was already there is the
  /// operator's, whatever it holds, and this step wrote nothing over it. Reading the content
  /// afterwards cannot answer that — a file an earlier run created holds exactly what this step
  /// writes, and taking a run back is not a licence to delete a file it did not create.
  @override
  Future<bool> capture(StepContext context) => context.files.exists(pathFor(context));

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.files.delete(pathFor(context));
  }
}
