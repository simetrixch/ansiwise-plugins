import 'package:ansiwise_checks_tree/audits.dart';

/// dependency-pins — every dependency THIS package resolves out of git names a release tag.
///
/// IT JUDGES ONE MANIFEST, this one, and the count in the test name says so. The reader walks up
/// from the working directory to the first pubspec.yaml, which from here is release/'s own — the
/// twelve plugin manifests are not among them and are not judged here.
///
/// WHICH IS THE WHOLE REASON IT STANDS HERE. The twelve are already refused a branch ref by the
/// release program itself: _bumpsFor walks every git dependency of every `ansiwise-*` manifest and
/// will not cut a tag while one of them names something no release ever produced. This manifest is
/// the one that reader does not reach, because PubspecsInRepository walks directories named
/// `ansiwise-*` and release/ is not one. So it was the single manifest of this repository that
/// could follow a branch with nothing to say so — which is what simetrixch/ansiwise-core#58 reported.
///
/// THE REASON IT MATTERS HERE IS GATE REPRODUCIBILITY, not a resolution somebody else performs.
/// Nothing depends on this package. But the tree standing at a release tag IS the release, and
/// .github/workflows/release.yml runs the gate over `*/pubspec.yaml`, release/ included — so a dev
/// dependency at `master` means re-running that gate at a tag later judges whatever master holds
/// that day, and the tag stops saying what was measured.
void main() => auditDependencyPins();
