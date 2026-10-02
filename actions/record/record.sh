#!/usr/bin/env bash
# Record a Release in homelab-k8s: the one module that changes files there.
# It works on a checkout and pushes nothing; the GitHub part (branch, PR,
# checks, merge) is actions/gitops-pr, which calls this.
#
#   record.sh <homelab-k8s checkout> <app>
#
# Environment:
#   VERSION          X.Y.Z, the Release
#   IMAGES           the Artifact list, [{"name", "image", "digest"}], digests
#                    set (actions/artifact/artifact.sh)
#   SOURCE_SHA       the release commit, full SHA; empty: the Application is
#                    left as it is (no annotations)
#   SOURCE_REPO      https://github.com/<owner>/<service>; needed with SOURCE_SHA
#   ENVIRONMENT_URL  where the service answers; optional
#
# In order, on manifests/<app>/base and apps/<app>.yaml of the checkout:
#   1. no downgrade: a version lower than the recorded one is refused
#      (no-downgrade.sh)
#   2. pin: each image@digest of the Artifact list (kustomize edit set image)
#   3. label: app.kubernetes.io/version on resources and pod templates, never
#      on selectors (a Deployment's selector is immutable)
#   4. annotate: the Release on the Application, kindorg.dev/* (annotate-app.sh)
#   5. verify: `kustomize build` renders every image@digest. A manifest naming
#      the image otherwise (not as the Artifact list's `image`) would make the
#      pin a silent no-op — recorded, never running; it fails here, named.
#
# Out: the diff of the checkout on stdout — empty when the Release is already
# recorded (a re-delivery). The log goes to stderr. Exit non-zero: refused or
# failed, the reason as ::error::. The checkout must be a git work tree
# without changes of its own.
#
# Tools are digest-pinned containers (docker). Cases: record.test.sh
# (self-test, and locally).
set -euo pipefail

dir=${1:?usage: record.sh <homelab-k8s checkout> <app>}
app=${2:?usage: record.sh <homelab-k8s checkout> <app>}
: "${VERSION:?}" "${IMAGES:?}"
SOURCE_SHA=${SOURCE_SHA:-}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../artifact/artifact.sh
source "$here/../artifact/artifact.sh"

dir=$(cd "$dir" && pwd)
base="manifests/${app}/base"
[ -n "$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" ] || {
  echo "::error::record: $dir is not a git checkout of homelab-k8s" >&2; exit 1; }
[ -z "$(git -C "$dir" status --porcelain)" ] || {
  echo "::error::record: the checkout $dir has changes of its own; record works on a clean one" >&2; exit 1; }
[ -d "$dir/$base" ] || {
  echo "::error::record: no $base in homelab-k8s: $app has no manifests to record in (homelab-k8s README, a service's manifests)" >&2; exit 1; }

rows=$(artifact_rows record "$IMAGES" digest)
refs=()
while IFS=$'\t' read -r _ image digest; do refs+=("$(artifact_ref "$image" "$digest")"); done <<< "$rows"

# kustomize as a pinned container, the whole checkout mounted (a base may
# reach outside its directory), working in the app's base
kustomize() {
  docker run --rm -u "$(id -u):$(id -g)" -v "$dir:/work" -w "/work/$base" \
    registry.k8s.io/kustomize/kustomize:v5.8.1@sha256:899fcd3bc898160e62bcaf82932b0cb29ba38d16272353db2e7acbba82129429 "$@"
}

# 1. Never backwards: an older run that finishes after a newer one must not
# roll Production back. Equal (re-delivery) and none yet (first delivery) pass.
bash "$here/no-downgrade.sh" "$dir/$base" "$VERSION" >&2

# 2. and 3.
for ref in "${refs[@]}"; do kustomize edit set image "$ref" >&2; done
kustomize edit add label --without-selector --include-templates -f "app.kubernetes.io/version:${VERSION}" >&2

# 4. which repo and commit ArgoCD reports running on, and which images must
# run before it does — as kustomize pins them, so as the pods run them
if [ -n "$SOURCE_SHA" ]; then
  IMAGES="${refs[*]}" bash "$here/annotate-app.sh" "$dir/apps/${app}.yaml" "$app" >&2
else
  echo "No release commit: apps/${app}.yaml left as it is (ArgoCD reports to Telegram only)" >&2
fi

# 5. the record must be what runs
rendered=$(kustomize build .) || { echo "::error::record: kustomize build $base failed" >&2; exit 1; }
running=$(sed -nE "s/^[[:space:]-]*image:[[:space:]]*[\"']?([^\"'[:space:]]+).*/\1/p" <<< "$rendered" | sort -u)
missing=0
while IFS=$'\t' read -r name image digest; do
  ref=$(artifact_ref "$image" "$digest")
  if grep -qxF "$ref" <<< "$running"; then
    echo "verified: $base renders $ref" >&2
  else
    echo "::error::record: ${name}: $base does not render ${ref} — no container there names the image ${image}, so the pin changes nothing (recorded, never running). The manifests render: $(paste -sd ' ' - <<< "${running:-nothing}"). Name the container's image ${image} in homelab-k8s." >&2
    missing=1
  fi
done <<< "$rows"
[ "$missing" = 0 ] || exit 1

diff=$(git -C "$dir" diff --no-color --no-ext-diff)
if [ -z "$diff" ]; then
  echo "homelab-k8s already records ${app} ${VERSION}: no diff" >&2
else
  echo "Recorded ${app} ${VERSION} in the checkout: $(git -C "$dir" diff --shortstat)" >&2
  printf '%s\n' "$diff"
fi
