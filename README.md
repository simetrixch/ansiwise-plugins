# ansiwise-plugins

Twelve packages, one per TOOL. Each declares steps for the tool it is named after and knows no
application of it — which tenant, which cluster, which file path a product decides is a program
row's to say. Nothing here produces a binary: the composition root that compiles one is
[ansiwise-cli](https://github.com/simetrixch/ansiwise-cli), and it depends on these.

## Adding a package

Make a directory named `ansiwise-<tool>` with a `pubspec.yaml` in it. That is the whole of it:

- the release finds it and bumps it with the others — `release/tool/release_packages.dart` walks
  every `ansiwise-*/` directory rather than reading a list somebody maintains;
- the gate runs its `dart test` — `.github/workflows/release.yml` walks every directory holding a
  `pubspec.yaml`;
- the tag a consumer pins already carries it, and the release page already lists it.

There is no register to add it to, in this repository or in the workflow.

## What a release is

**One tag for the whole repository**, under the grammar every release of everything is cut under:
`<major>.<minor>.<patch>-<channel>-<ts14>`, channel one of `alpha`, `beta`, `stable`. These packages
are libraries — they compile to no file and nobody downloads one — so the release attaches nothing
and the tree at the tag IS the release.

It is one tag rather than one per package because a git dependency names a REF and a PATH: one ref
serves all twelve and each consumer picks the paths it wants. One tag per package would let a
consumer hold two packages of this repository at two refs, which pub refuses to resolve —
`release/tool/release_packages.dart` carries the answer pub gave when it was asked.

## Cutting one

```
cd release
dart run tool/release.dart                        what has been released, and what could come next
dart run tool/release.dart <version> <channel>    push the tag, which starts the release
dart run tool/release.dart help                   what a release is, and what it is not
```

With no arguments it changes nothing. With a version and a channel it sets that version across every
package here, stamps the tag into every dependency one package here declares on another, commits
both, and pushes an annotated tag. The GitHub Release, its notes and the pre-release marking are the
workflow's work.

## Taking one

A consumer names the tag as the ref of a git dependency, one entry per package it wants:

```yaml
dependencies:
  ansiwise_helm:
    git:
      url: https://github.com/simetrixch/ansiwise-plugins.git
      ref: <tag>
      path: ansiwise-helm
```

Every package of this repository a consumer holds is pinned to the SAME ref. The release page of each
tag spells out the block for every package standing at it.
