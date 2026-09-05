/// Steps that know the shapes an authentik identity provider defines for itself.
///
/// This package knows the tool and never an application of it. Which applications exist, what the
/// provider registered them as, which label it is served under and on which domain — all of that is
/// a program row's to say.
library;

export 'src/plugin.dart';
export 'src/registry.dart';
export 'src/steps/group_membership.dart';
export 'src/steps/measure_issuer_url.dart';
export 'src/steps/report_out_of_box_flow.dart';
export 'src/steps/settings_value.dart';
