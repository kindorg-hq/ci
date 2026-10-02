# kindorg-hq/ci

How a service of kindorg-hq gets from a pull request to the home cluster.
Cluster terms (Platform, Application) are defined in homelab-k8s/CONTEXT.md.

## Language

**Stage**:
One of the named phases of a pipeline, run in order — each starts only on what the one before passed: **Build** (compile, test, package the Artifact), **Accept** (scans and checks of what was built), **Deliver** (cut the Release, promote the Artifact, record it for the cluster). Integrate and Rehearse exist in the team's model but have no environments here yet. Release is not a Stage: it is what Deliver starts with.
_Avoid_: step, phase, job (a job belongs to a Stage)

**Work item**:
The issue a change belongs to. Every change names it in the PR title's scope, `type(#N): …`, so the changelog traces each line to its issue.
_Avoid_: ticket, task

**Checks**:
What every pull request of a service must pass besides its own tests: a Conventional-Commit title, no secrets in the change, no vulnerable dependency added, the image builds and scans clean.
_Avoid_: CI (too broad — the service's own tests are CI too), gates

**Artifact**:
The image built once, on merge to the main branch, tagged with its commit SHA and scanned. Identified by its digest. Nothing after the merge rebuilds it: a Release promotes this exact artifact.
_Avoid_: build, image (an image can be rebuilt; an artifact is the one that was)

**Release**:
A version given to an accepted commit of main: a tag vX.Y.Z on that very commit and a GitHub Release with its notes. For a service every merge to main whose Artifact passed Accept becomes a Release — the merge is the decision to ship. This repo is the exception: its release PR is merged by a human, because its version is a promise to every service.
_Avoid_: deploy (that is Delivery), build

**Releasable change**:
A commit whose type is `feat`, `fix` or `perf`, or that is breaking. Only these become a Release; a merge of `chore`, `docs`, `ci` or `test` is built and accepted but ships nothing. Runtime dependency bumps are `fix(deps)`, so they ship.
_Avoid_: release-worthy, user-facing change

**Delivery**:
Getting a Release into Production without building anything: the Artifact of the release commit is promoted (the version tag added to the same digest), re-scanned, and recorded in homelab-k8s by a pull request — pinned by digest, labelled with the version. A Release is **recorded** when that PR merges, and **running** when ArgoCD reports it synced and healthy; only running counts as delivered. The pipeline marks every PR of the Release `released` and comments "recorded"; ArgoCD turns that comment on the release commit's PR into "running" (or "degraded") and sets the `production` deployment, which is the source of truth.
_Avoid_: deploy job, push to prod

**Production**:
The home cluster, as an environment: the only one there is. GitHub Deployments of a service go to `production`; the name leaves room for staging once Integrate and Rehearse get environments.
_Avoid_: cluster (as an environment name), prod

**Fix forward**:
The only way back from a bad Release is the next Release. There is no rollback in the pipeline.
_Avoid_: rollback, revert

**Break-glass**:
The documented exception to Fix forward: a manual revert in homelab-k8s when production is down and a fix cannot ship in time. Always followed by a written note of what went around the process and why.
_Avoid_: hotfix (that is just a Release)

**Golden path**:
The shared pipeline this repo provides, entered through one workflow: a service states what it is (name, images, address), the golden path decides how it gets to Production. This repo itself does not take it: its releases are cut by a human.
_Avoid_: template, standard pipeline
