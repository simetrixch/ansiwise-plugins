import 'package:ansiwise_core/ansiwise_core.dart';

import 'registry.dart';

/// What this plugin teaches the framework: holding a request-and-response conversation in the
/// protocol's own words.
///
/// It knows the TOOL and nothing of any interface it is pointed at. Which address answers, which
/// method and body a request carries, which field of an answer matters and which value means what
/// are all a program row's or an answer's to fill.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class HttpPlugin implements Plugin {
  /// Creates the plugin.
  const HttpPlugin();

  @override
  String get name => 'ansiwise-http';

  @override
  Registry get registry => httpRegistry;
}
