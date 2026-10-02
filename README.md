# kindorg-hq/ci

The golden path from a pull request to the home cluster, shared by every
service of kindorg-hq. Terms: [CONTEXT.md](CONTEXT.md).

```
PR ──▶ checks.yml          title · secrets · dependencies · image builds and scans
main ─▶ release.yml        release-please keeps a "release x.y.z" PR with the changelog
        merge release PR ─▶ tag vX.Y.Z + GitHub Release
                            └▶ deliver.yml   build ▸ push ▸ scan ▸ PR to homelab-k8s
                                             (digest + version label) ▸ checks ▸ merge
                                             └▶ ArgoCD rolls it out ▸ Telegram
```

The service keeps its own tests in its own workflow; everything after "tests
are green" is here.

## Using it

`.github/workflows/pipeline.yml` in a service:

```yaml
name: pipeline
on:
  pull_request:
  push:
    branches: [main]

jobs:
  checks:
    if: github.event_name == 'pull_request'
    uses: kindorg-hq/ci/.github/workflows/checks.yml@v1
    with:
      images: '[{"name": "pepic", "context": ".", "dockerfile": "Dockerfile"}]'

  release:
    if: github.event_name == 'push'
    uses: kindorg-hq/ci/.github/workflows/release.yml@v1
    secrets: inherit

  deliver:
    needs: release
    if: needs.release.outputs.released == 'true'
    uses: kindorg-hq/ci/.github/workflows/deliver.yml@v1
    with:
      app: pepic
      version: ${{ needs.release.outputs.version }}
      ref: ${{ needs.release.outputs.tag }}
      release-url: ${{ needs.release.outputs.url }}
      images: '[{"name": "pepic", "context": ".", "dockerfile": "Dockerfile"}]'
    secrets: inherit
```

Plus, in the service repo:

- `release-please-config.json` and `.release-please-manifest.json` (start
  version; `bootstrap-sha` for forks, so the first changelog does not pull in
  the upstream history);
- merge settings: squash only, PR title as the commit message — the title is
  what release-please reads;
- the kindorg-ci GitHub App installed on it; it reads `vars.KINDORG_CI_APP_ID`
  and `secrets.KINDORG_CI_APP_KEY`.

## Rules

- **Only Releases are delivered.** A merge to main runs the Checks and updates
  the release PR; nothing reaches the cluster until that PR is merged.
- **Fix forward.** No rollback in the pipeline. Break-glass is a manual revert
  in homelab-k8s, described in its README.
- **Images are pinned by digest** in homelab-k8s and labelled
  `app.kubernetes.io/version`. Tags in ghcr can be moved; digests cannot.
- **Trivy fails on CRITICAL with a fix available.** HIGH on old base images
  would drown the signal.
- **Third-party actions are pinned by SHA** (Dependabot proposes bumps). Tools
  run as containers pinned by digest rather than third-party actions.

## Versioning of this repo

Released by release-please like a service. Merging the release PR tags vX.Y.Z
and only then moves `v1`, so `@v1` never points at unreleased code. Every PR
runs `self-test.yml`: the Checks against `fixtures/hello`, using the actions
from the PR itself, plus actionlint.

## Free-plan limits

- Branch protection and required checks exist only for public repositories:
  for jtbd-graph and homelab-k8s the checks are advisory, and the GitOps PR is
  merged by the pipeline, not by GitHub's auto-merge.
- dependency-review needs Advanced Security on private repositories, so it is
  skipped there.
