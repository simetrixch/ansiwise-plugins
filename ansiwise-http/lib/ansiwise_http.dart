/// Steps that hold a request-and-response conversation over HTTP.
///
/// This package knows the tool and never an application of it. Which address answers, which method
/// and body a request carries, which field of an answer matters and which value means what — all
/// of that is a program row's or an answer's to say.
library;

export 'src/plugin.dart';
export 'src/registry.dart';
export 'src/steps/exchange_http_field.dart';
export 'src/steps/exchange_http_secret.dart';
export 'src/steps/http_conversation.dart';
export 'src/steps/http_exchange.dart';
export 'src/steps/read_http_field.dart';
export 'src/steps/send_http_request.dart';
export 'src/steps/wait_for_http_field.dart';
