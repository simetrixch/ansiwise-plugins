/// Credential exchanges between Vault and Kubernetes.
///
/// Each complete exchange stays one step because credentials remain in process memory. The program
/// supplies namespaces, entry fields and application-specific producer scripts. Keeping these
/// exchanges here leaves each individual tool package free of a dependency on the other tool.
library;

export 'src/plugin.dart';
export 'src/registry.dart';
export 'src/steps/kubernetes_secret_from_vault.dart';
export 'src/steps/vault_kv_entry_from_command.dart';
