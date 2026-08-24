/// Steps that keep one declaration of pinned component versions true everywhere: a stamp that
/// writes each pin into every file the declaration says carries it, and a report that holds each
/// pin against what its upstream has now.
///
/// This package knows the tools and never an application of them. Which components are pinned,
/// where each pin is written and where each upstream lives — all of that stands in a declaration
/// file a program row points at, and both steps read that ONE file, so the writer and the reader
/// cannot drift into disagreeing about what a component is.
library;

export 'src/declaration.dart';
export 'src/plugin.dart';
export 'src/registry.dart';
export 'src/stamping.dart';
export 'src/steps/measure_release_tag.dart';
export 'src/steps/report_version_pins_against_upstream.dart';
export 'src/steps/stamp_version_pins.dart';
export 'src/trees.dart';
export 'src/upstreams.dart';
