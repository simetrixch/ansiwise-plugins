/// Steps that drive one Vault over its HTTP API: minting and feeding back its quorum, shaping the
/// mounts, policies, roles and entries a program describes, and materializing one held entry onto a
/// cluster.
///
/// This package knows the tool and never an application of it. Where the profile and the credential
/// file stand, under which keys the profile carries its values, and what is written into Vault —
/// all of that is a program row's to say, and none of it has a default here.
///
/// **One step knows a SECOND tool, and it is the only one.** Reading a held value and writing it
/// where it is needed cannot be split into two rows, because a step that measured something has no
/// way to tell a later step what it found. It stands here rather than in the cluster package so the
/// dependency runs from the specialized tool to the general one: a product driving a cluster and
/// keeping no Vault carries none of this.
library;

export 'src/registry.dart';
export 'src/steps/argument_text.dart';
export 'src/steps/kubernetes_secret_from_vault.dart';
export 'src/steps/vault_api.dart';
export 'src/steps/vault_auth_method.dart';
export 'src/steps/vault_auth_role.dart';
export 'src/steps/vault_init.dart';
export 'src/steps/vault_kv_entry.dart';
export 'src/steps/vault_kv_mount.dart';
export 'src/steps/vault_policy.dart';
export 'src/steps/vault_profile.dart';
export 'src/steps/vault_unsealed.dart';
export 'src/plugin.dart';
