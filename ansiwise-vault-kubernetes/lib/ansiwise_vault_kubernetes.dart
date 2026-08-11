/// The step that reads a held value out of Vault and writes it onto a cluster.
///
/// **The subject of this package is the PAIR of tools, which is what its name says.** Reading a
/// value and writing it where it is needed cannot be split into two rows, because a step that
/// measured something has no way to tell a later step what it found — so it is one step, and it
/// knows two tools. Neither tool package is the place for it: a package that drives Vault would make
/// every vendor without a cluster resolve a cluster client, and a package that drives a cluster
/// would make every vendor without a secret store resolve one particular store. So the step stands
/// where its own subject is, and each tool package stays free of the other.
///
/// It knows the two tools and never an application of either. Which mount, which entry, which
/// Secret, which namespace, which keys, and where the store's own facts stand are all a program
/// row's to say, and none of them has a default here.
library;

export 'src/plugin.dart';
export 'src/registry.dart';
export 'src/steps/kubernetes_secret_from_vault.dart';
