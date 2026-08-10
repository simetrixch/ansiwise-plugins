import 'package:ansiwise_api/ansiwise_api.dart';
import 'configure_slave_apiserver_oidc_trust.dart';

/// Renders the object every certificate on this cluster is issued by.
///
/// It names the certificate authority, the address that receives the notices before a certificate
/// expires, the secret the account's own key lives in, and how a request is answered — over the
/// ingress this cluster already serves, which is why nothing else has to be arranged for it.
///
/// **Nothing here judges the address.** It used to warn when the mailbox ended in the domain the
/// illustrations use, because the address stood in the program file and was somebody's example.
/// It is answered now, so there is no example left to catch — and a rule that recognised an
/// illustration would refuse the operator whose own mailbox happens to read like one.
final class WriteClusterIssuerManifest extends ReversibleStep<String?> with FileStep {
  /// Renders the issuer [name] into [stateDirectory], for the mailbox this run names.
  const WriteClusterIssuerManifest({
    required this.name,
    required this.acmeServer,
    required this.ingressClass,
    required this.stateDirectory,
  });

  /// Builds the step from what the program gave it.
  factory WriteClusterIssuerManifest.fromArguments(Arguments arguments) =>
      WriteClusterIssuerManifest(
        name: arguments.text('name'),
        acmeServer: arguments.text('acme_server'),
        ingressClass: arguments.text('ingress_class'),
        stateDirectory: arguments.text('state_directory'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes: 'what the issuer is called, which is also the secret its account key lives in',
      required: false,
      defaultValue: 'letsencrypt-prod',
    ),
    ArgumentSpec(
      name: 'acme_server',
      kind: ArgumentKind.text,
      describes: 'the certificate authority every certificate on this cluster is issued by',
      required: false,
      defaultValue: 'https://acme-v02.api.letsencrypt.org/directory',
    ),
    ArgumentSpec(
      name: 'ingress_class',
      kind: ArgumentKind.text,
      describes: 'the ingress a request for a certificate is answered over',
      required: false,
      defaultValue: 'public',
    ),
    ArgumentSpec(
      name: 'state_directory',
      kind: ArgumentKind.text,
      describes: 'where this program keeps the manifests it renders',
      required: false,
      defaultValue: ConfigureSlaveApiserverOidcTrust.defaultStateDirectory,
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The mailbox the certificate authority writes to before a certificate expires. It belongs to
  /// whoever operates this installation, so it is asked for rather than shipped.
  static const List<String> answers = <String>[emailAnswer];

  /// The name the mailbox is answered under, which is what deploy-branch already calls it.
  static const String emailAnswer = 'letsencrypt_email';

  /// What the issuer is called.
  final String name;

  /// The authority certificates are issued by.
  final String acmeServer;

  /// The ingress a request is answered over.
  final String ingressClass;

  /// Where the rendered manifest goes.
  final String stateDirectory;

  /// Where the rendered manifest is written.
  String get path => '$stateDirectory/clusterissuer.yaml';

  @override
  String pathFor(StepContext context) => path;

  /// `0644` — a rendered manifest that carries nothing secret.
  @override
  int get mode => ConfigureSlaveApiserverOidcTrust.manifestMode;

  /// Every cluster this program runs on issues its own certificates, so there is always a manifest
  /// to render.
  @override
  Future<FileContent> contentFor(StepContext context) async =>
      FileContent.text(manifestFor(context));

  @override
  Future<void> apply(StepContext context) async {
    // The directory first. It is the state directory of this installation, and a run that reached
    // here on a machine that has never had one would otherwise fail on the write rather than on
    // anything that says what is missing.
    await context.files.createDirectory(stateDirectory, mode: 0x1ed);
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

  /// The manifest itself.
  String manifestFor(StepContext context) =>
      '# Every certificate on this cluster is issued by this. The account key lives in the secret\n'
      '# named below, and it decides whether a rebuilt issuer registers again or carries on with\n'
      '# the registration it already has.\n'
      'apiVersion: cert-manager.io/v1\n'
      'kind: ClusterIssuer\n'
      'metadata:\n'
      '  name: $name\n'
      'spec:\n'
      '  acme:\n'
      '    server: $acmeServer\n'
      '    email: ${context.answers.text(emailAnswer)}\n'
      '    privateKeySecretRef:\n'
      '      name: $name\n'
      '    solvers:\n'
      '      - http01:\n'
      '          ingress:\n'
      '            ingressClassName: $ingressClass\n';
}
