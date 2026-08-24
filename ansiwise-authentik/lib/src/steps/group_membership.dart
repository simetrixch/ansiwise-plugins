import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

/// Puts one account into one group of the identity provider, and takes it out again on an undo.
///
/// **ADDITIVE, and that is the whole reason this is a step.** The provider's own declarative form
/// states a group WITH its member list, so re-applying it sets the membership to exactly what the
/// declaration names and removes everyone else — which is why such a declaration has to be marked
/// "create once and never touch again", and why it therefore does nothing at all on an installation
/// where the group already exists. A declaration that may never be re-applied cannot converge, and
/// one that converges would delete the people an operator added by hand. This step has neither
/// problem: it adds one account and knows nothing about the others.
///
/// **WHAT IT IS FOR.** Everything on this platform that accepts a browser login decides on a group
/// carried in the token's claim. On a fresh installation the only person who exists is the account
/// the provider's own bootstrap made, and nothing has put them into the platform's group — so the
/// first operator is refused by every one of those services. That gap used to be closed by having
/// the provider INVENT the group name in the claim for anybody it considered privileged, which
/// admits people on a value computed at token time rather than on a membership anyone can look at.
/// This step closes it by making the membership real.
///
/// **The account and the group are the row's, never this package's.** Which account a provider's
/// bootstrap creates is a fact about that provider, and which group a platform admits on is a fact
/// about that platform. Neither is knowable here.
final class GroupMembership extends ReversibleStep<bool> {
  /// Puts [user] into [group] on the provider served at [subdomain] of the answered domain.
  const GroupMembership({
    required this.subdomain,
    required this.domainAnswer,
    required this.user,
    required this.group,
    required this.tokenPath,
    this.timeout = const Duration(seconds: 30),
  });

  /// Builds the step from what the program gave it.
  factory GroupMembership.fromArguments(Arguments arguments) => GroupMembership(
    subdomain: arguments.text('subdomain'),
    domainAnswer: arguments.text('domain_answer'),
    user: arguments.text('user'),
    group: arguments.text('group'),
    tokenPath: arguments.text('token_path'),
    timeout: Duration(seconds: arguments.integer('timeout_seconds')),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'subdomain',
      kind: ArgumentKind.text,
      describes:
          'the label this provider is served under, in front of the domain below — one '
          'installation chooses it, and this package has no opinion about which',
    ),
    ArgumentSpec(
      name: 'domain_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the domain the provider is served on. Named rather than '
          'written, because a run is what knows which installation this is',
    ),
    ArgumentSpec(
      name: 'user',
      kind: ArgumentKind.text,
      describes:
          'the account to put into the group, by the name it logs in under — which account a '
          "provider's own bootstrap creates is a fact about that provider",
    ),
    ArgumentSpec(
      name: 'group',
      kind: ArgumentKind.text,
      describes:
          'the group to put it into, by name — the group a platform admits on is a fact about that '
          'platform, and this package knows none of them',
    ),
    // A PATH AND NOT THE CREDENTIAL. A program file is read by everyone who may read the
    // installation, and a token written into one is a token in a repository. An earlier row puts it
    // there out of wherever this installation keeps its secrets, which is that row's business and
    // not this step's.
    ArgumentSpec(
      name: 'token_path',
      kind: ArgumentKind.text,
      describes:
          "the file holding the provider's API token, written there by an earlier row — the path "
          'and never the token, because a program file is not a place a credential may stand',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      required: false,
      defaultValue: 30,
      describes: 'how long to wait for the provider to answer one request',
    ),
  ];

  /// The label the provider is served under.
  final String subdomain;

  /// The name of the answer holding the domain it is served on.
  final String domainAnswer;

  /// The account this row puts into the group.
  final String user;

  /// The group it goes into.
  final String group;

  /// The file the API token stands in.
  final String tokenPath;

  /// How long to wait for one request.
  final Duration timeout;

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Reach reach = await _reachable(context);
    if (reach.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final _Membership found = await _membership(context, reach);
    if (found.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    return found.holds
        ? CheckResult.satisfied('$user is in $group on ${reach.url}')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final _Reach reach = await _reachable(context);
    if (reach.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'POST',
      '${reach.url}/api/v3/core/groups/<$group>/add_user/',
      body: 'the account $user, added to the members $group already has',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Reach reach = await _reachable(context);
    if (reach.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final _Membership found = await _membership(context, reach);
    if (found.refusal case final String refusal) {
      throw StateError(refusal);
    }
    if (found.holds) {
      return;
    }
    await _member(context, reach, found, add: true);
  }

  /// Whether the account was already in the group before this ran.
  ///
  /// An account somebody else put there is not this run's to take out again: an undo that removed it
  /// would lock a person out of a platform this run never let them into.
  @override
  Future<bool> capture(StepContext context) async {
    final _Reach reach = await _reachable(context);
    if (reach.refusal != null) {
      return true;
    }
    final _Membership found = await _membership(context, reach);
    return found.refusal != null || found.holds;
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    final _Reach reach = await _reachable(context);
    if (reach.refusal != null) {
      return;
    }
    final _Membership found = await _membership(context, reach);
    if (found.refusal != null || !found.holds) {
      return;
    }
    await _member(context, reach, found, add: false);
  }

  /// Adds the account to the group or takes it out, and refuses loudly where the provider does.
  Future<void> _member(
    StepContext context,
    _Reach reach,
    _Membership found, {
    required bool add,
  }) async {
    final String what = add ? 'add_user' : 'remove_user';
    final String url = '${reach.url}/api/v3/core/groups/${found.groupId}/$what/';
    final HttpAnswer answer = await context.http.send(
      HttpRequest(
        'POST',
        url,
        headers: <String, String>{
          'authorization': 'Bearer ${reach.token}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, Object?>{'pk': found.userId}),
        timeout: timeout,
      ),
    );
    if (!answer.ok) {
      throw RequestRefused(method: 'POST', url: url, status: answer.status, body: answer.body);
    }
  }

  /// Where the provider is and what this run may ask it with, or why neither can be had.
  Future<_Reach> _reachable(StepContext context) async {
    if (!context.answers.has(domainAnswer)) {
      return _Reach.unreachable(
        'this run holds no answer called "$domainAnswer", and it is the domain the provider is '
        'served on — without it there is no address to ask',
      );
    }
    final String domain = context.answers.text(domainAnswer);
    if (domain.isEmpty) {
      return _Reach.unreachable(
        '"$domainAnswer" was answered with nothing, so the address would name a host that is only '
        'a subdomain and a slash',
      );
    }
    if (!await context.files.exists(tokenPath)) {
      return _Reach.unreachable(
        '$tokenPath is not there, and it is where the API token stands — the row that writes it out '
        'of this installation\'s secrets runs before this one, so a run reaching here without it '
        'has skipped that row rather than failed it',
      );
    }
    final String token = (await context.files.read(tokenPath)).trim();
    if (token.isEmpty) {
      return _Reach.unreachable(
        '$tokenPath is empty, and a request carrying no credential is refused by the provider as an '
        'anonymous one — which says nothing about this row',
      );
    }
    return _Reach(url: 'https://$subdomain.$domain', token: token);
  }

  /// Who and which group the provider knows, and whether the one is already in the other.
  ///
  /// **BOTH ARE LOOKED UP BY NAME AND NEITHER IS CREATED.** A group this run invented would admit
  /// nobody anything is bound to, and an account it invented would hold the group and none of the
  /// credentials a person reaches the platform through. Where either is missing this row is refused
  /// and says which one, because both are put there by something else and the answer an operator
  /// needs is which of those two did not run.
  Future<_Membership> _membership(StepContext context, _Reach reach) async {
    final Object? held = await _one(
      context,
      reach,
      'core/groups/?name=${Uri.encodeQueryComponent(group)}',
    );
    if (held is! Map<String, Object?>) {
      return _Membership.refused(
        'the provider at ${reach.url} carries no group called "$group", and this row puts an '
        'account into it — the group is declared by the provider\'s own configuration, so a run '
        'reaching here without it has that configuration still to apply',
      );
    }
    final Object? account = await _one(
      context,
      reach,
      'core/users/?username=${Uri.encodeQueryComponent(user)}',
    );
    if (account is! Map<String, Object?>) {
      return _Membership.refused(
        'the provider at ${reach.url} carries no account called "$user", and this row puts it into '
        '"$group"',
      );
    }
    final Object? members = held['users'];
    final Object? id = account['pk'];
    final Object? groupId = held['pk'];
    if (id == null || groupId == null) {
      return const _Membership.refused(
        'the provider answered without an identifier for the account or the group, so there is '
        'nothing to put into anything',
      );
    }
    return _Membership(
      userId: id,
      groupId: '$groupId',
      holds: members is List<Object?> && members.any((Object? each) => each == id),
    );
  }

  /// The single object the provider answers a name query with, or null where it answers none.
  ///
  /// **A LIST WITH ONE ENTRY, and a list with none is not an error to this provider.** It answers a
  /// query that matched nothing with an empty page and status 200, so a step that only checked the
  /// status would go on to read a member list out of nothing.
  Future<Object?> _one(StepContext context, _Reach reach, String query) async {
    final HttpAnswer answer = await context.http.send(
      HttpRequest(
        'GET',
        '${reach.url}/api/v3/$query',
        headers: <String, String>{'authorization': 'Bearer ${reach.token}'},
        timeout: timeout,
      ),
    );
    if (!answer.ok) {
      return null;
    }
    final Object? decoded = jsonDecode(answer.body);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final Object? results = decoded['results'];
    if (results is! List<Object?> || results.length != 1) {
      return null;
    }
    return results.first;
  }
}

/// Where the provider is and what this run may ask it with.
final class _Reach {
  const _Reach({required this.url, required this.token}) : refusal = null;

  const _Reach.unreachable(String this.refusal) : url = '', token = '';

  final String url;
  final String token;
  final String? refusal;
}

/// What the provider knows about the account and the group named on the row.
final class _Membership {
  const _Membership({required this.userId, required this.groupId, required this.holds})
    : refusal = null;

  const _Membership.refused(String this.refusal) : userId = null, groupId = '', holds = false;

  final Object? userId;
  final String groupId;
  final bool holds;
  final String? refusal;
}
