/// line-endings — every file this repository declares as LF is LF in the working copy too.
///
/// `.gitattributes` already forces LF in the repository and on checkout. What it does NOT protect is
/// the WORKING COPY on a Windows machine, and the working copy is what the gate judges and what
/// `dart run tool/build.dart` compiles into the binary a Linux machine is given — so an editor or a
/// script that writes CRLF puts a broken file in front of both without git ever seeing it.
///
/// That is not a theoretical failure. It happened: two checks were patched by a Python script, which
/// writes `\r\n` by default on Windows, and on the Linux side the kernel looked for `bash\r`, found
/// nothing, and fell back to `sh` — where `set -o pipefail` does not exist. Both checks reported a
/// shell error instead of a finding, which reads as a broken tree rather than a broken file. The
/// scripts are gone; what wrote them has not changed, and a Dart file the analyzer parses with a
/// stray carriage return on every line is the same class of surprise.
library;

import 'package:path/path.dart' as p;

import 'finding.dart';
import 'source_tree.dart';

/// The file suffixes `.gitattributes` declares `eol=lf`.
///
/// Kept in step with that file by hand rather than parsed out of it: the two say the same thing for
/// different readers, and a parser here would turn a change in one into a silent change in the other.
const Set<String> declaredLineFeed = <String>{
  '.yaml',
  '.yml',
  '.tpl',
  '.json',
  '.conf',
  '.config',
  '.example',
  '.dart',
};

/// How few scanned files mean the walk stopped working rather than the tree being small.
const int tooFewToMeanAnything = 20;

/// The scan itself, over a tree it is given rather than over the repository it lives in.
final class LineEndings {
  /// Judges [tree].
  const LineEndings(this.tree);

  /// The tree being judged.
  final SourceTree tree;

  /// The paths this check reads, sorted.
  ///
  /// A file is read when its suffix is one `.gitattributes` declares, or when it opens with `#!`
  /// whatever it is called — `tools/ops/sync-versions` carried no suffix, and the next one will not
  /// either. A file that is not text is not read at all: a carriage return inside an image is a byte
  /// of the image.
  List<String> get scannedPaths {
    final List<String> paths = <String>[
      for (final MapEntry<String, String?> entry in tree.files.entries)
        if (entry.value case final String text)
          if (declaredLineFeed.contains(p.posix.extension(entry.key)) || text.startsWith('#!'))
            entry.key,
    ];
    return paths..sort();
  }

  /// Every scanned file that carries a carriage return.
  List<Finding> get findings => <Finding>[
    for (final String path in scannedPaths)
      if (tree.textOf(path)?.contains('\r') ?? false)
        Finding(path, 'carries CRLF, and this repository declares it LF'),
  ];
}
