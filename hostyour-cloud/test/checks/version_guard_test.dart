import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/version_guard.dart';

/// The version guard, driven with scripted versions.
///
/// The guard is what the pin IS now that no container installs it: the gate refuses to run on any
/// SDK but the pinned one, so a green run means green against one toolchain. Both directions are
/// probed — a guard that never refuses is no pin, and one that refuses the pinned SDK stops every
/// run — and the parse is held against the real `Platform.version` of the SDK running this suite,
/// for the day its shape changes.
void main() {
  const String pinned = '3.12.2';
  const String runningPinned = '3.12.2 (stable) (Tue Jun 9 01:11:39 2026 -0700) on "windows_x64"';
  const String runningOther = '3.13.0 (stable) (Mon Sep 7 10:00:00 2026 +0000) on "linux_x64"';

  test('the pinned SDK passes', () {
    expect(
      dartVersionRefusal(running: runningPinned, pinned: pinned),
      isNull,
      reason: 'a guard that refuses the pinned SDK stops every run there is',
    );
  });

  test('any other SDK is refused', () {
    expect(
      dartVersionRefusal(running: runningOther, pinned: pinned),
      isNotNull,
      reason: 'a guard that never refuses is no pin at all',
    );
  });

  test('the refusal names what was found and what was expected', () {
    final String? refusal = dartVersionRefusal(running: runningOther, pinned: pinned);
    expect(refusal, contains('3.13.0'));
    expect(
      refusal,
      contains(pinned),
      reason: 'a refusal that names only one of the two versions leaves the fix to a guess',
    );
  });

  test('the version is read out of the shape Platform.version answers', () {
    expect(dartVersionOf(runningPinned), '3.12.2');
  });

  test('what the guard reads out of this very SDK is a bare semantic version', () {
    expect(
      dartVersionOf(Platform.version),
      matches(RegExp(r'^\d+\.\d+\.\d+')),
      reason:
          'the parse takes everything before the first whitespace; if Platform.version ever '
          'changes shape, the guard would refuse every SDK including the pinned one',
    );
  });
}
