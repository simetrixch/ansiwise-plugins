import 'package:ansiwise_checks/audits.dart';

/// tool-purity — this plugin knows the DNS API as a tool and never an application of it.
///
/// It knows the shapes the API defines for itself — zones, records, the chunked storage of a long
/// TXT value — and the public record grammars anybody's DNS publishes in. What it may never know is
/// WHICH zones there are, which names get records or which product's machine they answer for —
/// every such name belongs to a program row or an answer, never to this package.
///
/// So the scan reads every byte of [scanned] — code, comment and fixture alike — against the word
/// list at [wordList]. The test that decides a word stands at the head of that list: could a vendor
/// with the same tool and a completely different product still use this package with that word in
/// it?
///
/// tool/ is not scanned, and that is the harness rather than a loophole. This check has to name the
/// words it forbids in order to search for them, and nothing under tool/ is compiled into the plugin
/// or shipped with it. It is also why the list is a file there rather than a constant here: a list
/// written into a scanned file would be an occurrence of every word on it.
void main() => auditWordPurity(
  wordListPath: wordList,
  scannedPaths: scanned,
  theRule: 'this plugin names no application of its tool',
);

/// Where the words this plugin may not name live, relative to the package root.
const String wordList = 'tool/tool-purity.words';

/// The directories of this package that are read to the byte.
///
/// Named one at a time rather than as "the package minus its tools", so adding a directory to the
/// scan is a decision somebody makes here rather than a silent widening.
const List<String> scanned = <String>['lib', 'test'];
