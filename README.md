# kindorg-hq/ci

The golden path from a pull request to Production (the home cluster), shared
by every service of kindorg-hq. A service calls one workflow,
`golden-path.yml@v3`; a merge to its default branch that carries a Releasable
change becomes a Release and is delivered. Terms: [CONTEXT.md](CONTEXT.md).
Conventions for changing a repo: [AGENTS.md](AGENTS.md).

## PR → Production

Every line names the job as it appears in the checks list of a service whose
pipeline job is `golden-path` and whose image is `pepic`; the file it runs in is
on the line above each group.

```
pull request   golden-path.yml → pull-request.yml: the Checks, nothing published
  golden-path / pull-request / Build: image (pepic)
      Dockerfile `test` stage (if any), then the image, loaded locally
  golden-path / pull-request / Accept: image scan (pepic)
      Trivy: CRITICAL with a fix fails
  golden-path / pull-request / Accept: PR title names its change and work item
  golden-path / pull-request / Accept: no secrets in the change           gitleaks
  golden-path / pull-request / Accept: no vulnerable dependencies added   public repos only
        │ squash-merge: the decision to ship
        ▼
push to the    golden-path.yml → build.yml
default branch
  golden-path / build / Build: artifact (pepic)
      `test` stage again, then the Artifact pushed as ghcr.io/<owner>/pepic:<commit-sha>
  golden-path / build / Accept: artifact scan (pepic)
        │
        ▼      golden-path.yml → release-and-deliver.yml, one at a time per service repo
  golden-path / deliver / Deliver: cut release
      git-cliff: a Releasable change since the last vX.Y.Z? tag this commit vX.Y.Z and
      create the GitHub Release. None: stop here, it ships with the next Release.
        │
        ▼      release-and-deliver.yml → deliver.yml
  golden-path / deliver / deliver / Deliver: promote and re-scan (pepic)
      :<commit-sha> → :X.Y.Z on the same digest (nothing rebuilt), Trivy again
  golden-path / deliver / deliver / Deliver: record pepic X.Y.Z in homelab-k8s
      GitOps PR: no downgrade, pin by digest, label the version, release commit on
      the Application (kindorg.dev annotations), wait for checks, merge
  golden-path / deliver / deliver / Deliver: report on the PRs in X.Y.Z
      PRs: `released` label + "recorded" comment; `production` deployment in_progress
        │
        ▼      homelab-k8s, not this repo
  ArgoCD syncs → comment "running" / "degraded", deployment success / failure (as the
  kindorg-argocd App) → Telegram

workflow_dispatch (re-deliver the latest Release; no Build, nothing rebuilt):
  golden-path / deliver / Deliver: find the latest release
      then the same three deliver / Deliver jobs as above
```

Stages are named Build, Accept, Deliver in every job, so everyone reads a
pipeline the same way (Integrate and Rehearse have no environments here yet).

**Build once, promote.** The image that reaches Production is byte for byte
the Artifact built and scanned on merge. A Release only adds a tag to its digest
(`crane tag`; the digest is checked unchanged).

## Files

| File | What it does |
| --- | --- |
| `.github/workflows/golden-path.yml` | The entry a service calls. Picks the path from the event: `pull_request` → `pull-request.yml`; push to the default branch → `build.yml`, then `release-and-deliver.yml` in the concurrency group `golden-path-deliver-<owner/repo>`; `workflow_dispatch` → `release-and-deliver.yml` only. Calls its stages with `$/` (this repo at the commit being run). |
| `.github/workflows/pull-request.yml` | The Checks: image build (with the `test` stage) and scan, PR title, gitleaks, dependency review. Publishes nothing. |
| `.github/workflows/build.yml` | Build and Accept of the Artifact on merge: push `:<commit-sha>` to ghcr, scan the pushed image. |
| `.github/workflows/release-and-deliver.yml` | The Deliver stage as one unit: `Deliver: cut release` (push) or `Deliver: find the latest release` (workflow_dispatch), then `deliver.yml`. Not called by services directly. |
| `.github/workflows/deliver.yml` | Deliver a Release without building: promote and re-scan each image, record it in homelab-k8s, report on the PRs. |
| `.github/workflows/release.yml` | release-please. In v3 only `release.self.yml` uses it, for this repo's own releases; services no longer do (callers on `@v2` read the v2 tag's copy). |
| `.github/workflows/self-test.yml` | This repo's PR checks: the Checks and `golden-path.yml` against `fixtures/hello` with the PR's own actions, the artifact path with a dry-run Release and promotion, the report dry run, the no-downgrade cases, the Application annotation cases, actionlint. |
| `.github/workflows/release.self.yml` | This repo's release on push to main: self-test, then release-please, then the major tag (never `v2`). |
| `actions/build-image` | Build one image with buildx for linux/arm64; builds the Dockerfile's `test` stage first when it has one. On PRs loads it locally; on merge pushes `:<commit-sha>`. |
| `actions/scan-image` | Trivy as a pinned container; fails on the given severity (CRITICAL) with a fix available. |
| `actions/cut-release` | git-cliff (`cliff.toml`): next version and notes from the Conventional Commits since the last `vX.Y.Z` tag; tags this commit and creates the GitHub Release only on a Releasable change. `dry-run` tags nothing. |
| `actions/promote-image` | Add the version tag to the Artifact of a commit with crane; fails if the digest changed. |
| `actions/gitops-pr` | Open, wait for and merge the PR to `manifests/<app>/base` and `apps/<app>.yaml` in homelab-k8s: digests pinned, `app.kubernetes.io/version` label, the Release on the Application (`annotate-app.sh`, cases in `annotate-app.test.sh`). Refuses a lower version first (`no-downgrade.sh`, cases in `no-downgrade.test.sh`). |
| `actions/report-delivery` | `released` label and one "recorded" comment on every PR of the Release; `production` deployment of the release commit, `in_progress`. |
| `fixtures/hello` | The smallest service (with a `test` stage) that self-test runs the path on. |
| `fixtures/gitops` | A GitOps repo stand-in for the no-downgrade and annotation cases. |
| `release-please-config.json`, `.release-please-manifest.json`, `CHANGELOG.md` | This repo's release-please state. |

## Connect a service

`.github/workflows/pipeline.yml` in the service:

```yaml
name: pipeline
on:
  pull_request:
  push:
    branches: [main]        # the default branch
  workflow_dispatch:        # re-deliver the latest Release

jobs:
  golden-path:
    uses: kindorg-hq/ci/.github/workflows/golden-path.yml@v3
    permissions: {contents: read, packages: write, pull-requests: write, deployments: write}
    with:
      app: pepic                         # dir under homelab-k8s/manifests/
      images: '[{"name": "pepic"}]'      # context ".", dockerfile "Dockerfile"
      url: https://pepic.example.com     # where the service answers
    secrets: inherit
```

Keep the job id `golden-path`: it is the first part of every check name.
Optional inputs: `runner` (default `ubuntu-24.04-arm`), `trivy-severity`
(`CRITICAL`), `require-issue` (`true`: the PR title's scope must be `#N`),
`ci-ref` (`v3`). Each entry of `images` may set `context` and `dockerfile`.

Before the first merge:

- **The kindorg-ci GitHub App is installed** on the service repo (it tags the
  Release) and on homelab-k8s (it opens and merges the GitOps PR). The repo
  sees the org variable `KINDORG_CI_APP_ID` and the org secret
  `KINDORG_CI_APP_KEY`; `secrets: inherit` passes the secret on.
- **homelab-k8s has `manifests/<app>/base/kustomization.yaml`** naming the
  images as `ghcr.io/<owner>/<name>`, and **`apps/<app>.yaml`**, the
  Application named `<app>` (the GitOps PR annotates it; without it Deliver
  fails before opening the PR).
- **The ghcr package lets the repo write**: a new package is created by the
  first push; an existing one must give the repo's Actions write access.
- **Merge settings**: squash only, PR title as the commit message. The title
  is `type(#N): summary` (see [AGENTS.md](AGENTS.md)); git-cliff reads it.
- **Tests, optional**: a stage `FROM … AS test` in the Dockerfile. Build runs
  it before the image, on every PR and every merge, for linux/arm64; a failure
  fails Build. Keep the image as the last stage. Without a `test` stage the
  run summary says the service has no tests.
- **Ruleset** (public repos; on the free plan private ones cannot require
  checks): require
  - `golden-path / pull-request / Build: image (<name>)` and
    `golden-path / pull-request / Accept: image scan (<name>)` for each image,
  - `golden-path / pull-request / Accept: PR title names its change and work item`,
  - `golden-path / pull-request / Accept: no secrets in the change`,
  - `golden-path / pull-request / Accept: no vulnerable dependencies added`.

Dependabot PRs (label `dependencies`) skip the title check, and get no
secrets, which the PR path does not need.

## Migrating from v2

1. **Pipeline file**: replace the `pull-request`, `build`, `release` and
   `deliver` jobs (and any `latest` job of your own) with the one
   `golden-path` call above. Add `workflow_dispatch`; set `push.branches` to
   the default branch.
2. **Permissions**: the call needs `contents: read, packages: write,
   pull-requests: write, deployments: write`; v2's deliver had only the first
   two.
3. **Tests in the Dockerfile**: move them into a `test` stage and delete the
   separate test workflow (and its required check).
4. **No release PR**: the merge is the Release. Delete
   `release-please-config.json` and `.release-please-manifest.json`, close an
   open release PR. The next version counts from the last `vX.Y.Z` tag,
   release-please's tags included.
5. **Freeze `CHANGELOG.md`**: leave it as it is and end it with a line that
   later releases are in GitHub Releases.
6. **Dependabot**: runtime dependencies (Go modules, npm, …) with
   `commit-message: {prefix: "fix(deps)"}` so they ship; GitHub Actions and
   the Docker base image `chore(deps)`.
7. **Ruleset**: replace the v2 names (`pull-request / …`, `checks / …`, the
   test workflow's) with the `golden-path / pull-request / …` names above.
8. **First delivery**: `gh workflow run pipeline.yml` re-delivers the latest
   Release. Promotion needs the Artifact tagged with that Release's commit SHA
   in ghcr (v2's `build.yml` pushed it; v1 did not). Without one, the next
   Releasable merge is the first delivery.

## Rules

- **A merge to the default branch ships.** A merge that carries a Releasable
  change (`feat`, `fix`, `perf`, breaking) becomes a Release once its Artifact
  passes Accept, and is delivered. Other merges are built and accepted and
  ship with the next Release.
- **Delivery is visible on the PR.** Once the GitOps PR merges, the Release is
  recorded: every PR in it (the PRs of its commits since the previous Release)
  gets the `released` label and one comment "vX.Y.Z recorded" linking the
  GitHub Release and the GitOps PR, and the release commit gets a GitHub
  Deployment to `production` in state `in_progress`. That is where the
  pipeline stops. **Recorded → running is ArgoCD's**, not this repo's: when
  the app is synced, healthy and runs the Release's images, ArgoCD
  Notifications (as the `kindorg-argocd` GitHub App) edit that comment on the
  release commit's PR into "running" and set the deployment to `success`; on
  Degraded, "degraded" and `failure`. The `production` deployment is the
  source of truth; recorded is not delivered. A re-delivery edits the comment,
  never adds one. Configuration, the App and its key:
  [homelab-k8s README, Notifications](https://github.com/kindorg-hq/homelab-k8s#notifications-telegram-and-github).
- **The comment tag is shared with homelab-k8s.** The comment carries
  `<!-- argocd-notifications delivery -->`: ArgoCD Notifications'
  `pullRequestComment` with `commentTag: delivery` finds it by that marker and
  edits it in place; it finds the deployment by the release commit's full SHA
  (`ref`) and `environment: production`. Change one side, change both.
- **The Release is written on the Application.** ArgoCD knows the GitOps
  commit, not the service's. So the GitOps PR also annotates
  `apps/<app>.yaml` in homelab-k8s (its app-of-apps syncs it):
  `kindorg.dev/source-repo` (the service repo URL), `kindorg.dev/source-sha`
  (the release commit, full SHA), `kindorg.dev/version`, `kindorg.dev/images`
  (the pinned `ghcr.io/…@sha256:…`, space separated; ArgoCD waits until the
  pods run exactly these) and `kindorg.dev/environment-url` (the service's
  `url`). The notification templates read them; also a contract, change both
  sides together.
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

This repo does not take its own golden path: its version is a promise to
every service, so a human merges its release PR. On push to main
`release.self.yml` first runs `self-test.yml` on that commit, and
release-please runs only once it is green: it keeps a "release x.y.z" PR with
the changelog. Merging that PR tags vX.Y.Z (again after a green self-test on
the merge commit) and only then moves the major tag, so `@v3` never points at
unreleased or untested code. Every PR runs `self-test.yml` too, with the
actions from the PR itself.

`v1` (rebuilt the image at release time) and `v2` (release-please in every
service, frozen at 2.1.0; the major-tag job refuses to move it) are frozen.

## Free-plan limits

- Branch protection and required checks exist only for public repositories:
  for private repos and homelab-k8s the checks are advisory, and the GitOps
  PR is merged by the pipeline, not by GitHub's auto-merge.
- dependency-review needs Advanced Security on private repositories, so it is
  skipped there.
