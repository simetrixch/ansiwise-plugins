import 'package:ansiwise_api/ansiwise_api.dart';
import 'argument_text.dart';
import 'cluster_profile.dart';
import 'vault_api.dart';

/// Writes one named Vault policy.
///
/// A policy is the whole of what a caller may do, so the set of them is the security surface of the
/// platform: which namespace may read which path, and — for the one the cluster manager holds — what
/// it may write without being able to read it back.
///
/// **Every grant carries the whole path it applies to.** A reader of the program file sees
/// `secret/data/<stage>/consumer/+/app` and knows what that rule reaches; nothing is put in front of
/// it here. The stage is the marked slot [stagePlaceholder] and this run's own stage fills it, the
/// way every other name one installation owns is filled.
///
/// **A stage written out in full is refused rather than written.** The policy would be accepted by
/// Vault and would grant on a tree that is not this installation's, and the first sign of it is a
/// caller refused with a message about its own token. Only THIS run's stage can be recognised — the
/// step knows no other — and that is the half that is reachable by copying a rule out of a working
/// installation.
///
/// **A templated policy needs the mount's accessor, and the accessor cannot be written down.** It is
/// minted when the mount is enabled, so a policy that interpolates a caller's own namespace or the
/// tenant its account is annotated with names the accessor in its path. The program file writes
/// [accessorPlaceholder], this reads the real one from Vault and hands it to the filling. Getting
/// that wrong has no error: every templated path resolves empty and the caller is refused with a
/// message about its own token.
///
/// **The rules are compared, not assumed.** Writing a policy overwrites whatever was there, so a
/// step that simply wrote on every run would report having changed something every time and could
/// never say what the cluster is actually holding.
final class VaultPolicy extends ReversibleStep {
  /// Writes the policy [name] with [rules] into the Vault the profile in [repository] names.
  const VaultPolicy({
    required this.repository,
    required this.name,
    required this.rules,
    this.authMount,
  });

  /// Builds the step from what the program gave it.
  factory VaultPolicy.fromArguments(Arguments arguments) => VaultPolicy(
    repository: arguments.text('repository'),
    name: arguments.text('name'),
    rules: arguments.text('rules'),
    authMount: arguments.optionalText('auth_mount'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile "
          "and the credential file Vault's root token was written to",
    ),
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes:
          'the policy name, which is what a role binds to — "$clusterPlaceholder" in front of it '
          "for a policy that belongs to this cluster alone, which the profile's own short name "
          'fills in',
    ),
    ArgumentSpec(
      name: 'rules',
      kind: ArgumentKind.text,
      describes:
          "the grants, in Vault's own language, each written on the whole path it applies to — "
          '"$stagePlaceholder" where that path belongs to one stage\'s tree, and '
          '"$accessorPlaceholder" where it templates on the calling account\'s own login',
    ),
    ArgumentSpec(
      name: 'auth_mount',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the auth mount whose accessor this policy templates on, for a policy that names '
          '$accessorPlaceholder in its paths — "$kubernetesMountPlaceholder" for the mount this '
          "cluster's own workloads log in through",
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = vaultAnswers;

  /// The checkout this installation runs from.
  final String repository;

  /// The policy name.
  final String name;

  /// The policy text as the program file wrote it.
  final String rules;

  /// The auth mount whose accessor the rules template on, when they template on one.
  final String? authMount;

  @override
  Future<CheckResult> check(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final _Names named = _namesIn(context, vault);
    if (named.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = vault.url ?? '';

    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    if (token.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String held = token.value ?? '';

    final _Rules wanted = await _writtenRules(context, vault, named, url, held);
    if (wanted.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }

    final HttpAnswer answer = await context.http.send(
      vaultRead(url, 'sys/policies/acl/${named.name}', token: held),
    );
    if (isAbsent(answer)) {
      return const CheckResult.ready();
    }
    final Object? current = decodedData(answer.body)?['policy'];
    if (current is! String) {
      return const CheckResult.ready();
    }
    return _same(current, wanted.text)
        ? CheckResult.satisfied('the policy "${named.name}" is what this run writes')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    if (vault.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final _Names named = _namesIn(context, vault);
    if (named.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    if (token.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final _Rules wanted = await _writtenRules(
      context,
      vault,
      named,
      vault.url ?? '',
      token.value ?? '',
    );
    if (wanted.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'PUT',
      '${vault.url}/v1/sys/policies/acl/${named.name}',
      body: wanted.text,
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    final _Names named = _namesIn(context, vault);
    final String url = vault.url ?? '';
    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    final String held = token.value ?? '';
    final _Rules wanted = await _writtenRules(context, vault, named, url, held);

    final HttpAnswer answer = await context.http.send(
      vaultWrite(
        url,
        'sys/policies/acl/${named.name}',
        token: held,
        body: <String, Object?>{'policy': wanted.text},
        method: 'PUT',
      ),
    );
    if (!answer.ok) {
      throw RequestRefused(
        method: 'PUT',
        url: '$url/v1/sys/policies/acl/${named.name}',
        status: answer.status,
        body: answer.body,
      );
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    final _Names named = _namesIn(context, vault);
    if (named.refusal != null) {
      return;
    }
    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    if (token.value case final String held) {
      await context.http.send(
        vaultDelete(vault.url ?? '', 'sys/policies/acl/${named.name}', token: held),
      );
    }
  }

  /// What this policy is called here and which mount it templates on, or why neither can be known.
  _Names _namesIn(StepContext context, ClusterProfile profile) {
    final ArgumentText written = profile.forThisInstallation(context, name);
    if (written.refusal case final String refusal) {
      return _Names.unwritable(refusal);
    }
    if (authMount case final String mount) {
      final ArgumentText at = profile.forThisInstallation(context, mount);
      if (at.refusal case final String refusal) {
        return _Names.unwritable(refusal);
      }
      return _Names.written(name: written.value ?? '', authMount: at.value);
    }
    return _Names.written(name: written.value ?? '');
  }

  /// The policy text this run sends, or why it cannot be written.
  ///
  /// One method for the check, the plan and the write alike: a policy composed twice is a policy a
  /// dry run can show while the run sends something else.
  Future<_Rules> _writtenRules(
    StepContext context,
    ClusterProfile profile,
    _Names named,
    String url,
    String token,
  ) async {
    // Vault accepts a policy that permits nothing, and every caller bound to it is then refused for
    // a reason nothing points at.
    if (rules.trim().isEmpty) {
      return _Rules.unwritable(
        'the policy "$name" has no grants at all — a policy Vault accepts and that permits nothing '
        'refuses every caller bound to it, with a message about their own token',
      );
    }
    if (_stageWrittenOut(context) case final String refusal) {
      return _Rules.unwritable(refusal);
    }

    String? accessor;
    if (rules.contains(accessorPlaceholder)) {
      final String? mount = named.authMount;
      if (mount == null) {
        return _Rules.unwritable(
          'the policy "${named.name}" templates on an accessor and this step was given no '
          'auth_mount to read one from. Written with $accessorPlaceholder still in it, every '
          'templated path resolves to nothing and every caller is refused with a message about its '
          'own token',
        );
      }
      accessor = await _accessorOf(context, url, token, mount);
      if (accessor == null) {
        return _Rules.unwritable(
          'the policy "${named.name}" templates on the accessor of the auth mount $mount/, and '
          'Vault at $url reports no such mount. Written with an empty accessor every templated path '
          'in it would resolve to nothing and every caller would be refused with a message about '
          'its own token',
        );
      }
    }

    final ArgumentText written = profile.forThisInstallation(context, rules, accessor: accessor);
    if (written.refusal case final String refusal) {
      return _Rules.unwritable(refusal);
    }
    return _Rules.text(written.value ?? '');
  }

  /// Why a rule names this run's stage where the slot belongs, or null when none does.
  ///
  /// The path is quoted back with the slot in the stage's place, so the fix is on the screen rather
  /// than a second run away.
  String? _stageWrittenOut(StepContext context) {
    final String stage = context.answers.text(vaultStageAnswer);
    for (final String path in _pathsIn(rules)) {
      final List<String> segments = path.split('/');
      final int at = segments.indexOf(stage);
      if (at < 0) {
        continue;
      }
      segments[at] = stagePlaceholder;
      return 'the policy "$name" names the stage "$stage" in "$path", and a program file ships to '
          'every installation — write it as "${segments.join('/')}" and this run\'s own stage goes '
          'there';
    }
    return null;
  }

  /// The accessor Vault at [url] minted for the auth mount [mount], or null when it reports none.
  Future<String?> _accessorOf(StepContext context, String url, String token, String mount) async {
    final HttpAnswer answer = await context.http.send(vaultRead(url, 'sys/auth', token: token));
    final Map<String, Object?>? mounts = decodedData(answer.body) ?? decodedObject(answer.body);
    final Object? held = mounts?['$mount/'];
    final Object? accessor = held is Map<String, Object?> ? held['accessor'] : null;
    return accessor is String && accessor.isNotEmpty ? accessor : null;
  }

  /// Every path named in [text].
  static List<String> _pathsIn(String text) => <String>[
    for (final String line in text.split('\n'))
      if (_pathLine.firstMatch(line)?.group(1) case final String path) path,
  ];

  static final RegExp _pathLine = RegExp(r'^\s*path\s+"([^"]*)"');

  /// Whether two policy texts say the same thing.
  ///
  /// Vault gives a policy back the way it was sent, but a program file and a stored policy differ in
  /// how they were indented and how many blank lines they carry, and neither of those is part of
  /// what the policy grants.
  static bool _same(String a, String b) => _lines(a) == _lines(b);

  static String _lines(String text) => text
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .join('\n');
}

/// What a policy is called on this installation and which mount it templates on.
final class _Names {
  const _Names.written({required this.name, this.authMount}) : refusal = null;

  const _Names.unwritable(String this.refusal) : name = '', authMount = null;

  final String name;

  final String? authMount;

  final String? refusal;
}

/// The policy text a run would write, or why it cannot be written.
final class _Rules {
  const _Rules.text(this.text) : refusal = null;

  const _Rules.unwritable(this.refusal) : text = '';

  final String text;

  final String? refusal;
}
