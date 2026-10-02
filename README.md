# kindorg-hq/ci

How every service of kindorg-hq gets from a pull request to Production (the
home cluster). A service calls one workflow per event — its pull request, a
merge to its default branch, a re-delivery by hand — and states what it is
(app, images, address); a merge that carries a Releasable change becomes a
Release and is delivered. Each run shows the Stages it went through (Build,
Accept, Deliver), one box each, and one summary. Terms:
[CONTEXT.md](CONTEXT.md). Conventions for changing a repo:
[AGENTS.md](AGENTS.md). Why it is shaped this way:
[PRINCIPLES.md](PRINCIPLES.md).

## A run, per event

Each box is a Stage, named as in the run's graph and the checks list of a
service whose caller job is `ci` and whose image is `pepic`; what it does is
its steps, inside the box.

**Pull request** — `pull-request.yml`, run "PR #12: feat(#7): …". Publishes
nothing.

```
┌─ ci / Build ───────────────────────────┐
│ Dockerfile `test` stage (if any),      │
│ then each image, loaded locally        │
└────────────────────────────────────────┘
                    │
                    ▼
┌─ ci / Accept ──────────────────────────┐
│ image scan (Trivy: CRITICAL with fix)  │
│ PR title names its change and work item│
│ no secrets in the change (gitleaks)    │
│ no vulnerable dependencies added       │
│   (public repos only)                  │
│ all run; the failing one is named      │
└────────────────────────────────────────┘
          squash-merge: the decision to ship
```

**Merge to the default branch** — `ship.yml`, run listed as "ship" with the
merged PR's title; its summary is headed "Ship vX.Y.Z", or "Ship <sha7>:
nothing to release".

```
┌─ ci / Build ───────────────────────────┐
│ `test` stage again, then each image    │
│ pushed as ghcr.io/<owner>/pepic:<sha>  │
│ — the Artifact                         │
└────────────────────────────────────────┘
                    │
                    ▼
┌─ ci / Accept ──────────────────────────┐
│ Trivy over the pushed images           │
└────────────────────────────────────────┘
                    │
                    ▼  one at a time per service
┌─ ci / Deliver ─────────────────────────┐
│ cut release: a Releasable change since │
│   the last vX.Y.Z? tag this commit and │
│   create the GitHub Release. None: the │
│   run ends here, green                 │
│ promote :<sha> → :X.Y.Z, same digest,  │
│   checked against what Accept scanned  │
│ re-scan                                │
│ record in homelab-k8s (GitOps PR: no   │
│   downgrade, pinned by digest, Release │
│   on the Application, checks, merge)   │
│ report on the PRs: `released` label,   │
│   "recorded" comment, `production`     │
│   deployment in_progress               │
│ summary                                │
└────────────────────────────────────────┘
                    │
                    ▼  homelab-k8s, not this repo
  ArgoCD syncs → comment "running" / "degraded", deployment
  success / failure (as the kindorg-argocd App) → Telegram
```

**Re-deliver** (by hand, `gh workflow run redeliver.yml`) — `redeliver.yml`,
run "Re-deliver the latest Release", summary "Re-deliver vX.Y.Z". Nothing is
built.

```
┌─ ci / Deliver ─────────────────────────┐
│ find the latest Release (tag, commit)  │
│ promote that commit's Artifact again   │
│   (none there: fails here)             │
│ then as in Ship: re-scan, record in    │
│   homelab-k8s, report, summary         │
└────────────────────────────────────────┘
```

Stages are named Build, Accept, Deliver in every run, so everyone reads a
pipeline the same way (Integrate and Rehearse have no environments here yet).

**Build once, promote.** The image that reaches Production is byte for byte
the Artifact built and scanned on merge. A Release only adds a tag to its digest
(`crane tag`; the digest is checked unchanged).

## Connect a service

Three files in the service's `.github/workflows/`, one per event. Keep the job
id `ci`: it is the first part of every check name.

`pull-request.yml`:

```yaml
name: pull-request
run-name: "PR #${{ github.event.pull_request.number }}: ${{ github.event.pull_request.title }}"
on:
  pull_request:

jobs:
  ci:
    uses: kindorg-hq/ci/.github/workflows/pull-request.yml@v4
    permissions: {contents: read, pull-requests: read}
    with:
      images: '[{"name": "pepic"}]'      # context ".", dockerfile "Dockerfile"
```

`ship.yml`:

```yaml
name: ship
on:
  push:
    branches: [main]        # the default branch

jobs:
  ci:
    uses: kindorg-hq/ci/.github/workflows/ship.yml@v4
    permissions: {contents: read, packages: write, pull-requests: write, deployments: write}
    with:
      app: pepic                         # dir under homelab-k8s/manifests/
      images: '[{"name": "pepic"}]'      # context ".", dockerfile "Dockerfile"
      url: https://pepic.example.com     # where the service answers
    secrets: inherit
```

No `run-name` here: it is fixed when the run starts, before the version is
known; GitHub lists the run by the merged PR's title, and the summary names
the version.

`redeliver.yml`:

```yaml
name: re-deliver
run-name: Re-deliver the latest Release
on:
  workflow_dispatch:

jobs:
  ci:
    uses: kindorg-hq/ci/.github/workflows/redeliver.yml@v4
    permissions: {contents: read, packages: write, pull-requests: write, deployments: write}
    with:
      app: pepic                         # as in ship.yml
      images: '[{"name": "pepic"}]'      # as in ship.yml; only the names count
      url: https://pepic.example.com
    secrets: inherit
```

The workflow is named `re-deliver`; `gh workflow run` takes its file:
`gh workflow run redeliver.yml`. `run-name` sits in the caller: a called workflow's own is ignored. Optional
inputs: `runner` (default `ubuntu-24.04-arm`; pull request and ship),
`trivy-severity` (`CRITICAL`), `require-issue` (pull request; `true`: the PR
title's scope must be `#N`), `ci-ref` (`v4`). Each entry of `images` may set
`context` and `dockerfile`.

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
  checks): require two checks, whatever the number of images:
  - `ci / Build` — the `test` stage and every image build;
  - `ci / Accept` — image scan, PR title, no secrets, no vulnerable
    dependencies added (skipped on private repos).

Dependabot PRs (label `dependencies`) skip the title check, and get no
secrets, which the pull request does not need.

## Migrating from v3 → v4

One PR in the service repo; everything below lands in it.

1. **Files**: delete `pipeline.yml` (the one `golden-path.yml@v3` call) and
   add the three files above. `app`, `images` and `url` stay as they were;
   the job id becomes `ci`.
2. **Push branch**: `ship.yml`'s `on.push.branches` is the repo's default
   branch — `[master]` where that is `master`. Copied as `[main]`, merges
   ship nothing.
3. **Permissions**: `pull-request.yml` needs only `contents: read,
   pull-requests: read`; `ship.yml` and `redeliver.yml` keep v3's
   `contents: read, packages: write, pull-requests: write, deployments: write`
   and `secrets: inherit`.
4. **Ruleset**: the v3 checks (`golden-path / pull-request / …`: one Build
   and one image scan per image, plus title, secrets, dependencies) never
   report again, so a ruleset still requiring them blocks every PR,
   the migration PR first. Once that PR's run shows `ci / Build` and
   `ci / Accept`, switch the required checks to those two: `GET` the
   ruleset, change only `required_status_checks`, `PUT` it back whole (a
   `PUT` without the other fields drops them):

   ```sh
   gh api repos/OWNER/REPO/rulesets                       # find the id
   gh api repos/OWNER/REPO/rulesets/ID > ruleset.json     # edit the checks
   jq '{name, target, enforcement, conditions, rules, bypass_actors}' ruleset.json \
     | gh api -X PUT repos/OWNER/REPO/rulesets/ID --input -
   ```

5. **The service's own docs**: its README and AGENTS point at v4 — links to
   `ci/blob/v4/…` (not `ci/blob/v3`), the three workflow files (not
   `pipeline.yml`), `gh workflow run redeliver.yml` to re-deliver (not
   `gh workflow run pipeline.yml`).
6. **Re-deliver**: the workflow is named `re-deliver`, its file is
   `redeliver.yml`; `gh workflow run` takes the file:
   `gh workflow run redeliver.yml`.

Nothing else moves: Releases, tags, the Artifacts in ghcr, homelab-k8s and
the PR comments carry over, and v4's Deliver queues with v3's (same
concurrency group), so the switch can land at any time. `@v3` stays frozen at
its last 3.x release.

## Migrating from v2

Move to v4 directly:

1. **Files**: replace the `pull-request`, `build`, `release` and `deliver`
   jobs (and any `latest` job of your own) with the three files above.
2. **Permissions**: Ship and re-deliver need `contents: read, packages:
   write, pull-requests: write, deployments: write`; v2's deliver had only the
   first two.
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
   test workflow's) with `ci / Build` and `ci / Accept`.
8. **First delivery**: `gh workflow run redeliver.yml` re-delivers the latest
   Release. Promotion needs the Artifact tagged with that Release's commit SHA
   in ghcr (v2's `build.yml` pushed it; v1 did not). Without one, the next
   Releasable merge is the first delivery.

## Files

| File | What it does |
| --- | --- |
| `.github/workflows/pull-request.yml` | What a service's pull request runs: `Build` (Dockerfile `test` stage, then every image, loaded locally and handed to Accept) → `Accept` (image scan, PR title, gitleaks, dependency review — each a step, all run, the failing one named; a summary of all four). Publishes nothing, needs no secrets. |
| `.github/workflows/ship.yml` | What a merge runs: `Build` (`test` stage, then every image pushed as `:<commit-sha>`) → `Accept` (Trivy over them) → `Deliver` (cut release, promote — digests checked against what Accept scanned —, re-scan, GitOps PR, report on the PRs; each a step, in the concurrency group `golden-path-deliver-<owner/repo>`). One summary, from Deliver. `dry-run` for self-test. |
| `.github/workflows/redeliver.yml` | Re-delivery, by hand (`workflow_dispatch`): one job, `Deliver` — find the latest Release, promote that commit's Artifact (nothing rebuilt; none there fails), re-scan, GitOps PR, report; in Ship's concurrency group. A version already recorded changes nothing in homelab-k8s and leaves comments and the `production` deployment as they are. From promote to report its steps are Ship's Deliver steps (self-test compares them). `dry-run` for self-test. |
| `.github/workflows/self-test.yml` | This repo's PR checks, with the PR's own actions on `fixtures/`: `pull-request.yml` as job `ci`, `ship.yml` as job `ship` (dry-run Release, promotion to a throw-away tag, report dry run), `redeliver.yml` as job `redeliver` (this repo's latest Release given a fixture Artifact, dry run), Ship's and re-delivery's Deliver steps the same, the list form of the image actions (two images in one job, one failing), the no-downgrade and Application annotation cases, actionlint. |
| `.github/workflows/release.self.yml` | This repo's release on push to main: self-test, then release-please, then the major tag (never `v2`). |
| `.github/workflows/release.yml` | release-please, for this repo's own releases (callers on `@v2` read the v2 tag's copy). |
| `actions/build-image` | Build a list of images (`images`: JSON `[{"name", "context", "dockerfile"}]`, one after the other in one step) with buildx for linux/arm64; builds each Dockerfile's `test` stage first when it has one. On PRs loads them locally; on merge pushes `:<commit-sha>`. Output `images`: `[{"name", "ref", "digest"}]`. The first failing image stops it, named. |
| `actions/scan-image` | Trivy as a pinned container over a list of images (`images`: JSON `[{"name", "ref"}]`, build-image's or promote-image's `images` output as is); scans them all, then fails on the given severity (CRITICAL) with a fix available, naming each failed image. |
| `actions/cut-release` | git-cliff (`cliff.toml`): next version and notes from the Conventional Commits since the last `vX.Y.Z` tag; tags this commit and creates the GitHub Release only on a Releasable change. `dry-run` tags nothing. |
| `actions/promote-image` | Add the version tag to the Artifact of a commit with crane, for a list of images (`images`: JSON `[{"name"}]`); fails if a digest changed, naming the image. Output `images`: `[{"name", "image", "ref", "digest"}]`. |
| `actions/gitops-pr` | Open, wait for and merge the PR to `manifests/<app>/base` and `apps/<app>.yaml` in homelab-k8s: digests pinned, `app.kubernetes.io/version` label, the Release on the Application (`annotate-app.sh`, cases in `annotate-app.test.sh`). Refuses a lower version first (`no-downgrade.sh`, cases in `no-downgrade.test.sh`). |
| `actions/report-delivery` | `released` label and one "recorded" comment on every PR of the Release; `production` deployment of the release commit, `in_progress`. |
| `actions/delivery-summary` | The one summary of a Ship or re-deliver run: version, commit, digests, Release, GitOps PR, what comes next; the failing step when one failed. The workflows set `KINDORG_CI_NOTES` to a file, and build-image, cut-release, promote-image, gitops-pr and report-delivery write their notes there instead of their own step summaries; this action folds them in, collapsed. Unset, they write step summaries. |
| `fixtures/hello` | The smallest service (with a `test` stage) that self-test runs the workflows on. |
| `fixtures/hello-worker`, `fixtures/broken` | A second image without a `test` stage, and one whose tests fail: the list form of the image actions in self-test. |
| `fixtures/gitops` | A GitOps repo stand-in for the no-downgrade and annotation cases. |
| `release-please-config.json`, `.release-please-manifest.json`, `CHANGELOG.md` | This repo's release-please state. |

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
  - *One Deliver at a time per service.* The Deliver job — cut release (or
    find the latest one) → promote → re-scan → GitOps PR → report, all one
    job — runs in the concurrency group `golden-path-deliver-<owner/repo>`,
    without cancel-in-progress; Ship's and re-delivery's share it (and v3's
    used the same name). GitHub keeps one pending run per group and drops
    older pending ones; that is accepted — the next Release includes their
    commits.
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

This repo does not ship the way its services do: its version is a promise to
every service, so a human merges its release PR. On push to main
`release.self.yml` first runs `self-test.yml` on that commit, and
release-please runs only once it is green: it keeps a "release x.y.z" PR with
the changelog. Merging that PR tags vX.Y.Z (again after a green self-test on
the merge commit) and only then moves the major tag, so `@v4` never points at
unreleased or untested code. Every PR runs `self-test.yml` too, with the
actions from the PR itself; this repo's ruleset requires its jobs, among them
`ci / Build` and `ci / Accept` as a service's would.

`v1` (rebuilt the image at release time), `v2` (release-please in every
service, frozen at 2.1.0; the major-tag job refuses to move it) and `v3` (one
`golden-path.yml` for every event; frozen at its last 3.x release, its files
live on in the tag) are frozen.

## Free-plan limits

- Branch protection and required checks exist only for public repositories:
  for private repos and homelab-k8s the checks are advisory, and the GitOps
  PR is merged by the pipeline, not by GitHub's auto-merge.
- dependency-review needs Advanced Security on private repositories, so it is
  skipped there.
