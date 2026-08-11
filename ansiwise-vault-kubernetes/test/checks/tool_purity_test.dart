import 'package:ansiwise_checks/audits.dart';

/// tool-purity — this plugin knows its two tools and never an application of either.
///
/// It knows how Vault answers over its HTTP API and how kubectl is invoked, and it knows the one
/// fact that joins them: a value read out of the store can be written onto the cluster. What it may
/// never know is any one product's layout — which mount, which entry, which Secret, which namespace,
/// which keys, where the store's own facts stand — nor which component that product deploys to do
/// the same job continuously afterwards. Every one of those belongs to a program row or to the
/// product, never to this package.
///
/// So the scan reads every byte of [scanned] — code, comment and fixture alike — against the word
/// list at [wordList]. The test that decides a word stands at the head of that list: could a vendor
/// with the same tools and a completely different product still use this package with that word in
/// it?
///
/// tool/ is not scanned, and that is the harness rather than a loophole. This check has to name the
/// words it forbids in order to search for them, and nothing under tool/ is compiled into the plugin
/// or shipped with it. It is also why the list is a file there rather than a constant here: a list
/// written into a scanned file would be an occurrence of every word on it.
void main() => auditWordPurity(
  wordListPath: wordList,
  scannedPaths: scanned,
  theRule: 'this plugin names no application of either of its tools',
);

/// Where the words this plugin may not name live, relative to the package root.
const String wordList = 'tool/tool-purity.words';

/// The directories of this package that are read to the byte.
///
/// Named one at a time rather than as "the package minus its tools", so adding a directory to the
/// scan is a decision somebody makes here rather than a silent widening.
const List<String> scanned = <String>['lib', 'test'];
