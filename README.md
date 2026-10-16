# ansiwise-plugins

Eleven packages, one per TOOL. Each declares steps for the tool it is named after and knows no
application of it — which tenant, which cluster, which file path a product decides is a program
row's to say. Nothing here produces a binary: the composition root that compiles one is
ansiwise-cli, and it depends on these.

## This repository is not released

It is a passive part of ansiwise-cli. It carries no version, cuts no tag, publishes nothing, and
builds nothing. What names it is the COMMIT the product was built from, written into ansiwise-cli's
manifest by its `release/release.sh` when a release is cut — and a commit is the stronger name
anyway, because a tag can be moved onto another tree while a commit cannot.

## Adding a package

Make a directory named `ansiwise-<tool>` with a `pubspec.yaml` in it. That is the whole of it:

- `build.sh` walks every directory holding a `pubspec.yaml` and a `test/`, so a new package is
  analysed, formatted and tested without being added to a list;
- the ci of the master, the pipeline `ansiwise-plugins-ci`, runs that same file on a push, so there is
  one walk and not two;
- the product picks up the packages it wants by path, at the commit its manifest names.

There is no register to add it to, in this repository or in the ci of the master.

## Judging it

```
./build.sh          analyse, format and test every package — the whole repository
```

Up to three packages run at once, each in a process of its own, because the ci of the master holds
the check to 3 GiB; each one's output is printed whole and in directory order. Every package is run
before anything is reported, so one red package does not hide the state of the ten behind it.

The ci of the master is the Tekton pipeline `ansiwise-plugins-ci` (hostyour-cloud
`clusters/inventories/consumer-build/templates/pipeline-ci.yaml`). It installs the Dart that
`ci-tools.json` names and runs this same file on a push of the default branch or of a branch whose
name starts with `ci/` (the Trigger `github-ci-push`, hostyour-cloud
`clusters/inventories/image-builder/templates/triggers/github-ci-push.yaml`). Its runs are the
PipelineRuns `ansiwise-plugins-ci-*` in the namespace `ansiwise-plugins-build`, and it sets the commit
status `tekton/ci`. The release of ansiwise-cli runs the file once more before it builds anything — a
red package stops a release before a binary exists.

## Taking one

A consumer names a commit as the ref of a git dependency, one entry per package it wants:

```yaml
dependencies:
  ansiwise_helm:
    git:
      url: https://github.com/simetrixch/ansiwise-plugins.git
      ref: <commit>
      path: ansiwise-helm
```

Every package of this repository a consumer holds is pinned to the SAME ref: a git dependency names
a REF and a PATH, one ref serves all eleven, and holding two packages of one repository at two refs
is something pub refuses to resolve.
