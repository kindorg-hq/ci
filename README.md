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
│ then each image, loaded locally,       │
│ then compose tests on it (if any)      │
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
│ — the Artifact; compose tests (if any) │
│ on it, pulled by digest                │
└────────────────────────────────────────┘
                    │
                    ▼
┌─ ci / Accept ──────────────────────────┐
│ Trivy over the pushed images — the     │
│ scan of record (the summary links it)  │
└────────────────────────────────────────┘
                    │
                    ▼  one at a time per service
┌─ ci / Deliver ─────────────────────────┐
│ cut release: a Releasable change since │
│   the last vX.Y.Z? tag this commit and │
│   create the GitHub Release. None: the │
│   run ends here, green                 │
│ deliver (actions/deliver, one step):   │
│ ┌────────────────────────────────────┐ │
│ │ promote :<sha> → :X.Y.Z, same      │ │
│ │   digest, checked against what     │ │
│ │   Accept scanned                   │ │
│ │ no re-scan: the same digest Accept │ │
│ │   just scanned                     │ │
│ │ record in homelab-k8s (GitOps PR:  │ │
│ │   no downgrade, pinned by digest,  │ │
│ │   Release on the Application,      │ │
│ │   verified to run every            │ │
│ │   image@digest, checks, merge)     │ │
│ │ report on the PRs: `released`      │ │
│ │   label, "recorded" comment,       │ │
│ │   `production` deployment          │ │
│ └────────────────────────────────────┘ │
│ summary (names the part that failed)   │
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
│ deliver (actions/deliver, as in Ship): │
│   that commit's Artifact found in ghcr │
│   (none there: fails here), promoted   │
│   again, re-scanned, recorded,         │
│   reported                             │
│ summary                                │
└────────────────────────────────────────┘
```

**Delivery is one module**, `actions/deliver`: Ship and re-delivery differ
only in how they get the Release (cut it / the latest) and where its Artifact
comes from (Build's list / found for the release commit). Inside, in order:
find the Artifact (when none is given) → promote → the promoted list is the
one given or found → re-scan (when `rescan`) → record (`gitops-pr`) → report.
It stops at the first part that fails and says which (`failed-at`, e.g.
"record in homelab-k8s") and how it ended (`outcome`: `recorded`,
`already-recorded`, `dry-run`, `failed`); the summary is headed with that part.

**Re-scan only when time has passed since Accept.** In Ship the merge is the
Release: Deliver promotes the digest Accept scanned moments before with the
same Trivy database, so a second scan adds no evidence (`rescan: false`); the
promoted = accepted check ties what is delivered to what was scanned, and the
summary links the Accept job as the scan of record. Re-delivery delivers an
older Release, so it re-scans the promoted images (new CVEs since its Accept
fail it there).

Stages are named Build, Accept, Deliver in every run, so everyone reads a
pipeline the same way (Integrate and Rehearse have no environments here yet).

**Build once, promote.** The image that reaches Production is byte for byte
the Artifact built and scanned on merge. A Release only adds a tag to its digest
(`crane tag`; the digest is checked unchanged).

**The Artifact list** carries the images from Build to the GitOps record, one
shape throughout: `[{"name", "image", "digest"}]`, where `image` is the full
address without tag (`ghcr.io/<owner>/<name>`) and a ref is `image@digest`
(on a pull request, nothing pushed: no digest, the image loaded locally under
its address). It is made once — by Build from the service's `images`, and on
re-delivery by `find-artifact` from the release commit — and only read
afterwards: promote adds the version tag and returns it unchanged, the
accepted = promoted check compares two lists as strings, scan, the digest pin
and the Application annotations read `image` and `digest` from it. The shape,
the one place a name becomes an address and the one check of the list (a
malformed one fails naming the entry) live in `actions/artifact/artifact.sh`.

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
inputs: `test-compose` (pull request and ship; see "Tests that need a
database" below), `runner` (default `ubuntu-24.04-arm`; pull request and ship),
`trivy-severity` (`CRITICAL`), `require-issue` (pull request; `true`: the PR
title's scope must be `#N`), `ci-ref` (`v4`). Each entry of `images` may set
`context` and `dockerfile`.

Before the first merge:

- **The kindorg-ci GitHub App is installed** on the service repo (it tags the
  Release) and on homelab-k8s (it opens and merges the GitOps PR). The repo
  sees the org variable `KINDORG_CI_CLIENT_ID` (the App's client id) and the
  org secret `KINDORG_CI_APP_KEY`; `secrets: inherit` passes the secret on.
  (`KINDORG_CI_APP_ID`, the numeric id, is only read by frozen `@v3` and
  earlier callers; the actions still take `app-id`, deprecated, for them.)
- **homelab-k8s has `manifests/<app>/base/kustomization.yaml`** whose
  containers name each image exactly `ghcr.io/<owner>/<name>` (a tag is fine,
  the pin replaces it), and **`apps/<app>.yaml`**, the Application named
  `<app>` (the GitOps PR annotates it). Either missing, or an image named
  otherwise, fails Deliver at "record in homelab-k8s", naming it, before any
  PR (homelab-k8s README, "A service's manifests").
- **The ghcr package lets the repo write**: a new package is created by the
  first push; an existing one must give the repo's Actions write access.
- **Merge settings**: squash only, PR title as the commit message. The title
  is `type(#N): summary` (see [AGENTS.md](AGENTS.md)); git-cliff reads it.
- **Tests, optional**: a stage `FROM … AS test` in the Dockerfile. Build runs
  it before the image, on every PR and every merge, for linux/arm64; a failure
  fails Build. Keep the image as the last stage. Without a `test` stage the
  run summary says the service has no tests. Tests that need a database:
  `test-compose`, below.
- **Ruleset** (public repos; on the free plan private ones cannot require
  checks): require two checks, whatever the number of images:
  - `ci / Build` — the `test` stage, every image build, the compose tests;
  - `ci / Accept` — image scan, PR title, no secrets, no vulnerable
    dependencies added (skipped on private repos).

Dependabot PRs (label `dependencies`) skip the title check, and get no
secrets, which the pull request does not need.

### Tests that need a database

A `test` stage runs inside `docker build`: no Postgres next to it. Tests that
need one run from a compose file in the service's repo, given as
`test-compose` to **both** `pull-request.yml` and `ship.yml` (the same
value):

```yaml
    with:
      images: '[{"name": "the-blog"}]'
      test-compose: compose.test.yml
```

After Build has built the images, it runs that file's service **`test`**
(`docker compose run --rm -T test`: its `depends_on` started first, a
`condition: service_healthy` waited for) against **those images**, and its
exit code decides: non-zero fails `ci / Build`, so nothing after it runs (no
Accept, no Release). The contract:

- **`IMAGE_<NAME>`** per image of `images`: the name upper-cased, `-` and `.`
  as `_` (`the-blog` → `IMAGE_THE_BLOG`, `jtbd-web` → `IMAGE_JTBD_WEB`). On a
  pull request it is the image loaded locally,
  `ghcr.io/<owner>/<name>`; on a merge `ghcr.io/<owner>/<name>@sha256:…`,
  pulled by digest — the very image Accept scans and Deliver promotes.
  Nothing is rebuilt; write `${IMAGE_<NAME>:?}` so a typo fails loudly.
- **A service `test`**: what runs. Everything else in the file (the
  database) is started for it. Use images that are multi-arch (the official
  `postgres` is): Build runs on arm64.
- **No `build:` for the image under test.** An image lacking its test tools
  (a production image without pytest) can get a test image built
  `FROM ${IMAGE_<NAME>}` with only the tools added — the code tested is
  still the built one. Build notes it, as a notice, when no service runs an
  image as is.
- No ports, volumes from the host or `.env` needed: the services reach each
  other by name, and the run is removed afterwards with its volumes.

On a failure the summary shows the last 80 lines of the `test` service's
output (the failing test); the log has all of it and the other services'
logs. On success it says "Compose tests passed" with the refs tested.

`compose.test.yml` for a Django service with Postgres:

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: app_test
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 2s
      retries: 30
  test:
    image: ${IMAGE_THE_BLOG:?set by ci}
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: app_test
    depends_on:
      postgres:
        condition: service_healthy
    command: ["sh", "-c", "python manage.py migrate --noinput && python -m pytest --tb=short -q"]
```

When the production image has no test tools, in place of `image:`:

```yaml
  test:
    build:
      dockerfile_inline: |
        FROM ${IMAGE_JTBD_WEB:?set by ci}
        RUN pip install --no-cache-dir -r requirements/test.txt
```

## How Build caches

Build reuses layers through one cache, **`ghcr.io/<owner>/<name>:buildcache`**
(every stage, `mode=max`): written by a merge's Build, read by every Build —
the next merge and every pull request. PRs read it anonymously, so the
package must be public (private: the import logs an error, the build goes on
uncached). There is no GitHub Actions cache: GitHub keeps it per ref, so what
a PR wrote was never read by its merge or by another PR, and writing it cost
a PR more time than its next push saved.

**The trust rule: what a merge's Build reads, only merges write.** A pull
request controls its own caller workflow, so it must never write a cache the
default branch consumes. build-image writes the cache only on a push to the
default branch with `push: "true"`, decided from the run's event and ref
(`github.event_name`, `github.ref` — not an input a PR could set); every
other build only reads. `pull-request.yml` grants no `packages: write`, and
PRs from forks never get it; self-test checks that build-image pushing from
a PR writes no cache.

**What a merge reuses** is everything before the first changed input:
base image, system packages, downloaded dependencies — and compiled
dependencies, if the Dockerfile keeps them in a layer. The code itself
changed, so its compile and the tests run again (they should: the merge is a
new commit). To benefit:

- **Order stages by how often they change**: system packages, then the
  dependency manifest (`go.mod`/`go.sum`, `package-lock.json`, …) and its
  download, then the code (`COPY . .`), then tests and the build.
- **Compile dependencies in their own layer, before the code**: a stage
  lists what the code imports, only the list is copied on, and a `RUN`
  compiles it into the language's build cache in that layer — rebuilt only
  when the list or lock file changes. `fixtures/hello-go/Dockerfile` does it
  for Go (`go list -deps` → `go build`).
- **Build the binary from the stage that has that layer**, without forcing a
  full rebuild (no `go build -a`): it compiles only the service's own code.
- **A `.dockerignore` with `.git`**: the checkout's `.git` differs on every
  run (merge ref, index), so `COPY . .` would never match a cached layer, and
  `.git` would end up in images that copy the whole context.
- **Cache mounts** (`RUN --mount=type=cache,…`) help only within one Build
  (the test stage, then the image, on the same runner): they are not in
  the cache, so the next run starts them empty. Keep what must last
  across runs in layers.

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
| `.github/workflows/pull-request.yml` | What a service's pull request runs: `Build` (Dockerfile `test` stage, then every image, loaded locally, then the compose tests (`test-compose`) on them, and handed to Accept as the run artifact `pr-images`, a `docker save` of tens of MB kept 1 day) → `Accept` (image scan, PR title, gitleaks, dependency review through GitHub's dependency-graph compare API — each a step, all run, the failing one named). One summary, from Accept: the four checks, then Build's and the dependency step's notes, collapsed; Build writes it instead when Build fails. Publishes nothing, needs no secrets. |
| `.github/workflows/ship.yml` | What a merge runs: `Build` (`test` stage, then every image pushed as `:<commit-sha>`, then the compose tests on them by digest) → `Accept` (Trivy over them) → `Deliver` (cut release, then `actions/deliver` on Build's Artifact list, then the summary; in the concurrency group `golden-path-deliver-<owner/repo>`). One summary, from Deliver (from Build when Build fails). `dry-run` for self-test. |
| `.github/workflows/redeliver.yml` | Re-delivery, by hand (`workflow_dispatch`): one job, `Deliver` — find the latest Release, then `actions/deliver` with no Artifact list (it finds that commit's; nothing rebuilt, none there fails), then the summary; in Ship's concurrency group. A version already recorded changes nothing in homelab-k8s and leaves comments and the `production` deployment as they are. `dry-run` for self-test. |
| `.github/workflows/self-test.yml` | This repo's PR checks, with the PR's own actions on `fixtures/`: `pull-request.yml` as job `ci`, `ship.yml` as job `ship` (dry-run Release, promotion to a throw-away tag, recorded in a copy of `fixtures/gitops`, report dry run), `redeliver.yml` as job `redeliver` (this repo's latest Release given a fixture Artifact, dry run), `actions/deliver` called directly (job `deliver`: a dry-run delivery with its diff checked, a downgrade failing "at record", a missing Artifact failing "at find"), the recording cases (`record.test.sh`) and a dry-run record of pepic in the real homelab-k8s (no diff expected), the list form of the image actions (two images in one job, one failing; found again by commit), the compose tests (one passing, one failing), the Artifact list cases, the no-downgrade and Application annotation cases, actionlint. |
| `.github/workflows/release.self.yml` | This repo's release on push to main: self-test, then release-please, then the major tag (never `v2`). |
| `.github/workflows/release.yml` | release-please, for this repo's own releases (callers on `@v2` read the v2 tag's copy). |
| `actions/artifact/artifact.sh` | The Artifact list `[{"name", "image", "digest"}]`: its shape, the one name → address mapping, its check (the offending entry named), refs. Sourced by the actions below and the workflows; cases in `artifact.test.sh`. |
| `actions/build-image` | Build a list of images (`images`: JSON `[{"name", "context", "dockerfile"}]`, one after the other in one step) with buildx for linux/arm64; builds each Dockerfile's `test` stage first when it has one. On PRs loads them locally; on merge pushes `:<commit-sha>`. Reads the ghcr cache `:buildcache`; only a merge writes it (see "How Build caches"). Output `images`: the Artifact list. The first failing image stops it, named. |
| `actions/test-compose` | A service's compose tests (`test-compose`): each image of an Artifact list as `IMAGE_<NAME>` (its ref), the compose file's service `test` run with its dependencies, its exit code the result; on a failure the last lines of its output go to the notes (the run's summary). Removes what it started. |
| `actions/find-artifact` | Re-delivery's Artifact list: for the service's `images` and a commit, the digest each `<image>:<commit-sha>` holds in ghcr; none fails, named. |
| `actions/scan-image` | Trivy as a pinned container over an Artifact list (build-image's, find-artifact's or promote-image's `images` output as is); scans them all, then fails on the given severity (CRITICAL) with a fix available, naming each failed image. |
| `actions/cut-release` | git-cliff (`cliff.toml`): next version and notes from the Conventional Commits since the last `vX.Y.Z` tag; tags this commit and creates the GitHub Release only on a Releasable change, as the kindorg-ci App (`client-id`, `private-key`). `dry-run` tags nothing and needs no App. |
| `actions/deliver` | Delivery of one Release, the module Ship and re-delivery share. In: the Release (`version`, `tag`, `sha`, `release-url`; `ref` for the report, default the tag), the Artifact list (`artifact`; empty: found for `sha` from `images`), `app`, `environment-url`, `trivy-severity`, `dry-run`, `client-id`/`private-key`, `token`. Runs find-artifact (when no list) → promote-image → promoted = given → scan-image → gitops-pr → report-delivery. Out: `outcome` (`recorded`, `already-recorded`, `dry-run`, `failed`), `failed-at` (the part, in words), `images`, `gitops-pr`, `diff`. Its parts are the actions of the ci checkout at `.kindorg-ci`. `dry-run`: a throw-away tag, recorded in a git copy of `fixtures/gitops` (app `hello-dry-run`), the report as a dry run. |
| `actions/promote-image` | Add the version tag to each `image@digest` of an Artifact list with crane; fails if a digest changed, naming the image. Output `images`: the list as read back, the same as its input. |
| `actions/record/record.sh` | Recording a Release in homelab-k8s, on a checkout, files only: `record.sh <checkout> <app>` with `VERSION`, `IMAGES` (the Artifact list), `SOURCE_SHA`, `SOURCE_REPO`, `ENVIRONMENT_URL` → no downgrade (`no-downgrade.sh`), each `image@digest` pinned, `app.kubernetes.io/version` label, the Release on the Application (`annotate-app.sh`), then verified: `kustomize build` must render every `image@digest`. Prints the diff (empty: already recorded); pushes nothing. Cases in `record.test.sh`, `no-downgrade.test.sh`, `annotate-app.test.sh`. |
| `actions/gitops-pr` | The GitHub adapter around `record.sh`: an App token for homelab-k8s, the checkout, the recording, then branch, PR (an open one of an earlier attempt reused), the manifest checks waited for (REST check-runs), merge. Outputs `changed`, `diff`, `pr-url`. `dry-run`: a read-only token and checkout, the diff in the summary, nothing pushed; or, with `checkout`, a GitOps tree it is given (no token, no clone). |
| `actions/report-delivery` | `released` label and one "recorded" comment on every PR of the Release; `production` deployment of the release commit, `in_progress`. |
| `actions/delivery-summary` | The one summary of a Ship or re-deliver run, from deliver's `outcome`: version, commit, digests, Release, GitOps PR, what comes next; the failing step, or deliver's `failed-at`, when one failed. The workflows set `KINDORG_CI_NOTES` to a file, and build-image, cut-release, find-artifact, promote-image, gitops-pr and report-delivery write their notes there instead of their own step summaries; this action folds them in, collapsed. Unset, they write step summaries. |
| `fixtures/hello` | The smallest service (with a `test` stage) that self-test runs the workflows on. |
| `fixtures/hello-go` | A Go service laid out for the Build cache (dependencies compiled in their own layer): self-test writes its ghcr cache as a merge would, then builds changed code as a PR and checks the dependencies were not compiled again. |
| `fixtures/hello-worker`, `fixtures/broken` | A second image without a `test` stage, and one whose tests fail: the list form of the image actions in self-test. |
| `fixtures/compose` | Compose tests with Postgres for self-test: `hello.yml` and `hello-ship.yml` (the `ci` and `ship` jobs' images as is), `pass.yml` and `fail.yml` (a test image built `FROM` the image under test; one passes, one fails with its error in the summary). |
| `fixtures/gitops` | A homelab-k8s stand-in (hello records 1.4.0; fresh, two images, nothing yet) for the recording cases. |
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
    find the latest one) → promote → re-scan (re-delivery) → GitOps PR →
    report, all one job — runs in the concurrency group
    `golden-path-deliver-<owner/repo>`, without cancel-in-progress; Ship's and re-delivery's share it (and v3's
    used the same name). GitHub keeps one pending run per group and drops
    older pending ones; that is accepted — the next Release includes their
    commits.
  - *No downgrade.* The GitOps PR (`actions/gitops-pr`) reads the
    `app.kubernetes.io/version` already recorded for the app in homelab-k8s
    and refuses a lower one, naming both versions. Equal is allowed
    (re-delivery), and so is none yet (first delivery). The rule is
    `actions/record/no-downgrade.sh`; self-test runs its cases against
    `fixtures/gitops`. Break-glass and the guard: see homelab-k8s README.
- **Images are pinned by digest** in homelab-k8s and labelled
  `app.kubernetes.io/version`. Tags in ghcr can be moved; digests cannot.
- **A record is verified before it is proposed.** Recording
  (`actions/record/record.sh`) changes only files of a homelab-k8s checkout
  — no downgrade, pin, label, annotations — and then renders the app's
  manifests (`kustomize build`): every `image@digest` of the Artifact list
  must be in them. A container naming the image otherwise would make the pin
  a silent no-op — recorded, never running, the comment stuck at "recorded";
  it fails instead, naming the image and what the manifests do render. The
  GitHub part (PR, checks, merge) is `actions/gitops-pr`, a thin adapter.
- **The dry run shows the real diff.** `gitops-pr` with `dry-run` records on
  a read-only checkout of the real homelab-k8s (an App token with
  `contents: read`, no credentials kept) and prints the diff it would
  propose; nothing is pushed. Self-test runs it for pepic, re-recording what
  homelab-k8s records, and expects no diff. Ship's and re-delivery's own dry
  runs record too, in a git copy of `fixtures/gitops` (app `hello-dry-run`,
  whose containers are the fixture images): the summary shows that diff.
- **Trivy fails on CRITICAL with a fix available.** HIGH on old base images
  would drown the signal.
- **Third-party actions are pinned by SHA** (Dependabot proposes bumps). Tools
  run as containers pinned by digest rather than third-party actions.

## Versioning of this repo

The public interface is the three workflows — `pull-request.yml`, `ship.yml`,
`redeliver.yml` — with their inputs and job names (the check names). The
`actions/` are internal to them: a service never calls one, so changing an
action's inputs or outputs is not a breaking release.

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
- A pull request's run uploads its images as the artifact `pr-images` (a
  `docker save`, ~70 MB for pepic) so Accept scans what Build built; it is
  kept 1 day, the shortest retention GitHub allows, to stay well inside the
  artifact storage quota.
