import 'package:ansiwise_core/ansiwise_core.dart';

/// Publishes the release tag this run cuts, composed from what the run was told.
///
/// **Why this is a step and not a line in a program file.** The tag is built out of parts, and a
/// program file may not build anything: the moment a file can compute, what gets debugged is the
/// file. Composing it here also puts the grammar in ONE place — a product that changes its channels
/// or its version shape changes the row that states them, and every program that cuts a release
/// follows.
///
/// **THE STAMP IS AN ANSWER AND NEVER A CLOCK READING, and that is the whole reason this step is
/// shaped the way it is.** A step that read the time would compose a different tag every time it
/// ran — and it runs in each of the three modes. What the mode that only says what would change
/// announced would then not be what the mode that changes things made, which is a plan that names
/// something that never comes into being. Reading it out of the run makes every mode compose the
/// same text, so the announcement and the act are one statement.
///
/// Whatever starts the run composes it, which is the only place that can: it happens once, before
/// any mode runs, and it is the same value for all three.
///
/// **WHICH CHANNELS EXIST IS THE PRODUCT'S, never this package's.** One product ships alpha, beta
/// and stable; the next has two, or five, or calls them something else. The row states them, and a
/// channel outside that list is refused by name rather than composed into a tag nothing downstream
/// can parse.
final class MeasureReleaseTag extends ObservingStep {
  /// Composes the tag from the answers named by [versionAnswer], [channelAnswer] and [stampAnswer].
  const MeasureReleaseTag({
    required this.versionAnswer,
    required this.channelAnswer,
    required this.stampAnswer,
    required this.channels,
  });

  /// Builds the step from what the program gave it.
  factory MeasureReleaseTag.fromArguments(Arguments arguments) => MeasureReleaseTag(
    versionAnswer: arguments.text('version_answer'),
    channelAnswer: arguments.text('channel_answer'),
    stampAnswer: arguments.text('stamp_answer'),
    channels: arguments.textList('channels'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'version_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the three numbers, as major.minor.patch. Named rather '
          'than written, because which release this is, is a fact of one run',
    ),
    ArgumentSpec(
      name: 'channel_answer',
      kind: ArgumentKind.answerName,
      describes: 'the name of the answer holding the channel this release is cut on',
    ),
    ArgumentSpec(
      name: 'stamp_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the fourteen digits of a UTC yyyyMMddHHmmss, which make '
          'two releases of one version tell each other apart. AN ANSWER AND NOT A CLOCK READING: a '
          'value read from the clock here would differ between the mode that says what would change '
          'and the mode that changes it, so the announcement would name a tag that never comes into '
          'being. Whatever starts the run composes it, once, for all three modes',
    ),
    ArgumentSpec(
      name: 'channels',
      kind: ArgumentKind.textList,
      describes:
          'every channel this product has, in the words it uses for them. A channel outside this '
          'list is refused by name rather than composed into a tag nothing downstream can parse',
    ),
  ];

  /// What this step publishes.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('release_tag'),
      describes: 'the tag this run cuts, as major.minor.patch-channel-stamp',
    ),
  ];

  /// The name of the answer holding the three numbers.
  final String versionAnswer;

  /// The name of the answer holding the channel.
  final String channelAnswer;

  /// The name of the answer holding the fourteen digits.
  final String stampAnswer;

  /// Every channel this product has.
  final List<String> channels;

  /// The three numbers, as a release states them.
  ///
  /// A leading zero is refused so that `01.02.03` cannot stand beside `1.2.3` as a second name for
  /// one release — two tags nothing can tell apart, on two different trees.
  static final RegExp _version = RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$');

  /// The fourteen digits of a UTC yyyyMMddHHmmss.
  static final RegExp _stamp = RegExp(r'^[0-9]{14}$');

  /// **Published HERE, in the check, and that is the shape a measuring step has.** The check runs in
  /// every mode, so the mode that only says what would change holds the same value the mode that
  /// changes things acts on — and a step that published only while applying would leave the first
  /// one announcing against a measurement nobody made.
  @override
  Future<CheckResult> check(StepContext context) async {
    final String? version = _answered(context, versionAnswer);
    if (version == null) {
      return CheckResult.blocked(_missing(versionAnswer, 'the three numbers of this release'));
    }
    if (!_version.hasMatch(version)) {
      return CheckResult.blocked(
        '"$versionAnswer" was answered "$version", and a release states three numbers as '
        'major.minor.patch — a leading zero among them is refused too, or 01.02.03 would stand '
        'beside 1.2.3 as a second name for one release',
      );
    }
    final String? channel = _answered(context, channelAnswer);
    if (channel == null) {
      return CheckResult.blocked(_missing(channelAnswer, 'the channel this release is cut on'));
    }
    if (!channels.contains(channel)) {
      return CheckResult.blocked(
        '"$channelAnswer" was answered "$channel", and this product has ${channels.join(', ')} — a '
        'channel outside them composes a tag nothing downstream can parse',
      );
    }
    final String? stamp = _answered(context, stampAnswer);
    if (stamp == null) {
      return CheckResult.blocked(
        _missing(stampAnswer, 'the fourteen digits that tell two releases of one version apart'),
      );
    }
    if (!_stamp.hasMatch(stamp)) {
      return CheckResult.blocked(
        '"$stampAnswer" was answered "$stamp", and what belongs there is fourteen digits of a UTC '
        'yyyyMMddHHmmss',
      );
    }

    final String tag = '$version-$channel-$stamp';
    context.measurements.publish(const MeasurementName('release_tag'), tag);
    return CheckResult.satisfied('this run cuts $tag');
  }

  /// What the run holds under [name], or null where it holds nothing there.
  String? _answered(StepContext context, String name) {
    if (!context.answers.has(name)) {
      return null;
    }
    final String held = context.answers.text(name).trim();
    return held.isEmpty ? null : held;
  }

  /// Why a missing answer stops this row, said in the words of the thing that is missing.
  String _missing(String name, String what) =>
      'this run holds no answer called "$name", and that is where this row says $what comes from';
}
