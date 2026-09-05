import 'package:ansiwise_core/ansiwise_core.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Mints Vault's quorum once, and puts it in a file nothing else ever writes.
///
/// This is the only place in the whole deployment where the root token and the unseal keys exist. If
/// this step is skipped, or reports success without producing them, the cluster ends up with Vault
/// installed and no code path anywhere that would ever mint them — and every secret every workload
/// reads is behind them.
///
/// **The address comes from the profile and the credential file from the stage answer.** Neither is
/// a step argument: the address is one installation's and is read out of the profile where the
/// deployment wrote it, and the file name carries the stage the operator answered. A program file
/// that carried either would ship one installation's values to every installation. What a row may
/// say is only WHERE the profile and the file stand — the layout, which has no default because no
/// product's layout is this package's to assume.
///
/// **The credential file is never written over.** A placeholder written into an
/// existing credential file destroys the only copy of the quorum. So a file that is
/// already there ends this step, on every branch, and the one thing that is never done
/// to it is a write.
///
/// **An answer that cannot be read is not proof that Vault is uninitialized**, and this is the least
/// obvious way to lose a quorum: the reading transiently returns nothing on a Vault that is
/// initialized, and treating nothing as "not yet" lands the run on the branch that mints a second
/// quorum over the storage of the first. Here an unreadable answer blocks the step and says so.
///
/// **The token is not printed, and this is the one place the word "token" is right.** Vault's root
/// token is an actual API token. What the run says is the path, the mode and the escrow sentence;
/// the value goes into the file and nowhere else. A run that echoed the init answer for convenience
/// would put it into the scrollback of every terminal and the record of every run.
final class VaultInit extends IrreversibleStep {
  /// Initializes the Vault the profile in [repository] names.
  const VaultInit({
    required this.repository,
    required this.keyShares,
    required this.keyThreshold,
    required this.layout,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory VaultInit.fromArguments(Arguments arguments) => VaultInit(
    repository: arguments.text('repository'),
    keyShares: arguments.integer('key_shares'),
    keyThreshold: arguments.integer('key_threshold'),
    layout: VaultLayout.fromArguments(arguments),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile "
          'and the secrets directory the quorum is written into',
    ),
    ArgumentSpec(
      name: 'key_shares',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 255,
        because:
            'a Shamir share is indexed by a non-zero byte, so 255 is the most that can exist, and a split into fewer than one part is no split',
      ),
      defaultValue: 5,
      describes: 'how many unseal keys the quorum is split into',
    ),
    ArgumentSpec(
      name: 'key_threshold',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 255,
        because:
            'a Shamir share is indexed by a non-zero byte, so 255 is the most that can exist, and a threshold below one would need no key at all',
      ),
      defaultValue: 3,
      describes: 'how many of those keys have to be fed back to unseal',
    ),
    ...VaultLayout.arguments,
    elevationArgument,
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// None by name. What this step reads out of the run is whichever answer the row's `run_answer`
  /// names, and that is a value of a program rather than of this package — so there is no name here
  /// that a resolver could hold a program to, and an answer the run does not carry leaves the slot
  /// standing and is refused by name where the text is used.
  static const List<String> answers = <String>[];

  /// `0600` — the file holds the keys to everything, and whatever unseals on this host reads it as
  /// root.
  static const int credentialsMode = 0x180;

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile and the credential file stand under the checkout.
  final VaultLayout layout;

  /// How many shares the quorum is split into.
  final int keyShares;

  /// How many of them unseal.
  final int keyThreshold;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  String get irreversibleReason =>
      'the root token and the $keyShares unseal keys are minted once and cannot be minted again: '
      'there is no second initialization, and getting another set means destroying Vault\'s storage '
      'and every secret in it';

  @override
  Future<CheckResult> check(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = vault.url ?? '';
    final String credentialsPath = vaultCredentialsPath(context, repository, layout: layout);

    final String? held = await _credentialsRefusal(context, credentialsPath);
    if (held != null) {
      return CheckResult.blocked(held);
    }
    final bool haveCredentials = await context.files.exists(credentialsPath, elevated: elevated);

    final HttpAnswer answer = await context.http.send(vaultRead(url, 'sys/init'));
    final Object? initialized = decodedObject(answer.body)?['initialized'];
    if (initialized is! bool) {
      return CheckResult.blocked(
        'Vault at $url answered ${answer.status} and nothing that says whether it is initialized. '
        'That is not read as "not yet": an unreadable answer from an initialized Vault would put '
        'this run on the branch that mints a second quorum over the storage of the first',
      );
    }

    if (initialized) {
      return haveCredentials
          ? CheckResult.satisfied('Vault is initialized and its quorum is in $credentialsPath')
          : CheckResult.blocked(
              'Vault at $url is already initialized and $credentialsPath is not on this host, so '
              'the only copy of its quorum is wherever it was taken — restore that file from escrow '
              'before anything else runs, because nothing here can produce it again',
            );
    }

    return haveCredentials
        ? CheckResult.blocked(
            'Vault at $url reports itself uninitialized while $credentialsPath holds a quorum, and '
            'the two disagree. Initializing now would mint a second set of keys and leave the first '
            'able to unseal nothing — find out which of the two is the truth first',
          )
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'POST',
      '${vault.url}/v1/sys/init',
      body:
          'a quorum of $keyShares keys, $keyThreshold of which unseal, written to '
          '${vaultCredentialsPath(context, repository, layout: layout)}',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final String url = vault.url ?? '';
    final String credentialsPath = vaultCredentialsPath(context, repository, layout: layout);

    final HttpAnswer answer = await context.http.send(
      vaultWrite(
        url,
        'sys/init',
        // No token: this is the one Vault call that is made before a token exists.
        token: '',
        body: <String, Object?>{'secret_shares': keyShares, 'secret_threshold': keyThreshold},
      ),
    );
    if (!answer.ok) {
      // The body is deliberately left out of the failure. On the success path it carries the whole
      // quorum, and a failure path that happened to answer 200-with-a-body would put it in the
      // record through the exception.
      throw RequestRefused(
        method: 'POST',
        url: '$url/v1/sys/init',
        status: answer.status,
        body: '',
      );
    }

    final Map<String, Object?>? minted = decodedObject(answer.body);
    final Object? token = minted?['root_token'];
    final Object? keys = minted?['keys_base64'] ?? minted?['keys'];

    if (token is! String || keys is! List<Object?>) {
      // Vault answered and this could not read the answer, so the quorum exists and is only in that
      // body. It goes to disk verbatim rather than being dropped: a malformed credential file is a
      // problem an operator can solve, and a lost one is not. The check afterwards refuses it, so
      // the step still fails.
      await context.files.write(
        credentialsPath,
        answer.body,
        mode: credentialsMode,
        elevated: elevated,
      );
      context.log.error(
        'Vault answered the initialization in a shape this could not read. The answer was written '
        'verbatim to $credentialsPath (mode 600) so nothing is lost — it holds the quorum and has '
        'to be put into the "$unsealKeyLabel <n>:" and "$rootTokenLabel:" form by hand',
      );
      return;
    }

    await context.files.write(
      credentialsPath,
      renderCredentials(
        url: url,
        unsealKeys: <String>[
          for (final Object? key in keys)
            if (key is String) key,
        ],
        rootToken: token,
      ),
      mode: credentialsMode,
      elevated: elevated,
    );

    context.log.info('Vault is initialized — its quorum is in $credentialsPath, mode 600');
    context.log.warn(
      'COPY $credentialsPath OFF THIS HOST. Whatever unseals this Vault after a restart reads it '
      'from here, so it is also the only escrow left if this disk is lost',
    );
  }

  /// Why the credential file already at [credentialsPath] cannot be trusted, or null when it can.
  Future<String?> _credentialsRefusal(StepContext context, String credentialsPath) async {
    if (!await context.files.exists(credentialsPath, elevated: elevated)) {
      return null;
    }
    final String content = await context.files.read(credentialsPath, elevated: elevated);
    final String? crlf = carriageReturnRefusal(credentialsPath, content);
    if (crlf != null) {
      return crlf;
    }
    if (rootTokenIn(content) == null || unsealKeysIn(content).isEmpty) {
      return '$credentialsPath is on this host and carries no "$rootTokenLabel:" line and no '
          '"$unsealKeyLabel <n>:" line. This refuses rather than write over it: whatever is in that '
          'file may be the only copy of a quorum, in a shape nothing here reads';
    }
    return null;
  }
}
