#!/usr/bin/env bash
# Write the Release onto the app's ArgoCD Application in the GitOps repo, as
# annotations ArgoCD Notifications read to report "running" / "degraded" on
# GitHub (homelab-k8s README, Notifications). homelab-k8s syncs apps/ with
# its app-of-apps Application, so the annotations reach the cluster with the
# same PR that pins the images.
#
#   annotate-app.sh <apps/<app>.yaml> <app>
#
# Environment:
#   SOURCE_REPO      https://github.com/<owner>/<service>
#   SOURCE_SHA       the release commit, full SHA
#   VERSION          X.Y.Z
#   IMAGES           the pinned images, space separated: <name>@sha256:<64 hex>
#                    — exactly as the pods will run them
#   ENVIRONMENT_URL  where the service answers; optional (removed when empty)
#
# Only these five keys are touched; everything else in the file stays as it
# is. yq is a digest-pinned container. self-test runs annotate-app.test.sh.
set -euo pipefail

file=${1:?usage: annotate-app.sh <application file> <app>}
app=${2:?usage: annotate-app.sh <application file> <app>}
: "${SOURCE_REPO:?}" "${SOURCE_SHA:?}" "${VERSION:?}" "${IMAGES:?}"
ENVIRONMENT_URL=${ENVIRONMENT_URL:-}

[ -f "$file" ] || { echo "::error::no $file: the app has no ArgoCD Application in the GitOps repo"; exit 1; }
[[ $SOURCE_REPO =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "::error::bad source repo '$SOURCE_REPO'"; exit 1; }
[[ $SOURCE_SHA =~ ^[0-9a-f]{40}$ ]] || { echo "::error::source sha must be a full commit SHA, got '$SOURCE_SHA'"; exit 1; }
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::bad version '$VERSION'"; exit 1; }
for image in $IMAGES; do
  [[ $image =~ ^[a-z0-9./_-]+@sha256:[0-9a-f]{64}$ ]] || { echo "::error::image not pinned by digest: '$image'"; exit 1; }
done
[ -z "$ENVIRONMENT_URL" ] || [[ $ENVIRONMENT_URL =~ ^https?://[^[:space:]]+$ ]] || { echo "::error::bad environment url '$ENVIRONMENT_URL'"; exit 1; }

dir=$(cd "$(dirname "$file")" && pwd); base=$(basename "$file")
yq() {
  docker run --rm -i -u "$(id -u):$(id -g)" -v "$dir:/work" -w /work \
    -e SOURCE_REPO -e SOURCE_SHA -e VERSION -e IMAGES="$(echo $IMAGES)" -e ENVIRONMENT_URL \
    mikefarah/yq:4.54.1@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e "$@"
}

kind=$(yq '.kind' "$base"); name=$(yq '.metadata.name' "$base")
[ "$kind" = Application ] && [ "$name" = "$app" ] || {
  echo "::error::$file is a $kind named $name, expected the Application $app"; exit 1; }

yq -i '
  .metadata.annotations["kindorg.dev/source-repo"] = strenv(SOURCE_REPO) |
  .metadata.annotations["kindorg.dev/source-sha"] = strenv(SOURCE_SHA) |
  .metadata.annotations["kindorg.dev/version"] = strenv(VERSION) |
  .metadata.annotations["kindorg.dev/images"] = strenv(IMAGES) |
  (with(select(strenv(ENVIRONMENT_URL) != ""); .metadata.annotations["kindorg.dev/environment-url"] = strenv(ENVIRONMENT_URL))) |
  (with(select(strenv(ENVIRONMENT_URL) == ""); del(.metadata.annotations["kindorg.dev/environment-url"])))
' "$base"
echo "Annotated $file: $app $VERSION from $SOURCE_REPO@$SOURCE_SHA"
