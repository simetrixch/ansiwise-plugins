import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'yaml_file.dart';

/// Where the mirror a machine pulls its images through is written down, and what it is reached with.
///
/// Two steps need the same answer for different reasons. The gate refuses a machine whose credential
/// is fillable and unfilled, before anything is installed. The writer puts that credential into the
/// file the container runtime reads. The names are declared ONCE here and spread into both steps, so
/// the pair cannot disagree about where the address stands, which key carries the credential, or
/// which machine the mirror itself runs on.
///
/// **Nothing here composes an address.** The mirror's address is READ out of the profile that
/// generated the checkout, because whatever else points at that registry reads the same key. An
/// address composed here would agree with the deployed one by accident and disagree the day either
/// of them moves, and the disagreement surfaces as a pull that is refused.
///
/// **Every name is the caller's.** Where the profile stands, which key holds the address, which file
/// holds the credential and under which name, what an example file writes in its place, and which
/// registry is mirrored at all — a vendor with the same container runtime and a completely different
/// product wants every one of those different, so none of them has a value in this package.
///
/// **The credential comes from an ANSWER of the run or from a FILE of the machine, and the run
/// decides which.** A machine that an earlier program of the same installation gave its credentials
/// to holds them in the file, and that file is the value somebody may have rotated by hand. A
/// machine that carries no such file is given the credential as an answer instead, and reading a
/// file there would refuse a machine whose credential is in the run in front of it. So where the run
/// holds a value under the name [credentialAnswer], that value IS the credential and the file is not
/// read; where it does not, the file is.
final class RegistryMirror {
  /// The layout exactly as a program row describes it.
  const RegistryMirror({
    required this.repository,
    required this.profilePath,
    required this.mirrorHostKey,
    required this.secretsPath,
    required this.credentialKey,
    required this.placeholderPrefix,
    required this.mirroredRegistry,
    required this.thisMachineAnswer,
    required this.mirrorMachineAnswer,
    this.credentialAnswer,
    this.runAnswer,
  });

  /// Builds the layout from what the program gave the step carrying it.
  factory RegistryMirror.fromArguments(Arguments arguments) => RegistryMirror(
    repository: arguments.text('repository'),
    profilePath: arguments.text('profile_path'),
    mirrorHostKey: arguments.text('mirror_host_key'),
    secretsPath: arguments.text('secrets_path'),
    credentialKey: arguments.text('credential_key'),
    placeholderPrefix: arguments.text('placeholder_prefix'),
    mirroredRegistry: arguments.text('mirrored_registry'),
    thisMachineAnswer: arguments.text('this_machine_answer'),
    mirrorMachineAnswer: arguments.text('mirror_machine_answer'),
    credentialAnswer: arguments.optionalText('credential_answer'),
    runAnswer: arguments.optionalText('run_answer'),
  );

  /// The arguments both steps of the mirror family declare.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          'the checkout the profile and the credential file stand in, which is where a deployment '
          'writes what one installation knows about itself',
    ),
    ArgumentSpec(
      name: 'profile_path',
      kind: ArgumentKind.text,
      describes:
          'where the profile stands under the checkout — the file that carries the address of the '
          'registry pulls are mirrored through',
    ),
    ArgumentSpec(
      name: 'mirror_host_key',
      kind: ArgumentKind.text,
      describes:
          'the key of the profile the mirror\'s address is written under, written with a dot '
          'between each level. The address is read and never composed: whatever else points at '
          'that registry reads the same key',
    ),
    // WHERE THE CREDENTIAL COMES FROM, said twice, and the RUN decides which of them is read. Not
    // one-or-the-other per row: the same row runs on a machine that was given a credential file and
    // on one that was given the credential as an answer, and a row that had to choose in the
    // program file would be two rows of the same step kept in step by hand.
    ArgumentSpec(
      name: 'credential_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer carrying the encoded pull configuration, for a machine no file of '
          'this installation writes it to. Where this run holds a value under that name it IS the '
          'credential and secrets_path is not read; where it holds none, secrets_path is',
      required: false,
    ),
    ArgumentSpec(
      name: 'secrets_path',
      kind: ArgumentKind.text,
      describes:
          'where the file carrying the pull credential stands under the checkout. It may carry the '
          'run_answer slot, and this run\'s value for that answer fills the place',
    ),
    ArgumentSpec(
      name: 'credential_key',
      kind: ArgumentKind.text,
      describes:
          'the name that file writes the encoded pull configuration under, read as a value and '
          'never sourced — a file that is run rather than read puts everything in it into '
          'everything the run starts afterwards',
    ),
    ArgumentSpec(
      name: 'placeholder_prefix',
      kind: ArgumentKind.text,
      describes:
          'what an example credential file writes in place of the real value, so a credential that '
          'is still the example is refused rather than written into the mirror',
    ),
    ArgumentSpec(
      name: 'mirrored_registry',
      kind: ArgumentKind.text,
      describes:
          'the registry whose pulls go through the mirror, written the way the container runtime '
          'and the pull configuration both name it',
    ),
    // The two answer NAMES, never the names themselves. Which machine this is, and which machine
    // the mirror stands on, are two things one installation states about itself — so a program file
    // that ships to every installation carries the name of the question and never its answer.
    ArgumentSpec(
      name: 'this_machine_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the name THIS machine is known by among the others — '
          'write "fqdn" here and this machine is whatever this run answered for "fqdn"',
    ),
    ArgumentSpec(
      name: 'mirror_machine_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the machine the mirror itself runs on, left empty by an '
          'installation whose mirror runs on this very machine. A machine that IS the mirror pulls '
          'nothing through it',
    ),
    // The one axis a product may run the same layout along more than once, and the reason it is
    // named rather than known: a container runtime has no such axis. A product with three
    // environments wants one credential file per environment, one with three regions wants the same
    // per region, and a product with neither wants none at all.
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name — write '
          '"stage" here and every "<stage>" in secrets_path is filled with this run\'s stage. '
          'Leave it off where the product has no such axis',
      required: false,
    ),
  ];

  /// The checkout the profile and the credential file stand in.
  final String repository;

  /// Where the profile stands under the checkout.
  final String profilePath;

  /// The dotted key of the profile the mirror's address is written under.
  final String mirrorHostKey;

  /// The name of the answer carrying the credential, or null where the row names none.
  final String? credentialAnswer;

  /// Where the credential file stands under the checkout, with its slot still in it.
  final String secretsPath;

  /// The name the credential file writes the encoded pull configuration under.
  final String credentialKey;

  /// What an example credential file writes in place of the real value.
  final String placeholderPrefix;

  /// The registry whose pulls go through the mirror.
  final String mirroredRegistry;

  /// The name of the answer holding the name this machine is known by.
  final String thisMachineAnswer;

  /// The name of the answer holding the machine the mirror itself runs on.
  final String mirrorMachineAnswer;

  /// The name of the answer whose value fills the slot spelled with that same name, or null.
  final String? runAnswer;

  /// Where the profile stands, as a whole path.
  ///
  /// **THE SLOTS ARE FILLED FROM THE ANSWERS THE LAYOUT ALREADY NAMES**, which is what makes a
  /// profile named for one installation nameable in a program file shipped to every installation.
  /// A profile is named for the machine the run stands on, so the slot spelled like
  /// [thisMachineAnswer] is filled from that answer, and the one spelled like [runAnswer] from that.
  ///
  /// Measured on a real deployment: read without filling them, the path kept the slot —
  /// `clusters/active/<fqdn>.yaml` — no such file existed, and both steps of this family reported
  /// themselves satisfied and wrote no mirror at all. Every machine of that installation went on
  /// pulling from the public registry, and nothing said so.
  String profileIn(StepContext context) =>
      '$repository/${_runAnswerFilled(context, _filled(context, thisMachineAnswer, profilePath))}';

  /// Where the credential file stands on this machine, as a whole path.
  String secretsIn(StepContext context) => '$repository/${_runAnswerFilled(context, secretsPath)}';

  /// Why the two machine answers cannot be read, or null when both are there.
  ///
  /// A run that holds neither name cannot say whether this machine is the mirror or pulls through
  /// one, and a step guessing at that either writes a mirror onto the machine the mirror runs on or
  /// leaves every pull of every other machine on the rate-limited public path. Both steps ask this
  /// first and refuse rather than pick.
  String? answerRefusalIn(StepContext context) {
    for (final String name in <String>[thisMachineAnswer, mirrorMachineAnswer]) {
      if (!context.answers.has(name)) {
        return 'this run holds no answer called "$name", and that is where this row says the '
            'machine the mirror runs on is decided from';
      }
    }
    return null;
  }

  /// Whether this machine is the one the mirror itself runs on.
  ///
  /// A mirror does not mirror itself: on the machine it stands on there is nothing to pull through,
  /// and at this point in that machine's own install the mirror does not exist yet. An EMPTY answer
  /// means the mirror stands here, which is what a single-machine installation states.
  ///
  /// Ask [answerRefusalIn] first — a run holding neither answer is answered here as though this
  /// machine were the mirror, which is the safe reading and not a true one.
  bool hostsTheMirror(StepContext context) {
    final String here = context.answers.text(thisMachineAnswer);
    final String mirror = context.answers.text(mirrorMachineAnswer);
    return mirror.isEmpty || mirror == here;
  }

  /// The address of the mirror this machine pulls through, or null when it cannot be read.
  ///
  /// Read out of the profile and never composed from any name. The profile is where the value is
  /// written when the checkout is generated, and composing it here would produce a second answer
  /// that only agrees with the first by accident.
  Future<String?> mirrorHostIn(StepContext context, {bool elevated = false}) async {
    final String profile = profileIn(context);
    if (!await context.files.exists(profile, elevated: elevated)) {
      return null;
    }
    final YamlNode document;
    try {
      document = loadYamlNode(await context.files.read(profile, elevated: elevated));
    } on YamlException {
      return null;
    }
    if (yamlNodeAt(document, mirrorHostKey)?.value case final String host) {
      return host.trim().isEmpty ? null : host.trim();
    }
    return null;
  }

  /// What this row says the credential comes from on THIS run, named the way a refusal names it.
  ///
  /// The answer where the run holds one, and the file otherwise. Read by both steps for what they
  /// say when the credential is usable, so the sentence an operator gets names the thing they would
  /// have to change.
  String credentialSourceIn(StepContext context) => _answered(context) == null
      ? '$credentialKey of ${secretsIn(context)}'
      : 'the answer "$credentialAnswer"';

  /// The credential this machine reaches the mirror at [host] with, or a refusal saying why none.
  ///
  /// The file is read into values and never into this program's own environment. A file of
  /// credentials that is run rather than read puts every value in it into everything the run starts
  /// afterwards.
  ///
  /// **Nothing carrying a credential is a REFUSAL and not a pass.** A machine that pulls through a
  /// mirror it cannot present a credential to sends every pull to the rate-limited public path, no
  /// later run comes back to write the mirror on its own, and a step that passed here would report
  /// that machine as installed. The two names it could have come from are both in the refusal,
  /// because either one of them is what somebody fixes.
  ///
  /// The credential itself is returned and never written anywhere a record can reach.
  Future<PullCredential> credentialFor(
    StepContext context,
    String host, {
    bool elevated = false,
  }) async {
    if (_answered(context) case final String written) {
      return _judged(written, host, context);
    }
    final String secrets = secretsIn(context);
    if (!await context.files.exists(secrets, elevated: elevated)) {
      return PullCredential.refused(
        '${_neitherSource(context)}, and this machine pulls its images through the mirror at $host '
        '— which refuses an anonymous pull, so every pull would go to the rate-limited public path '
        'and nothing comes back later to write the mirror',
      );
    }
    final String text = await context.files.read(secrets, elevated: elevated);
    if (text.contains('\r\n')) {
      return PullCredential.refused(
        '$secrets is written with the line endings of another operating system, which leaves an '
        'invisible character inside every value in it — what that produces is a credential that is '
        'rejected and looks perfectly correct on screen. Rewrite it with plain line endings.',
      );
    }
    return _judged(_value(text, credentialKey), host, context);
  }

  /// The value this run holds under [credentialAnswer], or null where there is no such value.
  ///
  /// Null where the row names no answer and where the run holds none. A value that is THERE and
  /// empty is not null: it is a credential somebody stated as nothing, and it is judged and refused
  /// by name rather than quietly sending the read to the file instead.
  String? _answered(StepContext context) {
    final String? name = credentialAnswer;
    return name == null ? null : context.answers.optionalText(name);
  }

  /// Both places this row says a credential could have come from, for the refusal when neither did.
  String _neitherSource(StepContext context) => credentialAnswer == null
      ? '${secretsIn(context)} is not on this machine, and this row names no credential_answer for '
            'a credential to reach it in'
      : 'this run holds no value under the answer "$credentialAnswer", and '
            '${secretsIn(context)} is not on this machine either';

  /// Whether [written] is a credential for [host], and a refusal naming its source where it is not.
  ///
  /// The same three judgements whichever source the value came from: a credential given as an
  /// answer that is blank, still the placeholder, or not an encoded pull configuration is exactly as
  /// unusable as one read out of a file.
  PullCredential _judged(String? written, String host, StepContext context) {
    final String named = credentialSourceIn(context);
    if (written == null || written.isEmpty) {
      return PullCredential.refused(
        '$named is blank, and without it the mirror would answer every pull with a refusal and fall '
        'back to the rate-limited public path anyway',
      );
    }
    if (written.startsWith(placeholderPrefix)) {
      return PullCredential.refused(
        '$named is still the placeholder an example credential file ships in place of the real '
        'value, which is not a credential',
      );
    }
    final String? blob = _blobFor(written, host);
    if (blob == null) {
      return PullCredential.refused(
        '$named does not carry a credential for $host — it holds the encoded pull configuration, '
        'and the entry for that address is what the mirror is written with',
      );
    }
    return PullCredential.usable(blob);
  }

  /// [text] with this run's own value for [runAnswer] where the slot marks it.
  ///
  /// Text carrying no slot, a layout naming no answer, and a run that does not hold the answer all
  /// come back unchanged — the last of them so the slot is still visible in whatever names the path,
  /// rather than being replaced by an empty string nobody could see.
  String _runAnswerFilled(StepContext context, String text) {
    final String? answer = runAnswer;
    return answer == null ? text : _filled(context, answer, text);
  }

  /// [text] with this run's value for [answer] where the slot spelled `<answer>` marks it.
  ///
  /// Text carrying no slot and a run that does not hold the answer both come back unchanged — the
  /// second so the slot is still visible in whatever names the path, rather than being replaced by
  /// an empty string nobody could see.
  static String _filled(StepContext context, String answer, String text) {
    final String slot = '<$answer>';
    if (!text.contains(slot) || !context.answers.has(answer)) {
      return text;
    }
    return text.replaceAll(slot, context.answers.text(answer));
  }

  /// The value written for [key] in [text], or null when it is not there.
  static String? _value(String text, String key) {
    for (final String line in text.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.startsWith('#') || !trimmed.startsWith('$key=')) {
        continue;
      }
      String value = trimmed.substring(key.length + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    }
    return null;
  }

  /// The credential [written] holds for [host], or null when it holds none.
  ///
  /// The shape is the pull configuration's own, which every client that logs in to a registry
  /// writes and reads: base64 of a document whose `auths` maps an address to the credential used
  /// against it.
  static String? _blobFor(String written, String host) {
    final Object? configuration;
    try {
      configuration = jsonDecode(utf8.decode(base64.decode(written)));
    } on FormatException {
      return null;
    }
    if (configuration is! Map<String, Object?>) {
      return null;
    }
    final Object? auths = configuration['auths'];
    if (auths is! Map<String, Object?>) {
      return null;
    }
    final Object? entry = auths[host];
    if (entry is! Map<String, Object?>) {
      return null;
    }
    final Object? blob = entry['auth'];
    return blob is String && blob.isNotEmpty ? blob : null;
  }
}

/// What a file of credentials said about the pull credential.
final class PullCredential {
  /// A credential that can be used.
  const PullCredential.usable(String this.blob) : refusal = null;

  /// No usable credential, because [refusal].
  const PullCredential.refused(String this.refusal) : blob = null;

  /// The credential itself, or null when there is none.
  ///
  /// Never written to the log or to a plan. It reaches exactly one place: the file the mirror is
  /// configured in, which only its owner may read.
  final String? blob;

  /// Why there is none, or null when there is one.
  final String? refusal;
}
