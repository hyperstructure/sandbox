---
name: publish
description: How the sandbox image reaches ghcr.io/hyperstructure/sandbox, and how to rebuild or repair it. Covers what starts the Image workflow (fctl releases, merges, Claude Code releases, the weekly rebuild), its tags and labels, running it by hand, checking a published image with or without Docker, and what to do when a run fails or the schedule stops. Use when asked to publish, rebuild or check the image, after merging a change to it, or when an fctl release has no image.
---

# Publishing the image

The Image workflow (`.github/workflows/image.yml`) publishes
`ghcr.io/hyperstructure/sandbox` from `main` only. Its first job, "What to
build", decides whether there is anything to do and says why in the run's
summary; then each architecture builds on a runner of its own (amd64 on
`ubuntu-24.04`, arm64 on `ubuntu-24.04-arm`), is pushed by digest and
checked with `check.sh`, and the last job tags the two as one image.

## When it runs

| Trigger | Builds the newest fctl release's image when |
|---|---|
| An fctl release | as daily, for that release (fctl's Release workflow passes `-f version=…`) |
| A push to `main` that changes the image | the published one predates the change |
| Every hour (minute 23) | there is none yet (a release whose own run failed), or it predates a change |
| Every day (05:41 UTC) | as hourly, or Claude Code has a newer release, or the image is a week old |
| `gh workflow run image.yml` | as daily; `-f version=…` for another release, `-f force=true` always |
| A pull request that changes the image | always, with the latest fctl, without publishing |

Every build installs that fctl release from https://fctl.sh/releases and
the newest Claude Code (https://downloads.claude.ai), and passes both
versions to `check.sh`.

fctl's Release workflow (`.github/workflows/release.yml` in
hyperstructure/fctl) starts the run for each release as soon as the release
is on fctl.sh, as the organization's fctl-actions GitHub App, and its
Sandbox image job waits for it: a failed run fails that job, and its
summary links the run. "What to build" gives fctl.sh two minutes to show a
release, and counts one that fctl.sh's `latest`, cached for a minute,
doesn't name yet as the newest. GitHub starts the hourly run hours late at
times, so it is only the fallback.

## Tags and labels

- `<version>` (`0.4.0`): the release's image. Hosts of that version pull it.
- `<major>.<minor>` (`0.4`): moves only when the build is the newest patch
  of its minor. fctl's releases count up one patch at a time and fctl.sh
  keeps them all, so the workflow asks fctl.sh for the next patch.
- `latest`: moves only for the newest release.

The image and its index carry `org.opencontainers.image.version` (fctl's
version), `sh.fctl.claude-code.version`, `org.opencontainers.image.revision`
(the commit built) and `org.opencontainers.image.created`. The workflow reads
them back to decide whether an image is current.

## Running it by hand

It takes write access to Actions on this repository (people have it; fctl
sessions don't, so ask a person):

```sh
gh workflow run image.yml -R hyperstructure/sandbox                     # the newest release, if needed
gh workflow run image.yml -R hyperstructure/sandbox -f version=0.3.0    # another release
gh workflow run image.yml -R hyperstructure/sandbox -f force=true       # even when current
gh run list -R hyperstructure/sandbox --workflow image.yml --limit 3
gh run watch -R hyperstructure/sandbox ID --exit-status
```

## Checking what's published

With Docker:

```sh
docker buildx imagetools inspect ghcr.io/hyperstructure/sandbox:0.3.0   # linux/amd64 and linux/arm64
docker buildx imagetools inspect --raw ghcr.io/hyperstructure/sandbox:0.3.0 | jq .annotations
docker run --rm -i ghcr.io/hyperstructure/sandbox:0.3.0 sh -s < check.sh
```

Without Docker (an fctl session), from the registry's API:

```sh
token=$(curl -fsS "https://ghcr.io/token?scope=repository:hyperstructure/sandbox:pull" | jq -r .token)
curl -fsS -H "Authorization: Bearer $token" \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  https://ghcr.io/v2/hyperstructure/sandbox/manifests/latest |
  jq '{annotations, platforms: [.manifests[].platform | "\(.os)/\(.architecture)"]}'
curl -fsS -H "Authorization: Bearer $token" https://ghcr.io/v2/hyperstructure/sandbox/tags/list
```

## When something fails

Publishing happens only after both architectures passed `check.sh`, so a
failed run leaves the published tags as they were (and an untagged digest
behind, which is harmless).

- **"What to build" fails**: fctl.sh or downloads.claude.ai didn't answer
  as expected; the error says what came back. Rerun it later.
- **`check.sh` says the Claude Code version differs**: a Claude Code release
  landed between planning and building. Rerun the run.
- **`check.sh` fails otherwise, or the build does**: the image is broken,
  often by a change upstream (an installer or a package moved). Fix it in a
  pull request (the `change-the-image` skill); its own Image run shows the
  fix works.
- **The push is denied**: the package must give this repository write
  access (the package's settings → Manage Actions access). It has it when
  this workflow created the package.
- **Hosts can't pull it** ("unauthorized", "denied"): the package must be
  public. A package starts private when the workflow first creates it; a
  person makes it public in the package's settings (Danger zone → Change
  visibility), and the organization must allow public packages.
- **fctl's Sandbox image job failed**: its summary links the run it
  started here, and the items above say what to do. A fix merged to `main`
  publishes the newest release's image at once. When the job failed before
  it started a run, its token is at fault: fctl's `release` skill says what
  to do, and meanwhile
  `gh workflow run image.yml -R hyperstructure/sandbox -f version=X.Y.Z`
  builds the image.
- **The workflow stopped**: GitHub turns off scheduled workflows in a public
  repository after 60 days without activity, and emails a warning first;
  fctl's Release workflow can't start it then either. A person turns it
  back on with `gh workflow enable image.yml -R hyperstructure/sandbox`,
  then runs it by hand. Meanwhile a new fctl release has no image of its
  own, and its hosts start sessions from `latest`.

Never delete a published version that has a tag: hosts pull by tag, and a
broken one is fixed by a rebuild.
