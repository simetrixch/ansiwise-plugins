import 'dart:convert';

import 'package:ansiwise_authentik/ansiwise_authentik.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

/// Putting one account into one group of the provider, additively.
///
/// **The idempotence audit beside this cannot reach this step, so it is proven here.** That audit
/// answers a request out of a fixed table, and a table does not change because something was posted
/// to it — so the second check would read exactly what the first one did and the run would prove
/// nothing. The provider in this file KEEPS ITS STATE: what is added to the group is what the next
/// query answers, which is the only arrangement under which "the second run has nothing to do" means
/// anything.
void main() {
  const String domain = 'example.invalid';
  const String tokenPath = '/srv/checkout/secrets/provider-dev.txt';
  const String token = 'ThisIsNotARealApiTokenItIsATestFixture';
  const String account = 'bootstrap-admin';
  const String groupName = 'operators';
  const String accountId = 'a0000000-0000-0000-0000-000000000001';

  const GroupMembership step = GroupMembership(
    subdomain: 'idp',
    domainAnswer: 'books_cluster',
    user: account,
    group: groupName,
    tokenPath: tokenPath,
  );

  FakeFiles checkout({String held = token}) => FakeFiles(<String, String>{tokenPath: '$held\n'});

  StepContext contextOn(Http http, {FakeFiles? files}) => StepContext(
    shell: FakeShell(),
    files: files ?? checkout(),
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _NothingSaid(),
    step: const StepName('authentik_group_membership'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'books_cluster': domain}),
    facts: Facts.none,
  );

  test('the account is put into the group, and a second run has nothing left to do', () async {
    // THE POSTCONDITION IS ASKED OF THE PROVIDER, not of the fact that a request returned 200. The
    // provider below answers the second query with what the first request changed, so a step that
    // reported itself finished without having changed anything would fail here.
    final _Provider provider = _Provider(members: <String>[]);

    expect(await step.check(contextOn(provider)), isA<Ready>());
    await step.apply(contextOn(provider));

    expect(provider.members, contains(accountId));
    expect(await step.check(contextOn(provider)), isA<Satisfied>());

    final int posted = provider.posts.length;
    await step.apply(contextOn(provider));
    expect(
      provider.posts.length,
      posted,
      reason: 'the second run found the membership already there and asked for nothing',
    );
  });

  test('an account somebody else put there is left exactly alone', () async {
    // THE INNOCENT CASE. Without it a green suite could mean the step adds on every run, which the
    // provider would accept silently — add_user on a member is not an error.
    final _Provider provider = _Provider(members: <String>[accountId]);

    final CheckResult answer = await step.check(contextOn(provider));

    expect(answer, isA<Satisfied>());
    expect((answer as Satisfied).because, contains(groupName));
    expect(provider.posts, isEmpty);
  });

  test('the step never owns the other members', () async {
    // The whole reason this is a step and not a declaration. A declarative group states its member
    // list, so re-applying it removes whoever is not named — here the row names one account and the
    // rest are none of its business.
    final _Provider provider = _Provider(members: <String>['someone-else', 'and-another']);

    await step.apply(contextOn(provider));

    expect(provider.members, containsAll(<String>['someone-else', 'and-another', accountId]));
  });

  test('a group the provider does not carry is refused by that group\'s name', () async {
    final _Provider provider = _Provider(members: <String>[], hasGroup: false);

    final CheckResult answer = await step.check(contextOn(provider));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains(groupName));
    expect(answer.reason, contains('configuration'));
    expect(provider.posts, isEmpty);
  });

  test('an account the provider does not carry is refused by that account\'s name', () async {
    // Refused and not created. An account this run invented would hold the group and none of the
    // credentials a person reaches the platform through.
    final _Provider provider = _Provider(members: <String>[], hasUser: false);

    final CheckResult answer = await step.check(contextOn(provider));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains(account));
    expect(provider.posts, isEmpty);
  });

  test('a token the earlier row has not written yet is refused by its path', () async {
    final _Provider provider = _Provider(members: <String>[]);
    final CheckResult answer = await step.check(
      contextOn(provider, files: FakeFiles(<String, String>{})),
    );

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains(tokenPath));
    expect(
      provider.asked,
      isEmpty,
      reason: 'nothing was asked of the provider without a credential',
    );
  });

  test('a provider that refuses the question does not become a provider that has nothing', () async {
    // THE SHAPE THIS CATCHES, and it cost a real diagnosis. A run whose credential had not reached
    // the provider yet reported that the provider carried no group of that name — a true-sounding
    // sentence about something the step had never been allowed to look at. Whoever read it went
    // looking for the group, which was there all along.
    final _Provider provider = _Provider(members: <String>[], refusesWith: 403);

    final CheckResult answer = await step.check(contextOn(provider));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains(tokenPath));
    expect(
      answer.reason,
      isNot(contains('carries no group')),
      reason: 'nothing here has looked at what the provider holds, so it may not say what it holds',
    );
  });

  test('a token file that is there and empty is refused too', () async {
    // The half that a "does the file exist" check misses: an empty file is a request the provider
    // answers as an anonymous one, which says nothing about this row.
    final _Provider provider = _Provider(members: <String>[]);
    final CheckResult answer = await step.check(contextOn(provider, files: checkout(held: '')));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('empty'));
  });

  group('undoing', () {
    test('what this run added, it takes back out', () async {
      final _Provider provider = _Provider(members: <String>[]);
      final bool before = await step.capture(contextOn(provider));
      await step.apply(contextOn(provider));

      await step.undo(contextOn(provider), before);

      expect(provider.members, isNot(contains(accountId)));
    });

    test('what it found already there, it leaves', () async {
      // An undo that removed it would lock a person out of a platform this run never let them into.
      final _Provider provider = _Provider(members: <String>[accountId]);
      final bool before = await step.capture(contextOn(provider));

      await step.undo(contextOn(provider), before);

      expect(before, isTrue);
      expect(provider.members, contains(accountId));
    });
  });
}

/// A provider that keeps what it is told, so a second question sees the first answer's effect.
final class _Provider implements Http {
  _Provider({
    required List<String> members,
    this.hasGroup = true,
    this.hasUser = true,
    this.refusesWith,
  }) : members = <String>[...members];

  /// A status the provider answers every question with, where it refuses to answer any.
  final int? refusesWith;

  /// Who is in the group right now.
  final List<String> members;

  /// Whether the provider carries the group and the account the row names.
  final bool hasGroup;
  final bool hasUser;

  /// Every address asked, and every address posted to.
  final List<String> asked = <String>[];
  final List<String> posts = <String>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    asked.add(request.url);
    if (refusesWith case final int status) {
      return HttpAnswer(
        status: status,
        body: '{"detail":"Authentication credentials were not provided."}',
        headers: const <String, String>{},
        elapsed: Duration.zero,
      );
    }
    if (request.method == 'GET' && request.url.contains('/core/groups/?name=')) {
      return _page(
        hasGroup
            ? <Map<String, Object?>>[
                <String, Object?>{'pk': groupId, 'name': 'operators', 'users': members},
              ]
            : const <Map<String, Object?>>[],
      );
    }
    if (request.method == 'GET' && request.url.contains('/core/users/?username=')) {
      return _page(
        hasUser
            ? <Map<String, Object?>>[
                <String, Object?>{'pk': accountId, 'username': 'bootstrap-admin'},
              ]
            : const <Map<String, Object?>>[],
      );
    }
    if (request.method == 'POST' && request.url.endsWith('/add_user/')) {
      posts.add(request.url);
      final Object? pk = (jsonDecode(request.body ?? '{}') as Map<String, Object?>)['pk'];
      if (pk is String && !members.contains(pk)) {
        members.add(pk);
      }
      return _ok('');
    }
    if (request.method == 'POST' && request.url.endsWith('/remove_user/')) {
      posts.add(request.url);
      final Object? pk = (jsonDecode(request.body ?? '{}') as Map<String, Object?>)['pk'];
      members.remove(pk);
      return _ok('');
    }
    return const HttpAnswer(
      status: 404,
      body: '',
      headers: <String, String>{},
      elapsed: Duration.zero,
    );
  }

  static const String groupId = 'g0000000-0000-0000-0000-000000000002';
  static const String accountId = 'a0000000-0000-0000-0000-000000000001';

  HttpAnswer _page(List<Map<String, Object?>> results) =>
      _ok(jsonEncode(<String, Object?>{'results': results}));

  HttpAnswer _ok(String body) => HttpAnswer(
    status: 200,
    body: body,
    headers: const <String, String>{},
    elapsed: Duration.zero,
  );
}

final class _NothingSaid implements Logger {
  const _NothingSaid();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
