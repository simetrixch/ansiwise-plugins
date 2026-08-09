import 'dart:io';

import 'package:test/test.dart';

import '../tool/analysis_invocation.dart';

/// The analysis check can go red, and it is the ARGUMENTS and the DIRECTORY that are proven.
///
/// The old reason for having no counter-probe here was that nothing parses output — each tool's exit
/// status is the verdict — so there was nothing in between that could stop matching. That is true of
/// the output and it is not true of the invocation, where two edits leave every test green and the
/// gate blind:
///
/// - drop `--fatal-infos`, and every info goes invisible. This package's strictness lives at info:
///   strict casts, strict inference and strict raw types all report there, so without the flag the
///   whole setting is advisory.
/// - point the run at a directory holding no Dart. `dart analyze` exits zero and says "No issues
///   found", and a gate one level too high reports a clean package it never opened.
///
/// THE REAL TOOLS RUN HERE, against a package planted for the purpose. A fake would prove that this
/// file agrees with itself; the question is what `dart analyze` does with these arguments, and only
/// `dart analyze` can answer it. The planted package needs no dependencies: one lint, enabled
/// directly, reports at info like every strictness setting this package relies on.
void main() {
  late Directory scratch;

  setUp(() => scratch = Directory.systemTemp.createTempSync('hostyour-analysis-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  /// A package at [into] whose only fault reports at INFO, or none when [clean].
  void plant(Directory into, {required bool clean}) {
    File('${into.path}/pubspec.yaml').writeAsStringSync(
      'name: planted_package\n'
      'publish_to: none\n'
      'environment:\n'
      "  sdk: '>=3.0.0 <5.0.0'\n",
    );
    File('${into.path}/analysis_options.yaml').writeAsStringSync(
      'linter:\n'
      '  rules:\n'
      '    - prefer_single_quotes\n',
    );
    Directory('${into.path}/lib').createSync(recursive: true);
    File('${into.path}/lib/planted.dart').writeAsStringSync(
      clean ? "const String planted = 'single';\n" : 'const String planted = "double";\n',
    );
  }

  group('the analyzer invocation', () {
    test('goes red on a fault that only reports at info', () async {
      plant(scratch, clean: false);
      expect(
        await runDart(analyzerArgv, directory: scratch.path, quiet: true),
        isNot(0),
        reason:
            'this is the fault class the whole strictness setting of this package produces — strict '
            'casts, strict inference and strict raw types all report at info',
      );
    });

    test('and it is --fatal-infos that catches it', () async {
      plant(scratch, clean: false);
      final List<String> weakened = <String>[
        for (final String argument in analyzerArgv)
          if (argument != '--fatal-infos') argument,
      ];
      expect(
        await runDart(weakened, directory: scratch.path, quiet: true),
        0,
        reason:
            'the same tree, the same tool, one flag fewer, and the fault is gone from the verdict — '
            'which is why dropping that flag is a silent edit and not a visible one',
      );
    });

    test('leaves a clean package alone', () async {
      plant(scratch, clean: true);
      expect(
        await runDart(analyzerArgv, directory: scratch.path, quiet: true),
        0,
        reason: 'a check that cannot go green is as useless as one that cannot go red',
      );
    });
  });

  group('the directory the check is pointed at', () {
    test('a directory with no Dart in it is refused rather than reported clean', () {
      expect(
        holdsDart(scratch),
        isFalse,
        reason:
            'dart analyze answers "No issues found" here and exits zero, so the emptiness has to be '
            'noticed before the tool is asked',
      );
    });

    test('the analyzer really does report an empty directory as clean', () async {
      expect(
        await runDart(analyzerArgv, directory: scratch.path, quiet: true),
        0,
        reason:
            'the reason the guard above exists, asserted rather than assumed: if this ever started '
            'failing on its own, the guard would be dead weight and should come out',
      );
    });

    test('a planted package is seen as holding Dart', () {
      plant(scratch, clean: true);
      expect(holdsDart(scratch), isTrue);
    });

    test('Dart at any depth counts, not only at the top', () {
      Directory('${scratch.path}/lib/src/deep').createSync(recursive: true);
      File('${scratch.path}/lib/src/deep/planted.dart').writeAsStringSync('const int x = 1;\n');
      expect(holdsDart(scratch), isTrue);
    });
  });
}
