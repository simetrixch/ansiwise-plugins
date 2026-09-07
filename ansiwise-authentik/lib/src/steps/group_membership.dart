import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'settings_value.dart';

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
/// first operator is refused by every one of those services. Closing that gap by having the
/// provider INVENT the group name in the claim for anybody it considers privileged admits people on
/// a value computed at token time rather than on a membership anyone can look at. This step closes
/// it by making the membership real.
///
/// **The account and the group are the row's, never this package's.** Which account a provider's
/// bootstrap creates is a fact about that provider, and which group a platform admits on is a fact
/// about that platform. Neither is knowable here.
///
/// **THE TOKEN AND THE GROUP ARE WAITED FOR.** Both are objects the provider applies from its own
/// configuration, and it applies them on its own schedule after coming up — so a run that reaches
/// this row while that is still happening is refused the question by a provider that would have
/// answered it a minute later. The row carries a clock for exactly those two: a credential the
/// provider does not accept yet, a server error from a provider still starting, and a group that is
/// not there are each "not yet", asked again every `interval_seconds` until `timeout_seconds` runs
/// out, and only then refused by name with how long it was given. Every other answer is refused at
/// once, because no clock turns a wrong address or a missing account into a right one.
final class GroupMembership extends ReversibleStep<bool> {
  /// Puts [user] into [group] on the provider served at [subdomain] of the answered domain.
  const GroupMembership({
    required this.subdomain,
    required this.domain,
    required this.user,
    required this.group,
    required this.tokenPath,
    this.timeoutSeconds = 300,
    this.intervalSeconds = 5,
  });

  /// Builds the step from what the program gave it.
  factory GroupMembership.fromArguments(Arguments arguments) => GroupMembership(
    subdomain: arguments.text('subdomain'),
    domain: SettingsValue(
      what: 'the domain the provider is served on',
      answer: arguments.optionalText('domain_answer'),
      key: arguments.optionalText('domain_key'),
      settingsPath: arguments.optionalText('settings_path'),
      runAnswer: arguments.optionalText('run_answer'),
    ),
    user: arguments.text('user'),
    group: arguments.text('group'),
    tokenPath: arguments.text('token_path'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
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
      required: false,
      describes:
          'the name of the answer holding the domain the provider is served on. Named rather than '
          'written, because a run is what knows which installation this is. Write "domain_key" '
          'instead where a settings file of the machine already carries it',
    ),
    // THE OTHER SOURCE OF THE SAME VALUE. A domain handed to a row as an answer is a COPY of what a
    // settings file of the machine already says, and a copy is what a caller gets wrong. A key
    // names the one place the value stands, so there is nothing to keep in step. Where a row names
    // both, the answer is read and the record says which key was not.
    ArgumentSpec(
      name: 'settings_path',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the settings file "domain_key" is read out of, as a path on the machine. It may carry '
          'the slot "run_answer" names. Leave it off where the domain is answered',
    ),
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in '
          '"settings_path" — write "fqdn" here and a "<fqdn>" in the path is filled with the value '
          'this run holds. Leave it off where the file is named the same on every installation',
    ),
    ArgumentSpec(
      name: 'domain_key',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the key of that settings file the domain stands under, as a dotted path — each dot '
          'descends one map. Write it instead of "domain_answer", never beside it',
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
      band: IntegerBand.between(
        least: 1,
        most: 86400,
        because:
            'a bound of zero seconds gives up before it looks, and one longer than a day outlives the run it bounds',
      ),
      required: false,
      defaultValue: 300,
      describes:
          'how long the token the provider accepts and the group it carries are given before this '
          'row reports that they did not come. Both are applied by the provider from its own '
          'configuration, on its own schedule after it comes up, and this is the window that '
          'covers it',
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 3600,
        because:
            'a gap of zero seconds asks without pausing, and one longer than an hour is a wait rather than a gap between looks',
      ),
      required: false,
      defaultValue: 5,
      describes: 'how long to leave between asks',
    ),
  ];

  /// The label the provider is served under.
  final String subdomain;

  /// Where the domain it is served on comes from: an answer, or a key of a settings file.
  final SettingsValue domain;

  /// The account this row puts into the group.
  final String user;

  /// The group it goes into.
  final String group;

  /// The file the API token stands in.
  final String tokenPath;

  /// How long the token's acceptance and the group are given.
  final int timeoutSeconds;

  /// How long to leave between asks.
  final int intervalSeconds;

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
      body:
          'the account $user, added to the members $group already has, after up to '
          '${timeoutSeconds}s waiting for the token and the group the provider applies from its '
          'own configuration',
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
        // THE ACT IS NOT A POLL, so it is not held to the gap between two asks: it happens once,
        // and the only bound the row states for it is its own clock.
        timeout: Duration(seconds: timeoutSeconds),
      ),
    );
    if (!answer.ok) {
      throw RequestRefused(method: 'POST', url: url, status: answer.status, body: answer.body);
    }
  }

  /// Where the provider is and what this run may ask it with, or why neither can be had.
  Future<_Reach> _reachable(StepContext context) async {
    final ({String? value, String? refusal}) served = await domain.valueIn(context);
    if (served.refusal case final String refusal) {
      return _Reach.unreachable(refusal);
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
    return _Reach(url: 'https://$subdomain.${served.value}', token: token);
  }

  /// Who and which group the provider knows, once the two the provider's bootstrap makes are there.
  ///
  /// **THE CLOCK IS HERE AND NOT IN ONE METHOD OF THE FIVE**, because every one of them asks this
  /// question: the check either side of the apply, the capture the undo rests on, the apply itself
  /// and the undo. A wait written into the check alone would leave the capture reading a provider
  /// that has not answered yet and recording "the account was already a member" — an undo that then
  /// leaves behind exactly what this run put there. [plan] is the one caller that does not come
  /// through here, so a dry run says what it would do and waits for nothing.
  ///
  /// What each ask costs is the gap between two asks and no more: an ask that outlives the interval
  /// has stopped being a poll, because the next one is already due.
  Future<_Membership> _membership(StepContext context, _Reach reach) async {
    final DateTime giveUp = context.clock.now().add(Duration(seconds: timeoutSeconds));
    while (true) {
      final _Membership found = await _look(context, reach);
      if (found.notYet case final String because) {
        if (context.clock.now().isBefore(giveUp)) {
          context.log.info('$because — asking again in ${intervalSeconds}s');
          await context.clock.sleep(Duration(seconds: intervalSeconds));
          continue;
        }
        return _Membership.refused('$because, and this row waited ${timeoutSeconds}s for it');
      }
      return found;
    }
  }

  /// What one ask found: the two identifiers, why there is nothing yet, or why there never will be.
  ///
  /// **BOTH ARE LOOKED UP BY NAME AND NEITHER IS CREATED.** A group this run invented would admit
  /// nobody anything is bound to, and an account it invented would hold the group and none of the
  /// credentials a person reaches the platform through. Where either is missing this row is refused
  /// and says which one, because both are put there by something else and the answer an operator
  /// needs is which of those two did not run.
  ///
  /// **THE GROUP IS "NOT YET" AND THE ACCOUNT IS NOT.** The group is applied by the provider's own
  /// configuration on its own schedule, so its absence is a moment in time; the account the row
  /// names is one the row got wrong or one nothing created, and waiting out a clock in front of a
  /// misspelt name reports a timeout where the answer was already there.
  Future<_Membership> _look(StepContext context, _Reach reach) async {
    final _Answer groups = await _one(
      context,
      reach,
      'core/groups/?name=${Uri.encodeQueryComponent(group)}',
    );
    if (groups.refusal case final String refusal) {
      return _Membership.refused(refusal);
    }
    if (groups.notYet case final String because) {
      return _Membership.notYet(because);
    }
    final Object? held = groups.found;
    if (held is! Map<String, Object?>) {
      return _Membership.notYet(
        'the provider at ${reach.url} carries no group called "$group" yet, and this row puts an '
        'account into it — the group is declared by the provider\'s own configuration, which it '
        'applies on its own schedule after coming up',
      );
    }
    final _Answer users = await _one(
      context,
      reach,
      'core/users/?username=${Uri.encodeQueryComponent(user)}',
    );
    if (users.refusal case final String refusal) {
      return _Membership.refused(refusal);
    }
    if (users.notYet case final String because) {
      return _Membership.notYet(because);
    }
    final Object? account = users.found;
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

  /// The single object the provider answers a name query with, or why there is no answer to read.
  ///
  /// **A LIST WITH ONE ENTRY, and a list with none is not an error to this provider.** It answers a
  /// query that matched nothing with an empty page and status 200, so a step that only checked the
  /// status would go on to read a member list out of nothing.
  ///
  /// **"IT REFUSED THE QUESTION" AND "IT HAS NO SUCH THING" ARE DIFFERENT ANSWERS.** Folded into
  /// one, a run whose credential has not reached the provider yet reports that the provider carries
  /// no group of that name — a true-sounding sentence about something the step was never allowed to
  /// look at, and whoever reads it goes looking for a group that is there all along.
  ///
  /// **"NOT ACCEPTED YET" AND "NOT ACCEPTED" ARE THE SAME ANSWER FROM THE PROVIDER**, and the row's
  /// clock is what tells them apart: the token this row asks with is one the provider applies from
  /// its own configuration after coming up, so a 401 or a 403 is what the window before that looks
  /// like. A server error is that same window seen from the other side — the provider is up enough
  /// to route the request and not up enough to answer it. Every other status is refused at once,
  /// because no clock turns an address that answers 404 into one that answers the group.
  Future<_Answer> _one(StepContext context, _Reach reach, String query) async {
    final String url = '${reach.url}/api/v3/$query';
    final HttpAnswer answer = await context.http.send(
      HttpRequest(
        'GET',
        url,
        headers: <String, String>{'authorization': 'Bearer ${reach.token}'},
        timeout: Duration(seconds: intervalSeconds),
      ),
    );
    if (answer.status == 401 || answer.status == 403) {
      return _Answer.notYet(
        'the credential in $tokenPath is not one the provider at ${reach.url} accepts yet — it '
        'refused the question with $url, and the token it does accept is one it applies from its '
        'own configuration on its own schedule after coming up',
      );
    }
    if (answer.status >= 500) {
      return _Answer.notYet(
        'the provider at ${reach.url} answered ${answer.status} to $url, so nothing here has '
        'looked at what it holds',
      );
    }
    if (!answer.ok) {
      return _Answer.refused(
        'the provider at ${reach.url} answered ${answer.status} to $url, so nothing here has '
        'looked at what it holds',
      );
    }
    final Object? decoded = jsonDecode(answer.body);
    if (decoded is! Map<String, Object?>) {
      return _Answer.refused(
        'the provider at ${reach.url} answered $url with something that is not a page of results',
      );
    }
    final Object? results = decoded['results'];
    if (results is! List<Object?> || results.length != 1) {
      return const _Answer.none();
    }
    return _Answer.of(results.first);
  }
}

/// What one name query came back with: the object, nothing, why there is nothing to read yet, or
/// why there is nothing to read at all.
final class _Answer {
  const _Answer.of(this.found) : refusal = null, notYet = null;

  const _Answer.none() : found = null, refusal = null, notYet = null;

  const _Answer.refused(String this.refusal) : found = null, notYet = null;

  const _Answer.notYet(String this.notYet) : found = null, refusal = null;

  final Object? found;
  final String? refusal;

  /// Why the provider has not answered this yet, for a caller holding a clock.
  final String? notYet;
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
    : refusal = null,
      notYet = null;

  const _Membership.refused(String this.refusal)
    : userId = null,
      groupId = '',
      holds = false,
      notYet = null;

  const _Membership.notYet(String this.notYet)
    : userId = null,
      groupId = '',
      holds = false,
      refusal = null;

  final Object? userId;
  final String groupId;
  final bool holds;
  final String? refusal;

  /// Why the two the provider's bootstrap makes are not both there yet, or null once they are.
  final String? notYet;
}
