import 'package:ansiwise_core/ansiwise_core.dart';

import 'argument_text.dart';
import 'dkim_key.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Mints the mail signing key pair into one entry of the store: the private half the signer reads
/// and, beside it, the public half a DKIM record carries.
///
/// **What no other row can write.** The entry the mail relay signs with carries a private key, and
/// neither of the two ways a row has of filling an entry can produce one. A hand-filled input is a
/// file of `KEY=value` lines, so it cannot hold a private key, which is many lines. And the
/// generator beside it makes a random value, which is a password rather than half of a key pair —
/// the other half has to match it, and nothing random matches anything. So the entry stood empty,
/// whatever a program declared about it, and the relay sent every mail unsigned.
///
/// **Both halves, in one act.** The private half is what the signer reads; the public half is what
/// the row that publishes the record reads, and it is written here out of the very private key that
/// was written, so the two cannot come apart. A record published for a key the signer does not hold
/// makes receivers fail mail that is otherwise fine.
///
/// **A KEY PAIR ALREADY IN THE STORE IS NEVER MINTED AGAIN, and this is the decision this step is
/// built around.** The public half of an existing pair stands in the DNS of every domain the relay
/// sends as, and nothing here knows which domains those are. Minting a second pair over the first
/// would leave every one of those records naming a key the signer no longer holds, and every
/// receiver would fail every signature until the records were published again. So a value that is
/// there is read, kept, and written back unchanged; only an entry that carries none is given one.
///
/// **What cannot be read is refused, never replaced.** An entry holding something under the private
/// key's name that does not parse as an unencrypted RSA key is left exactly as it is and the run is
/// blocked. It is either a value another writer owns or a damaged one, and both of those are cases
/// where writing is the one act that cannot be taken back.
///
/// **The pair is made by the machine's own openssl.** Making an RSA key is arithmetic this package
/// does not write and must not: a subtle error yields a pair whose halves do not match, nothing on
/// this side would notice, and what shows up weeks later is every receiver failing every signature.
/// The command answers with the private key, so its output is kept out of the record.
///
/// **The public half is published**, so the row that puts it into the DNS is given exactly what was
/// written here rather than reading the store a second time with a rule of its own. It is published
/// from the check, always out of what the store actually holds — on the run that mints it and on
/// every run afterwards, where it is read back out of the private half.
final class VaultKvDkimKeyPair extends IrreversibleStep {
  /// Writes the key pair to [path] on [mount] of this installation's Vault.
  const VaultKvDkimKeyPair({
    required this.repository,
    required this.mount,
    required this.path,
    required this.privateKeyField,
    required this.publicKeyField,
    required this.layout,
  });

  /// Builds the step from what the program gave it.
  factory VaultKvDkimKeyPair.fromArguments(Arguments arguments) => VaultKvDkimKeyPair(
    repository: arguments.text('repository'),
    mount: arguments.text('mount'),
    path: arguments.text('path'),
    privateKeyField: arguments.text('private_key_field'),
    publicKeyField: arguments.text('public_key_field'),
    layout: VaultLayout.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile and "
          "the credential file Vault's root token was written to",
    ),
    ArgumentSpec(
      name: 'mount',
      kind: ArgumentKind.text,
      describes: 'the key-value mount this entry is written on',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the entry, below the mount — it may carry the slot this row names under run_answer, '
          'where the entry belongs to one value of that axis rather than to all of them',
    ),
    ArgumentSpec(
      name: 'private_key_field',
      kind: ArgumentKind.text,
      describes:
          'the field of that entry the private half is written under. Whatever reads it expects '
          'that name, so it is stated here rather than chosen in this package',
    ),
    ArgumentSpec(
      name: 'public_key_field',
      kind: ArgumentKind.text,
      describes:
          'the field of that entry the public half is written under, as the one line of base64 a '
          "DKIM record's p= carries, for the same reason the field above is named here",
    ),
    ...VaultLayout.arguments,
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// None by name, as everywhere in this family: what varies with the run reaches this step through
  /// the slots the layout fills, and which answer fills them is a value of a program.
  static const List<String> answers = <String>[];

  /// What this step publishes.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('dkim_public_key'),
      describes:
          'the public half of the mail signing key pair the entry holds, as the one line of base64 '
          "a DKIM record's p= carries",
    ),
  ];

  /// What makes the pair, on the machine, and what it is told.
  static const List<String> mintingArgv = <String>[
    'openssl',
    'genpkey',
    '-algorithm',
    'RSA',
    '-pkeyopt',
    'rsa_keygen_bits:2048',
  ];

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile and the credential file stand under the checkout.
  final VaultLayout layout;

  /// The key-value mount.
  final String mount;

  /// The entry below it.
  final String path;

  /// The field of the entry the private half is written under.
  final String privateKeyField;

  /// The field of the entry the public half is written under.
  final String publicKeyField;

  @override
  String get irreversibleReason =>
      'the private half written here is the only copy there is: the signer reads it and the DNS '
      'of every domain the relay sends as carries the public one, so a later write that replaced it '
      'would leave every record published for it verifying nothing. A write becomes the current '
      'value and pushes the previous one into a history ten deep, and past that there is nothing to '
      'go back to';

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Entry entry = await _entry(context);
    if (entry.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }

    final HttpAnswer answer = await context.http.send(
      vaultRead(entry.url, entry.dataPath, token: entry.token),
    );
    // TOLD APART, because "I could not read it" is not an answer about what the entry holds. Read as
    // work to do, it sends the run into an apply that mints over a key pair the signer is using.
    final VaultReading reading = readingOf(answer, path: entry.dataPath);
    if (reading case final VaultUnreadable refused) {
      return CheckResult.blocked(refused.because);
    }
    if (reading is! VaultHeld) {
      return const CheckResult.ready();
    }
    final Object? held = reading.data['data'];
    final Map<String, Object?> standing = held is Map<String, Object?>
        ? held
        : const <String, Object?>{};

    final Object? privateKey = standing[privateKeyField];
    if (privateKey is! String || privateKey.isEmpty) {
      context.log.debug('${entry.dataPath} carries no $privateKeyField yet');
      return const CheckResult.ready();
    }
    final String? publicKey = dkimPublicKeyIn(privateKey);
    if (publicKey == null) {
      return CheckResult.blocked(_unreadable(entry.dataPath));
    }
    context.measurements.publish(const MeasurementName('dkim_public_key'), publicKey);

    if (standing[publicKeyField] != publicKey) {
      // The field, never the value: which of the two the entry names is what an operator would
      // look at, and the value beside it is what a record carries and a signer holds.
      context.log.debug(
        '${entry.dataPath} names a different $publicKeyField than the $privateKeyField yields',
      );
      return const CheckResult.ready();
    }
    return CheckResult.satisfied('${entry.dataPath} holds the mail signing key pair');
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final _Entry entry = await _entry(context);
    if (entry.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'POST',
      '${entry.url}/v1/${entry.dataPath}',
      body:
          'the fields $privateKeyField and $publicKeyField, the first minted here where the entry '
          'carries none and kept where it does, the second read out of the first',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Entry entry = await _entry(context);
    if (entry.refusal case final String refusal) {
      throw StateError(refusal);
    }

    final HttpAnswer answer = await context.http.send(
      vaultRead(entry.url, entry.dataPath, token: entry.token),
    );
    final VaultReading reading = readingOf(answer, path: entry.dataPath);
    if (reading case final VaultUnreadable refused) {
      throw StateError(refused.because);
    }
    final Object? held = reading is VaultHeld ? reading.data['data'] : null;
    final Map<String, Object?> standing = held is Map<String, Object?>
        ? held
        : const <String, Object?>{};

    final Object? already = standing[privateKeyField];
    final String privateKey;
    if (already is String && already.isNotEmpty) {
      if (dkimPublicKeyIn(already) == null) {
        throw StateError(_unreadable(entry.dataPath));
      }
      privateKey = already;
    } else {
      privateKey = await _minted(context);
    }
    // Read out of the private half that is being written, so the two halves are one pair by
    // construction and never by agreement.
    final String publicKey = dkimPublicKeyIn(privateKey)!;

    // A write to this store replaces the whole entry, so every field it already carries is written
    // back as it stands. Only the two this step owns are decided here.
    final Map<String, Object?> writing = <String, Object?>{
      ...standing,
      privateKeyField: privateKey,
      publicKeyField: publicKey,
    };
    final HttpAnswer written = await context.http.send(
      vaultWrite(
        entry.url,
        entry.dataPath,
        token: entry.token,
        body: <String, Object?>{'data': writing},
      ),
    );
    if (!written.ok) {
      throw RequestRefused(
        method: 'POST',
        url: '${entry.url}/v1/${entry.dataPath}',
        status: written.status,
        body: written.body,
      );
    }
  }

  /// A fresh private key, made by the machine's own openssl.
  ///
  /// The command answers with the key itself, so its output is declared secret and never reaches
  /// the record; a command that failed is reported by its exit code alone for the same reason. What
  /// comes back is held to the format this package reads before anything is written, because a
  /// tool that answered with something else would otherwise be written into the store as a key.
  Future<String> _minted(StepContext context) async {
    final CommandResult minted = await context.shell.run(
      Command.detailed(mintingArgv.first, arguments: mintingArgv.sublist(1), secretOutput: true),
    );
    if (!minted.ok) {
      throw CommandFailed.withheldOutput(argv: mintingArgv, exitCode: minted.exitCode);
    }
    final String privateKey = '${minted.stdout.trim()}\n';
    if (dkimPublicKeyIn(privateKey) == null) {
      throw StateError(
        '${mintingArgv.join(' ')} answered with something that is not an unencrypted RSA private '
        'key this can read, so nothing was written',
      );
    }
    return privateKey;
  }

  String _unreadable(String dataPath) =>
      '$privateKeyField of $dataPath is not an unencrypted RSA private key this can read, and a '
      'value that cannot be read is not a value that may be replaced — every record published for '
      'the key it stands for would verify nothing after the write. Look at that entry before this '
      'runs again';

  /// Where this entry stands and what may reach it, or why nothing can.
  Future<_Entry> _entry(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return _Entry.unreachable(refusal);
    }
    final ArgumentText at = vault.forThisInstallation(context, path);
    if (at.refusal case final String refusal) {
      return _Entry.unreachable(refusal);
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.refusal case final String refusal) {
      return _Entry.unreachable(refusal);
    }
    return _Entry.at(
      url: vault.url ?? '',
      dataPath: '$mount/data/${at.value ?? ''}',
      token: token.value ?? '',
    );
  }
}

/// Where one entry stands and what reaches it.
final class _Entry {
  const _Entry.at({required this.url, required this.dataPath, required this.token})
    : refusal = null;

  const _Entry.unreachable(this.refusal) : url = '', dataPath = '', token = '';

  /// Where Vault answers.
  final String url;

  /// The entry's data path under Vault's version one API.
  final String dataPath;

  /// The root token every call of this step is made with.
  final String token;

  /// Why none of the above can be had, or null when it can.
  final String? refusal;
}
