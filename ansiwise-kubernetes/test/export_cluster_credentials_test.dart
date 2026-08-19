import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// Harvesting the credentials another machine's manager drives this cluster with, and the
/// properties everything here circles: the tokens leave through the FILE alone, the address is the
/// caller's statement and never a measurement, and an unpopulated Secret is waited for — bounded —
/// rather than read as empty.
void main() {
  const StepName under = StepName('export_cluster_credentials');
  const String server = 'https://198.51.100.7:16443';
  const String adminToken = 'ThisIsNotARealAdminTokenItIsATestFixture';
  const String reviewToken = 'ThisIsNotARealReviewTokenItIsATestFixture';
  const String authority = 'Q0EgYnVuZGxlIGZpeHR1cmU=';
  const String file = '/tmp/cluster-credentials';

  const ExportClusterCredentials step = ExportClusterCredentials(
    namespace: 'kube-system',
    tokens: <String>['adminToken=admin-token', 'reviewToken=review-token'],
    serverAnswer: 'api_server_url',
    filePath: file,
  );

  const Arguments stated = Arguments(<String, Object>{'api_server_url': server});

  String secretJson(String token) => jsonEncode(<String, Object?>{
    'data': <String, String>{'token': base64Encode(utf8.encode(token)), 'ca.crt': authority},
  });

  ClusterMachine populated() {
    final ClusterMachine machine = ClusterMachine();
    machine.shell.answers(
      'kubectl -n kube-system get secret admin-token -o json',
      secretJson(adminToken),
    );
    machine.shell.answers(
      'kubectl -n kube-system get secret review-token -o json',
      secretJson(reviewToken),
    );
    return machine;
  }

  test('the file carries the stated address, the authority and every decoded token — and mode '
      'keeps it to this account', () async {
    final ClusterMachine machine = populated();
    final StepContext context = machine.contextFor(under, Arguments.none, stated);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    final Map<String, Object?> written =
        jsonDecode(machine.files.contents[file]!) as Map<String, Object?>;
    expect(written['server'], server);
    expect(written['caData'], authority);
    expect(written['adminToken'], adminToken);
    expect(written['reviewToken'], reviewToken);
    expect(machine.files.modes[file], 0x180);
  });

  test('a second run over the same cluster state has nothing to do', () async {
    final ClusterMachine machine = populated();
    final StepContext context = machine.contextFor(under, Arguments.none, stated);
    await step.apply(context);

    expect(await step.check(context), isA<Satisfied>());
  });

  test('a token the cluster rotated makes the file work again — the check compares, never merely '
      'looks for the file', () async {
    // The planted defect: a check satisfied on the file's existence would hand the caller the OLD
    // token after a rebuild, and the failure would surface on the other machine as a refusal.
    final ClusterMachine machine = populated();
    machine.files.contents[file] = '{"server":"$server","stale":"yes"}\n';

    expect(await step.check(machine.contextFor(under, Arguments.none, stated)), isA<Ready>());
  });

  test(
    'an unpopulated Secret is waited for, bounded, and then named — never read as empty',
    () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers('kubectl -n kube-system get secret admin-token -o json', '{"data":{}}');
      machine.shell.answers(
        'kubectl -n kube-system get secret review-token -o json',
        secretJson(reviewToken),
      );

      await expectLater(
        step.apply(machine.contextFor(under, Arguments.none, stated)),
        throwsA(isA<StateError>()),
      );

      expect(machine.files.written, isEmpty);
      expect(machine.clock.slept, isNotEmpty);
    },
  );

  test('no token ever rides a command line', () async {
    final ClusterMachine machine = populated();
    await step.apply(machine.contextFor(under, Arguments.none, stated));

    expect(
      machine.shell.ran.where((String c) => c.contains(adminToken) || c.contains(reviewToken)),
      isEmpty,
    );
  });

  test('an undo takes away only a file this run created', () async {
    final ClusterMachine machine = populated();
    final StepContext context = machine.contextFor(under, Arguments.none, stated);

    expect(await step.capture(context), isFalse);
    await step.apply(context);
    await step.undo(context, false);
    expect(machine.files.contents.containsKey(file), isFalse);

    machine.files.contents[file] = 'somebody else\'s';
    await step.undo(context, true);
    expect(machine.files.contents[file], 'somebody else\'s');
  });
}
