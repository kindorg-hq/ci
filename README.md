# kindorg-hq/ci

The golden path from a pull request to the home cluster, shared by every
service of kindorg-hq. Terms: [CONTEXT.md](CONTEXT.md).

```
                    Build                      Accept                          Deliver
PR    pull-request  image (local)              image scan · title (#N) ·
                                               secrets · dependencies
main  build         Artifact :<commit-sha>     artifact scan
      release       release-please keeps a "release x.y.z" PR ─ merge it ─▶ tag vX.Y.Z
      deliver                                                                 promote :<sha> → :x.y.z
                                                                              (same digest), re-scan,
                                                                              GitOps PR ▸ checks ▸ merge
                                                                              ▸ PRs `released`, "recorded",
                                                                              `production` deployment
                                                                              ▸ ArgoCD ▸ Telegram
```

Stages are named Build, Accept, Deliver in every job, so everyone reads a
pipeline the same way (Integrate and Rehearse have no environments here yet).

**Build once, promote.** The image that reaches the cluster is byte for byte
the one built and scanned on merge. A release only adds a tag to its digest
(`crane tag`; the digest is checked unchanged); nothing is rebuilt.

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
  pull-request:
    if: github.event_name == 'pull_request'
    uses: kindorg-hq/ci/.github/workflows/pull-request.yml@v2
    with:
      images: '[{"name": "pepic", "context": ".", "dockerfile": "Dockerfile"}]'

  build:
    if: github.event_name == 'push'
    uses: kindorg-hq/ci/.github/workflows/build.yml@v2
    permissions: {contents: read, packages: write}
    with:
      images: '[{"name": "pepic", "context": ".", "dockerfile": "Dockerfile"}]'

  release:
    if: github.event_name == 'push'
    uses: kindorg-hq/ci/.github/workflows/release.yml@v2
    secrets: inherit

  deliver:
    needs: [build, release]
    if: needs.release.outputs.released == 'true'
    uses: kindorg-hq/ci/.github/workflows/deliver.yml@v2
    permissions: {contents: read, packages: write}
    with:
      app: pepic
      version: ${{ needs.release.outputs.version }}
      ref: ${{ needs.release.outputs.tag }}
      release-url: ${{ needs.release.outputs.url }}
      images: '[{"name": "pepic"}]'
    secrets: inherit
```

Plus, in the service repo:

- `release-please-config.json` and `.release-please-manifest.json` (start
  version; `bootstrap-sha` for forks, so the first changelog does not pull in
  the upstream history);
- merge settings: squash only, PR title as the commit message — the title is
  what release-please reads, and its scope names the work item:
  `fix(#12): …` (see [AGENTS.md](AGENTS.md));
- the kindorg-ci GitHub App installed on it; it reads `vars.KINDORG_CI_APP_ID`
  and `secrets.KINDORG_CI_APP_KEY`.

## Rules

- **Only Releases are delivered.** A merge to main runs the Checks and updates
  the release PR; nothing reaches the cluster until that PR is merged.
- **Delivery is visible on the PR.** Once the GitOps PR merges, the Release is
  recorded: every PR in it (the PRs of its commits since the previous Release)
  gets the `released` label and one comment "vX.Y.Z recorded" linking the
  GitHub Release and the GitOps PR, and the release commit gets a GitHub
  Deployment to `production` in state `in_progress`. ArgoCD then edits that
  comment on the release commit's PR into "running" or "degraded" and sets the
  deployment to `success` or `failure`. The `production` deployment is the
  source of truth; recorded is not delivered. A re-delivery edits the comment,
  never adds one.
- **The comment tag is shared with homelab-k8s.** The comment carries
  `<!-- argocd-notifications delivery -->`: ArgoCD Notifications'
  `pullRequestComment` with `commentTag: delivery` finds it by that marker and
  edits it in place; it finds the deployment by the release commit's full SHA
  (`ref`) and `environment: production`. Change one side, change both.
- **Fix forward.** No rollback in the pipeline. Break-glass is a manual revert
  in homelab-k8s, described in its README.
- **Deliveries never overtake each other.** Two quick merges must not cut the
  same version twice, and an older run must never record its version after a
  newer one — that would roll Production back. Two mechanisms:
  - *One Deliver at a time per service.* golden-path.yml calls the whole
    Deliver stage (cut release or find the latest one → promote → re-scan →
    GitOps PR → report, `release-and-deliver.yml`) from one job in the
    concurrency group `golden-path-deliver-<owner/repo>`, without
    cancel-in-progress. The group is on the calling job because it is held
    until the called workflow ends; a group on an inner job would let the next
    run in between cut and record. Re-delivery (`workflow_dispatch`) queues in
    the same group. GitHub keeps one pending run per group and drops older
    pending ones; that is accepted — the next Release includes their commits.
  - *No downgrade.* The GitOps PR (`actions/gitops-pr`) reads the
    `app.kubernetes.io/version` already recorded for the app in homelab-k8s
    and refuses a lower one, naming both versions. Equal is allowed
    (re-delivery), and so is none yet (first delivery). The rule is
    `actions/gitops-pr/no-downgrade.sh`; self-test runs its cases against
    `fixtures/gitops`. Break-glass and the guard: see homelab-k8s README.
- **Images are pinned by digest** in homelab-k8s and labelled
  `app.kubernetes.io/version`. Tags in ghcr can be moved; digests cannot.
- **Trivy fails on CRITICAL with a fix available.** HIGH on old base images
  would drown the signal.
- **Third-party actions are pinned by SHA** (Dependabot proposes bumps). Tools
  run as containers pinned by digest rather than third-party actions.

## Versioning of this repo

Released by release-please like a service; a human merges the release PR.
On push to main `release.self.yml` first runs `self-test.yml` on that commit,
and release-please runs only once it is green: a red self-test cuts no release
and moves no tag. Merging the release PR tags vX.Y.Z and only then moves the
major tag, so `@vN` never points at unreleased or untested code. Every PR runs
`self-test.yml` too: the Checks against `fixtures/hello`, using the actions
from the PR itself, plus actionlint.

`v1` is frozen: it rebuilt the image at release time. `v2` is frozen at 2.1.0;
v3 is next, and the major-tag job refuses to move `v2`.

## Free-plan limits

- Branch protection and required checks exist only for public repositories:
  for jtbd-graph and homelab-k8s the checks are advisory, and the GitOps PR is
  merged by the pipeline, not by GitHub's auto-merge.
- dependency-review needs Advanced Security on private repositories, so it is
  skipped there.
