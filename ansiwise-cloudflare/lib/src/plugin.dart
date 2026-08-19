import 'package:ansiwise_core/ansiwise_core.dart';

import 'registry.dart';

/// What this plugin teaches the framework: the shapes the Cloudflare v4 API and the public mail
/// record grammars define for themselves.
///
/// It knows the TOOL and nothing of any product whose names it publishes. Which zone, which names,
/// which address and where the token stands are all a program row's or an answer's to fill.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class CloudflarePlugin implements Plugin {
  /// Creates the plugin.
  const CloudflarePlugin();

  @override
  String get name => 'ansiwise-cloudflare';

  @override
  Registry get registry => cloudflareRegistry;
}
