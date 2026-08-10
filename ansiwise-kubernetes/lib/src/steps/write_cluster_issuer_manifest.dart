import 'package:ansiwise_api/ansiwise_api.dart';

/// Renders the cert-manager object every certificate on this cluster is issued by.
///
/// It names the certificate authority, the address that receives the notices before a certificate
/// expires, the secret the account's own key lives in, and how a request is answered — over an
/// ingress the cluster already serves, which is why nothing else has to be arranged for it.
///
/// **The manifest is a TEMPLATE beside the programs, not text composed here.** Every value one
/// installation decides stands in a marked slot: `<name>`, `<acme-server>`, `<email>` and
/// `<ingress-class>`. A slot nothing fills and a value with no slot are both refused, so the file
/// that lands on the machine and the values this run holds cannot silently disagree.
///
/// **Nothing here judges the address.** It is the mailbox of whoever operates the installation, and
/// a rule that recognised an illustration would refuse the operator whose own mailbox reads like
/// one.
///
/// **Where it is written is a row's to say, and cert-manager mandates no name for it.** A base name
/// in this package would agree with the file the steps that APPLY the issuer are given only by
/// accident, which is why one value is handed to all three under one name.
final class WriteClusterIssuerManifest extends ReversibleStep<String?> with FileStep, TemplateStep {
  /// Renders the issuer [name] into the file at [path], for the mailbox this run names.
  const WriteClusterIssuerManifest({
    required this.templatePath,
    required this.name,
    required this.acmeServer,
    required this.ingressClass,
    required this.path,
  });

  /// Builds the step from what the program gave it.
  factory WriteClusterIssuerManifest.fromArguments(Arguments arguments) =>
      WriteClusterIssuerManifest(
        templatePath: arguments.text('template'),
        name: arguments.text('name'),
        acmeServer: arguments.text('acme_server'),
        ingressClass: arguments.text('ingress_class'),
        path: arguments.text('issuer_manifest_path'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'template',
      kind: ArgumentKind.text,
      describes:
          'the manifest as text, with a marked slot where each value this run holds belongs — '
          '<name>, <acme-server>, <email> and <ingress-class>',
    ),
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes: 'what the issuer is called, which is also the secret its account key lives in',
    ),
    ArgumentSpec(
      name: 'acme_server',
      kind: ArgumentKind.text,
      describes: 'the certificate authority every certificate on this cluster is issued by',
    ),
    ArgumentSpec(
      name: 'ingress_class',
      kind: ArgumentKind.text,
      describes: 'the ingress a request for a certificate is answered over',
    ),
    // The whole path and not a directory with a base name added here. This step and the two that
    // apply the file are given one value under one name, so the name of the file is written once in
    // the program and the three cannot come to mean three different files. The directory it stands
    // in is created from the same value, so there is no second answer about where it goes.
    ArgumentSpec(
      name: 'issuer_manifest_path',
      kind: ArgumentKind.text,
      describes:
          'the file this renders the issuer into, which the steps that apply it are given too',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The mailbox the certificate authority writes to before a certificate expires. It belongs to
  /// whoever operates the installation, so it is asked for rather than shipped, and it is an ANSWER
  /// rather than an argument because a program file ships to every installation.
  static const List<String> answers = <String>[emailAnswer];

  /// The name the mailbox is answered under.
  static const String emailAnswer = 'letsencrypt_email';

  /// `0644` — a rendered manifest that carries nothing secret.
  static const int manifestMode = 0x1a4;

  /// `0755` — the directory it stands in.
  static const int directoryMode = 0x1ed;

  /// The manifest as text, with a marked slot where each value belongs.
  @override
  final String templatePath;

  /// What the issuer is called.
  final String name;

  /// The authority certificates are issued by.
  final String acmeServer;

  /// The ingress a request is answered over.
  final String ingressClass;

  /// Where the rendered manifest is written.
  final String path;

  /// The directory the manifest stands in, taken off the path rather than answered a second time.
  ///
  /// Null where the path names no directory at all — a bare file name is written where the run
  /// stands, and there is nothing to create for it.
  String? get directory {
    final int lastSeparator = path.lastIndexOf('/');
    return lastSeparator <= 0 ? null : path.substring(0, lastSeparator);
  }

  @override
  String pathFor(StepContext context) => path;

  @override
  int get mode => manifestMode;

  /// Every cluster this runs on issues its own certificates, so there is always a manifest to
  /// render.
  @override
  Future<FileContent> contentFor(StepContext context) async =>
      FileContent.text(await manifestFor(context));

  @override
  Future<void> apply(StepContext context) async {
    // The directory first. A run that reached here on a machine that has never had one would
    // otherwise fail on the write rather than on anything that says what is missing.
    if (directory case final String under) {
      await context.files.createDirectory(under, mode: directoryMode);
    }
    await super.apply(context);
  }

  /// What the file held before, or null when it was not there.
  ///
  /// A rendered file and not state: the object in the cluster is what issues certificates, and the
  /// step that applies it is what takes that away. What this puts back is the text a previous run
  /// rendered, so a machine that had one is left with it rather than with nothing.
  @override
  Future<String?> capture(StepContext context) => contentBefore(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      await context.files.delete(path);
      return;
    }
    await context.files.write(path, captured, mode: mode);
  }

  /// The manifest itself, rendered from the template this run names.
  ///
  /// Public because what the cluster is asked to hold and what this writes have to be one text: the
  /// steps that apply the issuer and that prove it settled compare against exactly this.
  Future<String> manifestFor(StepContext context) => renderedWith(context, <String, String>{
    'name': name,
    'acme-server': acmeServer,
    'email': context.answers.text(emailAnswer),
    'ingress-class': ingressClass,
  });
}
