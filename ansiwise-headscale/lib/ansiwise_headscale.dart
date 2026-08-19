/// Steps that drive a headscale coordinator's admin surface.
///
/// This package knows the coordinator's own grammar — users, pre-auth keys, their single use and
/// their expiry — and never an application of it. How the surface is reached, which machine gets a
/// user, how long a key stays redeemable and where a minted credential is put for the caller are
/// arguments a program row fills, and not one of them has a product's value as a default here.
library;

export 'src/plugin.dart';
export 'src/registry.dart';
export 'src/steps/tailnet_join_credential.dart';
