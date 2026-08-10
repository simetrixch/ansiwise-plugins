/// Steps that drive one Vault over its HTTP API: minting and feeding back its quorum, and shaping
/// the mounts, policies, roles and entries a program describes.
///
/// This package knows the tool and never an application of it. Where the profile and the credential
/// file stand, under which keys the profile carries its values, and what is written into Vault —
/// all of that is a program row's to say, and none of it has a default here.
library;

export 'src/registry.dart';
export 'src/steps/argument_text.dart';
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
