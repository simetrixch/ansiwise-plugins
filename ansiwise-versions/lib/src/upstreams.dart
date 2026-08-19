/// Asking each kind of upstream what it has now, through the framework's network port.
///
/// Everything here READS: every request is a GET, so the whole of it runs under a dry run too, and
/// nothing can change anything at the other end. And nothing here fails a run: an upstream that
/// cannot be resolved is an answer of the shape "?", carried in [UpstreamReading.unresolved] with
/// the reason — because a version appearing on the internet, or a feed being down, must never turn
/// a tree red, or red stops meaning "the tree is sound".
///
/// Three lessons of the predecessor are load-bearing here and named where they bite:
///
/// - **An image is published by a REGISTRY**, and a project can tag a release with no image
///   behind it, so for an image the registry's tag list is asked and never the release feed.
/// - **A tag list is paginated and unsorted.** One page is not an answer, and the maximum is not
///   the last entry: every page is followed and the maximum is taken over all of them. The
///   predecessor once reported an image's newest tag as one two minors old, because the newer
///   tags fell outside the one page it read.
/// - **The pattern decides what is comparable.** A tag list carries every shape a project ever
///   published, so each candidate must match the declared pattern whole before it competes.
library;

import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:yaml/yaml.dart';

/// What asking one upstream produced: the newest version, or why there is no answer.
final class UpstreamReading {
  /// The newest version [newest], as the upstream serves it.
  ///
  /// [caveat] is what weakens the answer without voiding it — a registry that refused the rest of
  /// a list mid-walk. It is printed beside the value, because an answer whose ground shrank and
  /// says nothing about it is the quiet failure this whole report exists to end.
  const UpstreamReading.of(String this.newest, {this.caveat}) : unresolved = null;

  /// No answer, because [unresolved].
  ///
  /// A finding about the report, not about the pin, and it says so rather than staying quiet.
  const UpstreamReading.unresolved(String this.unresolved) : newest = null, caveat = null;

  /// The newest version the upstream serves, or null.
  final String? newest;

  /// What weakens [newest] without voiding it, or null.
  final String? caveat;

  /// Why nothing could be answered, or null.
  final String? unresolved;
}

/// How many pages of a paginated tag list are followed before the reading gives up.
///
/// A bound so a registry that pages forever cannot hang the report; generous because stopping
/// early is exactly the lie pagination invites. Hitting it is reported as unresolved rather than
/// answered from what happened to be read.
const int pageLimit = 200;

/// The latest release tag of [project] on github.com.
Future<UpstreamReading> githubLatestRelease(
  Http http,
  String project, {
  required Duration timeout,
}) async {
  final _Json fetched = await _json(
    http,
    'https://api.github.com/repos/$project/releases/latest',
    timeout: timeout,
    headers: const <String, String>{'Accept': 'application/vnd.github+json'},
  );
  final Object? body = fetched.body;
  if (body == null) {
    return UpstreamReading.unresolved(fetched.whyNot!);
  }
  if (body is Map<String, Object?> && body['tag_name'] is String) {
    return UpstreamReading.of(body['tag_name']! as String);
  }
  return const UpstreamReading.unresolved('the releases feed answered without a tag name');
}

/// The newest tag of [image] on hub.docker.com matching [matching].
///
/// The list is asked newest-updated first and every page is still followed — the ordering is a
/// hedge, not the answer. The hedge is there because this registry rations deep pagination for
/// its largest images and starts refusing after a handful of pages: with recency first, what was
/// served before the refusal carries the living tags, and the reading then answers the maximum
/// over exactly that, SAYING SO, instead of either trusting one page or answering nothing.
Future<UpstreamReading> dockerHubNewestTag(
  Http http,
  String image,
  String matching, {
  required Duration timeout,
}) async {
  final List<String> tags = <String>[];
  String? url =
      'https://hub.docker.com/v2/repositories/$image/tags?page_size=100&ordering=last_updated';
  for (int page = 0; url != null; page++) {
    if (page >= pageLimit) {
      return UpstreamReading.unresolved(
        'the tag list of $image did not end within $pageLimit pages',
      );
    }
    final _Json fetched = await _json(http, url, timeout: timeout);
    final Object? body = fetched.body;
    if (body == null) {
      if (tags.isNotEmpty) {
        final UpstreamReading partial = _newest(tags, matching, of: image);
        return partial.newest == null
            ? UpstreamReading.unresolved(fetched.whyNot!)
            : UpstreamReading.of(
                partial.newest!,
                caveat:
                    'the registry refused the rest of the list after $page page(s), newest-updated '
                    'first; this is the maximum over what it served',
              );
      }
      return UpstreamReading.unresolved(fetched.whyNot!);
    }
    if (body is! Map<String, Object?>) {
      return UpstreamReading.unresolved('the tag list of $image answered an unexpected shape');
    }
    if (body['results'] case final List<Object?> results) {
      for (final Object? result in results) {
        if (result is Map<String, Object?> && result['name'] is String) {
          tags.add(result['name']! as String);
        }
      }
    }
    url = body['next'] as String?;
  }
  return _newest(tags, matching, of: image);
}

/// The newest tag of [image] on the registry at [host] matching [matching].
///
/// The registry speaks the distribution protocol: an anonymous request may be answered 401 with
/// the token endpoint named in its own WWW-Authenticate header, and the tag list pages through
/// Link headers. Both are followed rather than assumed, so any registry of that protocol answers
/// and none is named here.
Future<UpstreamReading> registryNewestTag(
  Http http,
  String host,
  String image,
  String matching, {
  required Duration timeout,
}) async {
  String? token;
  final List<String> tags = <String>[];
  String? url = 'https://$host/v2/$image/tags/list?n=1000';
  for (int page = 0; url != null; page++) {
    if (page >= pageLimit) {
      return UpstreamReading.unresolved(
        'the tag list of $host/$image did not end within $pageLimit pages',
      );
    }
    final HttpAnswer answer;
    try {
      answer = await http.send(
        HttpRequest(
          'GET',
          url,
          timeout: timeout,
          headers: token == null
              ? const <String, String>{}
              : <String, String>{'Authorization': 'Bearer $token'},
        ),
      );
    } on Object catch (failure) {
      return UpstreamReading.unresolved('$url could not be asked — $failure');
    }
    if (answer.status == 401 && token == null) {
      final ({String? token, String? whyNot}) minted = await _bearerToken(
        http,
        answer,
        image,
        timeout: timeout,
      );
      if (minted.token == null) {
        return UpstreamReading.unresolved(minted.whyNot!);
      }
      token = minted.token;
      continue;
    }
    if (!answer.ok) {
      return UpstreamReading.unresolved('$url answered ${answer.status}');
    }
    final Object? body = _decoded(answer.body);
    if (body is! Map<String, Object?>) {
      return UpstreamReading.unresolved(
        'the tag list of $host/$image answered an unexpected shape',
      );
    }
    if (body['tags'] case final List<Object?> served) {
      for (final Object? tag in served) {
        if (tag is String) {
          tags.add(tag);
        }
      }
    }
    url = _nextLinked(answer, host);
  }
  return _newest(tags, matching, of: '$host/$image');
}

/// The newest three-part version of [chart] in the repository at [repository].
///
/// A classic repository answers with an index document; an `oci://` one is a registry whose tag
/// list is read the paginated way above. The two are not interchangeable, and which one a chart
/// comes from is the declaration's to say — usually by not saying it at all and letting the
/// stamped Chart.yaml answer.
Future<UpstreamReading> chartNewestVersion(
  Http http,
  String repository,
  String chart, {
  required Duration timeout,
}) async {
  if (repository.startsWith('oci://')) {
    final String stripped = repository.substring('oci://'.length);
    final int cut = stripped.indexOf('/');
    if (cut <= 0) {
      return UpstreamReading.unresolved('"$repository" names no path on its registry');
    }
    return registryNewestTag(
      http,
      stripped.substring(0, cut),
      '${stripped.substring(cut + 1)}/$chart',
      r'^[0-9]+\.[0-9]+\.[0-9]+$',
      timeout: timeout,
    );
  }
  final String base = repository.endsWith('/') ? repository : '$repository/';
  final String url = '${base}index.yaml';
  final HttpAnswer answer;
  try {
    answer = await http.send(HttpRequest('GET', url, timeout: timeout));
  } on Object catch (failure) {
    return UpstreamReading.unresolved('$url could not be asked — $failure');
  }
  if (!answer.ok) {
    return UpstreamReading.unresolved('$url answered ${answer.status}');
  }
  final Object? index;
  try {
    index = loadYaml(answer.body);
  } on YamlException {
    return UpstreamReading.unresolved('$url is not a readable index');
  }
  if (index is! YamlMap || index['entries'] is! YamlMap) {
    return UpstreamReading.unresolved('$url carries no entries');
  }
  final Object? entries = (index['entries'] as YamlMap)[chart];
  if (entries is! YamlList) {
    return UpstreamReading.unresolved('the index at $url lists no chart "$chart"');
  }
  final List<String> versions = <String>[
    for (final Object? entry in entries)
      if (entry is YamlMap && entry['version'] is String) entry['version']! as String,
  ];
  return _newest(versions, r'^[0-9]+\.[0-9]+\.[0-9]+$', of: chart);
}

/// The newest stable track of [snap] in the snap store, in the pin's own shape `<track>/stable`.
Future<UpstreamReading> snapNewestStableTrack(
  Http http,
  String snap, {
  required Duration timeout,
}) async {
  final _Json fetched = await _json(
    http,
    'https://api.snapcraft.io/v2/snaps/info/$snap',
    timeout: timeout,
    headers: const <String, String>{'Snap-Device-Series': '16'},
  );
  final Object? body = fetched.body;
  if (body == null) {
    return UpstreamReading.unresolved(fetched.whyNot!);
  }
  if (body is! Map<String, Object?> || body['channel-map'] is! List<Object?>) {
    return UpstreamReading.unresolved('the store answered without a channel map for $snap');
  }
  final List<String> tracks = <String>[];
  for (final Object? held in body['channel-map']! as List<Object?>) {
    if (held is! Map<String, Object?> || held['channel'] is! Map<String, Object?>) {
      continue;
    }
    final Map<String, Object?> channel = held['channel']! as Map<String, Object?>;
    if (channel['risk'] == 'stable' &&
        channel['architecture'] == 'amd64' &&
        channel['track'] is String) {
      tracks.add(channel['track']! as String);
    }
  }
  final UpstreamReading newest = _newest(tracks, r'^[0-9]+\.[0-9]+$', of: snap);
  return newest.newest == null ? newest : UpstreamReading.of('${newest.newest}/stable');
}

/// The latest version of [product] on the hashicorp releases feed, in the pin's own `v` shape.
Future<UpstreamReading> hashicorpLatestVersion(
  Http http,
  String product, {
  required Duration timeout,
}) async {
  final _Json fetched = await _json(
    http,
    'https://api.releases.hashicorp.com/v1/releases/$product/latest',
    timeout: timeout,
  );
  final Object? body = fetched.body;
  if (body == null) {
    return UpstreamReading.unresolved(fetched.whyNot!);
  }
  if (body is Map<String, Object?> && body['version'] is String) {
    return UpstreamReading.of('v${body['version']! as String}');
  }
  return UpstreamReading.unresolved('the releases feed answered without a version for $product');
}

/// The highest of [candidates] matching [matching] whole, compared by their numbers.
///
/// The comparison reads every run of digits and holds them against each other in order, so
/// `10.2.1` stands above `9.9.9` and a `12-slim` above an `11-slim` — a plain text sort puts
/// both the other way around. Ties fall back to the text itself, so the answer is deterministic.
UpstreamReading _newest(Iterable<String> candidates, String matching, {required String of}) {
  final RegExp shape = RegExp(matching);
  final List<String> matched = <String>[
    for (final String candidate in candidates)
      if (shape.stringMatch(candidate) == candidate) candidate,
  ];
  if (matched.isEmpty) {
    return UpstreamReading.unresolved('$of serves no version matching $matching');
  }
  matched.sort(_byNumbers);
  return UpstreamReading.of(matched.last);
}

int _byNumbers(String a, String b) {
  final List<int> left = _numbers(a);
  final List<int> right = _numbers(b);
  for (int i = 0; i < left.length && i < right.length; i++) {
    final int order = left[i].compareTo(right[i]);
    if (order != 0) {
      return order;
    }
  }
  final int order = left.length.compareTo(right.length);
  return order != 0 ? order : a.compareTo(b);
}

List<int> _numbers(String text) => <int>[
  for (final RegExpMatch match in RegExp(r'\d+').allMatches(text)) int.parse(match[0]!),
];

/// The token a registry's own WWW-Authenticate header says to fetch, for pulling [image].
Future<({String? token, String? whyNot})> _bearerToken(
  Http http,
  HttpAnswer refused,
  String image, {
  required Duration timeout,
}) async {
  final String challenge = _header(refused, 'www-authenticate') ?? '';
  final String? realm = _challengeField(challenge, 'realm');
  if (realm == null) {
    return (token: null, whyNot: 'the registry refused anonymously and named no token endpoint');
  }
  final String? service = _challengeField(challenge, 'service');
  final String url =
      '$realm?scope=repository:$image:pull${service == null ? '' : '&service=${Uri.encodeQueryComponent(service)}'}';
  final _Json fetched = await _json(http, url, timeout: timeout);
  final Object? body = fetched.body;
  if (body == null) {
    return (token: null, whyNot: fetched.whyNot);
  }
  if (body is Map<String, Object?> && body['token'] is String) {
    return (token: body['token']! as String, whyNot: null);
  }
  return (token: null, whyNot: 'the token endpoint answered without a token');
}

String? _challengeField(String challenge, String field) {
  final RegExpMatch? match = RegExp('$field="([^"]*)"').firstMatch(challenge);
  return match?[1];
}

/// The next page a Link header names, made absolute against [host], or null.
///
/// Header lines arrive ending in a carriage return on some transports, and one left in place
/// lands in the middle of the next address — where every follow-up request fails in silence. It
/// is stripped here, once, rather than remembered at every caller.
String? _nextLinked(HttpAnswer answer, String host) {
  final String? link = _header(answer, 'link');
  if (link == null || !link.contains('rel="next"')) {
    return null;
  }
  final RegExpMatch? match = RegExp('<([^>]+)>').firstMatch(link);
  final String? target = match?[1]?.replaceAll('\r', '');
  if (target == null) {
    return null;
  }
  return target.startsWith('/') ? 'https://$host$target' : target;
}

String? _header(HttpAnswer answer, String name) {
  for (final MapEntry<String, String> header in answer.headers.entries) {
    if (header.key.toLowerCase() == name) {
      return header.value;
    }
  }
  return null;
}

final class _Json {
  const _Json(this.body, this.whyNot);

  final Object? body;
  final String? whyNot;
}

Future<_Json> _json(
  Http http,
  String url, {
  required Duration timeout,
  Map<String, String> headers = const <String, String>{},
}) async {
  final HttpAnswer answer;
  try {
    answer = await http.send(HttpRequest('GET', url, timeout: timeout, headers: headers));
  } on Object catch (failure) {
    return _Json(null, '$url could not be asked — $failure');
  }
  if (!answer.ok) {
    return _Json(null, '$url answered ${answer.status}');
  }
  final Object? body = _decoded(answer.body);
  if (body == null) {
    return _Json(null, '$url answered something that is not a document');
  }
  return _Json(body, null);
}

Object? _decoded(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}
