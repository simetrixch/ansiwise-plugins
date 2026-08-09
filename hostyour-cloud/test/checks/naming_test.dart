import 'package:test/test.dart';

import 'finding.dart';
import 'naming.dart';
import 'source_tree.dart';

void main() {
  final Naming check = Naming(SourceTree.on(repositoryRoot()));

  test('there are names to judge', () {
    expect(
      check.namesJudged,
      isNotEmpty,
      reason: 'nothing was walked, so this check measured nothing',
    );
  });

  test('there are Dart files to read sub-command declarations out of', () {
    expect(
      check.dartFilesJudged,
      isNotEmpty,
      reason: 'the sub-command half of this check read no file',
    );
  });

  test('no file, directory or sub-command carries an abolished word', () {
    expect(
      check.findings,
      isEmpty,
      reason:
          'the verbs are deploy and onboard, and a step named for the command it runs keeps that '
          'name',
    );
  });

  group('counter-probe', () {
    // Both scans get a planted violation AND a correct neighbour, so a scan that reported
    // everything is caught as surely as one that reports nothing. The correct neighbours are the
    // point of this probe: install_packages.dart and deploy-host.yaml are exactly what a substring
    // match would eat, so they are what reports the check having been "simplified" back into one.

    final Naming planted = Naming(
      SourceTree.planted(<String, String>{
        'pubspec.yaml': 'name: planted_package\n',
        'setup/whatever.dart': 'const int x = 1;',
        'lib/desktop/shell.dart': 'const int x = 2;',
        'install.sh': '#!/bin/sh',
        'programs/setup-cluster.yaml': 'name: p',
        'lib/deploy_host.dart': 'const int x = 3;',
        'lib/install_packages.dart': 'const int x = 4;',
        'programs/deploy-host.yaml': 'name: p',
        'lib/commands.dart': _plantedCommandSource,
      }),
      roots: const <String>{''},
    );
    final List<Finding> names = planted.nameFindings;
    final List<Finding> commands = planted.subCommandFindings;

    for (final String path in <String>[
      'setup',
      'lib/desktop',
      'install.sh',
      'programs/setup-cluster.yaml',
    ]) {
      test('the planted name $path is reported', () {
        expect(about(names, path), isNotEmpty, reason: 'the name scan cannot go red');
      });
    }

    for (final String path in <String>[
      'lib/deploy_host.dart',
      'lib/install_packages.dart',
      'programs/deploy-host.yaml',
    ]) {
      test('$path names the command it runs and is not reported', () {
        expect(
          about(names, path),
          isEmpty,
          reason: 'the name scan has collapsed back into a match on the substring',
        );
      });
    }

    for (final String name in _plantedCommands) {
      test("the planted sub-command '$name' is reported", () {
        expect(
          commands.where((Finding hit) => hit.what.contains('"$name"')),
          isNotEmpty,
          reason: 'the sub-command scan cannot go red',
        );
      });
    }

    for (final String name in _allowedCommands) {
      test("the sub-command '$name' carries no abolished word and is not reported", () {
        expect(commands.where((Finding hit) => hit.what.contains('"$name"')), isEmpty);
      });
    }

    test('a sub-command finding names the line it was declared on', () {
      expect(
        commands.map((Finding hit) => hit.line),
        everyElement(isNotNull),
        reason: 'a declaration nobody can find is a finding nobody can act on',
      );
    });
  });
}

const List<String> _plantedCommands = <String>[
  'install',
  'install-cluster',
  'setup',
  'desktop-cli',
];
const List<String> _allowedCommands = <String>['deploy-cluster', 'onboard'];

/// The planted sub-command declarations, built by interpolation.
///
/// This file is itself scanned by the check it holds. Writing the planted names into the source
/// straight after a marker would declare them here, and the check would report itself; assembled
/// this way the marker on each template line yields the interpolation and not a forbidden name.
final String _plantedCommandSource = <String>[
  for (final String name in <String>[..._plantedCommands.take(2), _allowedCommands.first])
    "  String get name => '$name';",
  for (final String name in <String>[..._plantedCommands.skip(2), _allowedCommands.last])
    "    parser.addCommand('$name');",
].join('\n');
