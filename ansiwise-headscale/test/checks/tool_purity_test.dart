import 'package:ansiwise_checks/audits.dart';

/// tool-purity — this plugin knows its tool and never an application of it.
///
/// The coordinator's own words — user, pre-auth key, expiration — pass. What may never stand here
/// is any one product built around a coordinator: its namespaces, its workload names, its stages,
/// its substrate — every such name belongs to a program row, and above all the words of the
/// invocation that reaches a coordinator running as a workload, which is one installation's
/// arrangement and arrives as data.
void main() => auditWordPurity(
  wordListPath: wordList,
  scannedPaths: scanned,
  theRule: 'this plugin names no application of its tool',
);

/// Where the words this plugin may not name live, relative to the package root.
const String wordList = 'tool/tool-purity.words';

/// The directories of this package that are read to the byte.
const List<String> scanned = <String>['lib', 'test'];
