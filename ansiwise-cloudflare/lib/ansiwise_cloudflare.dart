/// Steps that publish DNS records through the Cloudflare v4 API.
///
/// This package knows the tool and never an application of it. Which zone a record lives in, which
/// names get records, which address they answer and where the API token stands — all of that is a
/// program row's or an answer's to say.
library;

export 'src/plugin.dart';
export 'src/registry.dart';
export 'src/steps/cloudflare_a_record.dart';
export 'src/steps/cloudflare_api.dart';
export 'src/steps/cloudflare_dkim_record.dart';
export 'src/steps/cloudflare_dmarc_record.dart';
export 'src/steps/cloudflare_spf_record.dart';
