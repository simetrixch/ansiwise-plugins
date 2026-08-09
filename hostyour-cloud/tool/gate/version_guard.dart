/// The pin, applied to the SDK the gate is running on.
///
/// The pinned container this replaces made the pinned SDK the only one a check could meet. On the
/// bare machine the pin is a requirement instead, and this is what enforces it: every tool the gate
/// starts is this process's own SDK — the real toolchain launches `Platform.resolvedExecutable` —
/// so reading this process's version reads the version of everything the run would use, and a
/// refusal here stops the whole run before any check can answer under a toolchain the answer is not
/// true for.
library;

/// The bare semantic version out of [platformVersion].
///
/// `Platform.version` answers the version first and the channel, the build date and the platform
/// after it — `3.12.2 (stable) (Tue Jun 9 01:11:39 2026 -0700) on "windows_x64"` — so the version
/// is everything before the first whitespace.
String dartVersionOf(String platformVersion) => platformVersion.trim().split(RegExp(r'\s')).first;

/// Why the gate must not run on this SDK, or null when it is the pinned one.
///
/// [running] is what `Platform.version` answers; [pinned] is the bare version the pin names.
String? dartVersionRefusal({required String running, required String pinned}) {
  final String found = dartVersionOf(running);
  if (found == pinned) {
    return null;
  }
  return 'this is Dart $found, and the checks of this repository are pinned to Dart $pinned — '
      'put the pinned SDK on the PATH, or raise the pin in tool/gate/pins.dart';
}
