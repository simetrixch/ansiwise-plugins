import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import 'composition.dart';

/// The Vault identities a workload PRESENTS, against the ones a program CREATES.
///
/// **Why this file exists.** A login to Vault names a role, and the role names the service accounts
/// it admits. The workload's half stands in the deployed tree — the chart renders the account and
/// writes the role name into the pod's environment — and the program's half stands in the
/// installation's own repository. Nothing held the two together, and they drifted: the manager ran
/// as `manager` and presented the role `manager` while the program created a role `controller` bound
/// to an account `controller` that nothing anywhere renders.
///
/// **A drift here is silent and total.** The login is refused before any policy is consulted, so
/// every credential of that workload is unreachable while the seed that wrote them reports success
/// and the entries sit in the store, written and correct. Nothing in the run says a word.
///
/// **Both halves are read, neither is restated.** A test that carried its own table of role names
/// would be a third statement of the same fact, and the way this defect arrives is a second one.
void main() {
  group('a role a workload presents is a role the program creates', () {
    test(
      'every VAULT_K8S_ROLE in the deployed tree is created by a program of this installation',
      () {
        final Map<String, String> presented = _rolesPresented();
        expect(
          presented,
          isNotEmpty,
          reason:
              'no workload of the deployed tree names a Vault role, which means this test read the '
              'wrong tree or the wrong key rather than that the tree is clean',
        );

        final Set<String> created = _rolesCreated();
        for (final MapEntry<String, String> pair in presented.entries) {
          expect(
            created,
            contains(pair.value),
            reason:
                '${pair.key} presents the Vault role "${pair.value}" and no program of this '
                'installation creates it. The login is refused before any policy is read, so every '
                'credential that workload holds is unreachable and nothing reports it',
          );
        }
      },
    );

    test('a role is bound to a service account the deployed tree really renders', () {
      final Set<String> rendered = _serviceAccountsRendered();
      expect(rendered, isNotEmpty, reason: 'the deployed tree renders no service account at all');

      final Map<String, Set<String>> bound = _accountsBound();
      final Map<String, Set<String>> unknown = <String, Set<String>>{
        for (final MapEntry<String, Set<String>> pair in bound.entries)
          if (pair.value.difference(rendered) case final Set<String> missing
              when missing.isNotEmpty)
            pair.key: missing,
      };

      expect(
        unknown,
        isEmpty,
        reason:
            'a role bound to an account nothing renders admits nobody. A program cannot rename '
            'an account a chart creates, so where these differ it is the program that follows',
      );
    });
  });
}

/// The Vault role each workload of the deployed tree presents, by the file that writes it.
///
/// Read out of the deployment templates rather than out of a list here: the value is a literal the
/// chart writes into the pod's environment, and a copy of it in this file would be the third
/// statement of a fact that already has two.
Map<String, String> _rolesPresented() {
  final Map<String, String> found = <String, String>{};
  for (final File file in _templatesOf(deployedRoot)) {
    final List<String> lines = file.readAsLinesSync();
    for (int at = 0; at < lines.length - 1; at += 1) {
      if (!lines[at].contains('name: VAULT_K8S_ROLE')) {
        continue;
      }
      // The value stands on the line below the name, and only a literal is readable here — a value
      // composed from a template expression is a fact this test cannot hold and must not pretend to.
      final RegExpMatch? value = RegExp(r'value:\s*"?([a-z0-9-]+)"?\s*$').firstMatch(lines[at + 1]);
      if (value != null) {
        found['${_shortPath(file)}:${at + 2}'] = value.group(1)!;
      }
    }
  }
  return found;
}

/// Every service account name the deployed tree renders, from BOTH ways it names one.
///
/// A template that writes the name as a literal is only half of it. The secret-store chart takes its
/// account's name as a value, so `apps/postgresql/values.yaml` naming `postgres-eso` renders an
/// account of that name just as surely — and a scan that read templates alone would report two live
/// accounts as rendered by nothing. A check that cries wolf is retired by whoever it wakes, which
/// costs exactly as much as one that never fires.
Set<String> _serviceAccountsRendered() => <String>{
  for (final File file in _templatesOf(deployedRoot))
    ..._namesUnder(file.readAsLinesSync(), afterKind: 'ServiceAccount'),
  for (final File file in _valuesOf(deployedRoot))
    for (final String raw in file.readAsLinesSync())
      if (RegExp(r'^\s*serviceAccountName:\s*([a-z0-9-]+)\s*$').firstMatch(raw) case final m?)
        m.group(1)!,
};

/// Every values file of every application of [root].
Iterable<File> _valuesOf(String root) sync* {
  final Directory apps = Directory('$root/apps');
  if (!apps.existsSync()) {
    return;
  }
  for (final FileSystemEntity each in apps.listSync(recursive: true)) {
    if (each is File && each.uri.pathSegments.last.startsWith('values')) {
      yield each;
    }
  }
}

/// The roles the programs of this installation create.
Set<String> _rolesCreated() => <String>{
  for (final ProgramStep entry in _authRoles()) entry.arguments.text('role'),
};

/// The service accounts each created role admits, by the role's name.
Map<String, Set<String>> _accountsBound() {
  final Map<String, Set<String>> bound = <String, Set<String>>{};
  for (final ProgramStep entry in _authRoles()) {
    final Object? body = jsonDecode(entry.arguments.text('body'));
    if (body case <String, Object?>{'bound_service_account_names': final List<Object?> names}) {
      bound[entry.arguments.text('role')] = <String>{for (final Object? each in names) '$each'};
    }
  }
  return bound;
}

/// Every `vault_auth_role` row of every program of this installation.
///
/// EVERY program and not one: a role created by another program is still a role, and a scan limited
/// to one file would answer that a presented role is uncreated when it is simply created elsewhere.
List<ProgramStep> _authRoles() => <ProgramStep>[
  for (final File file in Directory(
    installationProgramsRoot,
  ).listSync().whereType<File>().where((File each) => each.path.endsWith('.yaml')))
    for (final ProgramStep entry in loadProgram(
      file.readAsStringSync(),
      where: file.uri.pathSegments.last,
    ).steps)
      if (entry.step == const StepName('vault_auth_role')) entry,
];

/// The `metadata.name` of every document of [afterKind] in [lines].
Set<String> _namesUnder(List<String> lines, {required String afterKind}) {
  final Set<String> names = <String>{};
  bool inKind = false;
  for (final String raw in lines) {
    if (raw.startsWith('---') || raw.startsWith('kind:')) {
      inKind = raw == 'kind: $afterKind';
    }
    if (!inKind) {
      continue;
    }
    final RegExpMatch? name = RegExp(r'^\s\sname:\s*([a-z0-9-]+)\s*$').firstMatch(raw);
    if (name != null) {
      names.add(name.group(1)!);
      inKind = false;
    }
  }
  return names;
}

/// Every template file of every application of [root].
Iterable<File> _templatesOf(String root) sync* {
  final Directory apps = Directory('$root/apps');
  if (!apps.existsSync()) {
    return;
  }
  for (final FileSystemEntity each in apps.listSync(recursive: true)) {
    if (each is File && each.path.endsWith('.yaml') && each.path.contains('templates')) {
      yield each;
    }
  }
}

/// [file]'s path from the deployed tree down, for a message somebody can open.
String _shortPath(File file) =>
    file.path.replaceAll('\\', '/').split('/').skipWhile((String p) => p != 'apps').join('/');
