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
- `scripts/check.sh` runs that same file before every push, and the release of ansiwise-cli runs it
  before it builds a binary, so there is one walk and not two;
- the product picks up the packages it wants by path, at the commit its manifest names.

There is no register to add it to.

## Judging it

```
./build.sh          analyse, format and test every package — the whole repository
```

Up to three packages run at once, each in a process of its own, because the build of the binaries of
ansiwise-cli runs it in a pod of 3 GiB; each one's output is printed whole and in directory order. Every package is run
before anything is reported, so one red package does not hide the state of the ten behind it.

`scripts/check.sh` runs this same file on the machine before every push: the push gate of the pre-push
hook runs it, and a red package refuses the push. No ci runs it anywhere else. The release of
ansiwise-cli runs the file once more before it builds anything — a red package stops a release before
a binary exists.

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
