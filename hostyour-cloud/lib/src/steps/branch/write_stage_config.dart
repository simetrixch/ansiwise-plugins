import 'package:ansiwise_api/ansiwise_api.dart';
import '../gitops/stage_config.dart';
import 'filled_template.dart';
import 'filled_template_step.dart';

/// Turns the answers this run was given into the config file the rest of the installation reads.
///
/// `configs/config.<stage>` is where every later program looks for what this installation is:
/// which stage it runs, which domain it answers on, where its alerts go, which catalog its tenants
/// deploy from, which mailbox its certificates are registered to. The trunk carries
/// `configs/config.example` — the same file with every value at a placeholder — and this fills
/// the keys it owns, leaving every other line of it exactly as it ships.
///
/// **Only the operator's own values are here, and each of them exactly once.** The template's other
/// half is the platform's defaults: the pod network, the addon list, the chart repositories, the
/// timeouts. Those belong to the product and not to an installation, so nothing asks anybody for
/// them and nothing here writes them.
///
/// **The three values the domain and the stage fully determine are written out, not derived later.**
/// `DEPLOY_ENV`, `DOMAIN_SUFFIX` and `CLUSTER_NAME` all fall out of two answers, and a later program
/// that derived them again would be a second place for the same fact to be wrong in.
///
/// **A key that already carries a value is never rewritten**, and a value still equal to the
/// template's own counts as no value at all. Both halves are in [FilledTemplate]; the second is what
/// keeps a file somebody copied and never filled from being read as an answered one.
final class WriteStageConfig extends FilledTemplateStep {
  /// Writes the config of the installation generated in [repository].
  const WriteStageConfig({required this.repository});

  /// Builds the step from what the program gave it.
  factory WriteStageConfig.fromArguments(Arguments arguments) =>
      WriteStageConfig(repository: arguments.text('repository'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout this installation is generated in',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>[
    'fqdn',
    'stage',
    'letsencrypt_email',
    'alert_recipients',
    'unit_apex',
    'platform_domain',
    'build_plane',
    'catalog_repo',
  ];

  /// The checkout the config is written in.
  final String repository;

  /// The file the trunk carries, with every value at a placeholder.
  ///
  /// Named from the same constant the READER excludes by, so the one name that has to mean the same
  /// thing on both sides cannot drift on one of them.
  @override
  String get templatePath => '$repository/configs/$stageConfigTemplate';

  /// `0644` — every later program on this machine reads this file, and it holds no credential.
  @override
  int get mode => 0x1a4;

  /// Where the config of [context]'s stage stands.
  @override
  String pathFor(StepContext context) =>
      '$repository/configs/config.${context.answers.text('stage')}';

  /// What this step writes, by the key the file declares it under.
  ///
  /// `ALERT_RECIPIENTS` is one line holding several mailboxes, because that is the shape the file
  /// has always had and what reads it splits on the comma.
  @override
  Map<String, String> valuesFrom(StepContext context) {
    final Arguments given = context.answers;
    return <String, String>{
      'DEPLOY_ENV': given.text('stage'),
      'DOMAIN_SUFFIX': given.text('fqdn'),
      'CLUSTER_NAME': given.text('fqdn'),
      'LETSENCRYPT_EMAIL': given.text('letsencrypt_email'),
      'ALERT_RECIPIENTS': given.textList('alert_recipients').join(','),
      'UNIT_APEX': given.text('unit_apex'),
      'PLATFORM_DOMAIN': given.text('platform_domain'),
      'BUILD_PLANE_FQDN': given.text('build_plane'),
      'CATALOG_REPO': given.text('catalog_repo'),
    };
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(templatePath)) {
      return CheckResult.blocked(
        '$templatePath is not on this branch, and it is what this file is made from — every key '
        'stands under the paragraph explaining it, and nothing here writes one the template does '
        'not declare',
      );
    }

    final Map<String, String> wanted = valuesFrom(context);
    final List<String> unwritable = unwritableIn(wanted);
    if (unwritable.isNotEmpty) {
      return CheckResult.blocked(
        'these answers hold a double quote or a line break, which this file cannot carry: '
        '${unwritable.join(', ')}',
      );
    }

    final FilledTemplate file = await read(context);
    final List<String> undeclared = file.missingKeys(wanted.keys);
    if (undeclared.isNotEmpty) {
      return CheckResult.blocked(
        '$templatePath declares no ${undeclared.join(', ')}, so filling it in place would put a '
        'bare assignment at the end of a file whose value is that every key stands under its own '
        'explanation',
      );
    }

    final List<String> filling = toFill(file, wanted);
    if (filling.isEmpty) {
      return CheckResult.satisfied(
        '${pathFor(context)} states what this installation is, and every value in it was answered',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    // Answered rather than thrown, on the one machine this step cannot act on at all. A plan is what
    // an operator reads to decide whether to let the run happen, and a plan that fails to be
    // produced tells them nothing about what would be done.
    if (!await context.files.exists(templatePath)) {
      return StepPlan.nothing(
        '$templatePath is not on this branch, so nothing can be filled from it',
      );
    }

    final FilledTemplate file = await read(context);
    final Map<String, String> wanted = valuesFrom(context);
    final List<String> filling = toFill(file, wanted);

    for (final String key in wanted.keys) {
      context.log.debug(
        filling.contains(key)
            ? '$key would be filled in'
            : '$key already carries an answer and would be left alone',
      );
    }
    return StepPlan.diff(
      pathFor(context),
      before: await context.files.exists(pathFor(context)) ? file.current : '',
      after: file.filled(<String, String>{
        for (final String key in filling) key: wanted[key] ?? '',
      }),
    );
  }
}
