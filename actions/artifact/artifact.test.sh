#!/usr/bin/env bash
# Cases for artifact.sh, the Artifact list. Runs in self-test and locally
# (needs docker):
#   actions/artifact/artifact.test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=artifact.sh
source "$here/artifact.sh"
export GITHUB_REPOSITORY_OWNER=KindOrg-HQ
failed=0
D1=sha256:$(printf 'a%.0s' {1..64})
D2=sha256:$(printf 'b%.0s' {1..64})

same() { # same <why> <want> <got>
  if [ "$2" = "$3" ]; then echo "ok   $1"; else
    echo "FAIL $1"; echo "     want: $2"; echo "     got:  $3"; failed=1; fi
}
refused() { # refused <why> <wanted words in the error> <command...>
  local why=$1 want=$2 out; shift 2
  if out=$("$@" 2>&1); then
    echo "FAIL $why: accepted"; echo "$out" | sed 's/^/     /'; failed=1
  elif [[ $out != *"$want"* ]]; then
    echo "FAIL $why: the error does not say \"$want\""; echo "$out" | sed 's/^/     /'; failed=1
  else echo "ok   $why"; fi
}

# --- the one name → address mapping ----------------------------------------
same "a name becomes ghcr.io/<owner, lowercase>/<name>" \
  "ghcr.io/kindorg-hq/pepic" "$(artifact_image pepic)"
refused "an image name is lowercase" '"Pepic" is not an image name' artifact_image Pepic

# --- the service's images input, resolved -----------------------------------
same "context and dockerfile default to . and Dockerfile" \
  "pepic	ghcr.io/kindorg-hq/pepic	.	Dockerfile
pepic-worker	ghcr.io/kindorg-hq/pepic-worker	worker	worker/Dockerfile" \
  "$(artifact_images test '[{"name":"pepic"},{"name":"pepic-worker","context":"worker","dockerfile":"worker/Dockerfile"}]')"
refused "an empty images input" "must be a non-empty JSON list" artifact_images build-image '[]'
refused "an images input that is not JSON" "images is not JSON" artifact_images build-image 'pepic'
refused "a bad entry of the input is named" 'build-image: images entry 2 {"name":"Bad"}' \
  artifact_images build-image '[{"name":"ok"},{"name":"Bad"}]'

# --- the Artifact list ------------------------------------------------------
list="[{\"name\":\"pepic\",\"image\":\"ghcr.io/kindorg-hq/pepic\",\"digest\":\"$D1\"},{\"name\":\"pepic-worker\",\"image\":\"ghcr.io/kindorg-hq/pepic-worker\",\"digest\":\"$D2\"}]"
rows=$(artifact_rows test "$list" digest)
same "a list reads as rows name, image, digest" \
  "pepic	ghcr.io/kindorg-hq/pepic	$D1
pepic-worker	ghcr.io/kindorg-hq/pepic-worker	$D2" "$rows"
same "rows make the same list again, byte for byte" "$list" "$(echo "$rows" | artifact_list)"
same "a ref is image@digest" \
  "ghcr.io/kindorg-hq/pepic@$D1
ghcr.io/kindorg-hq/pepic-worker@$D2" "$(artifact_refs test "$list")"
local_list='[{"name":"hello","image":"ghcr.io/kindorg-hq/hello","digest":""}]'
same "a local image (no digest) is referred to by its address" \
  "ghcr.io/kindorg-hq/hello" "$(artifact_refs test "$local_list")"
same "a local image's row keeps its empty digest" \
  "$local_list" "$(artifact_rows test "$local_list" | artifact_list)"

refused "a local image cannot be promoted" 'promote-image: images entry 1' \
  artifact_rows promote-image "$local_list" digest
refused "an empty list" "must be a non-empty Artifact list" artifact_rows scan-image '[]'
refused "not a list" "must be a non-empty Artifact list" artifact_rows scan-image '{"name":"x"}'
refused "an old shape (ref) is refused, the entry named" \
  "gitops-pr: images entry 1 {\"name\":\"pepic\",\"digest\":\"$D1\"}: must have exactly name, image and digest" \
  artifact_rows gitops-pr "[{\"name\":\"pepic\",\"digest\":\"$D1\"}]" digest
refused "an image with a tag" "entry 2" artifact_rows scan-image \
  "[{\"name\":\"a\",\"image\":\"ghcr.io/o/a\",\"digest\":\"$D1\"},{\"name\":\"b\",\"image\":\"ghcr.io/o/b:1.0\",\"digest\":\"$D2\"}]"
refused "a bad digest" "digest must be sha256" artifact_rows scan-image \
  '[{"name":"a","image":"ghcr.io/o/a","digest":"sha256:abc"}]'
refused "every bad entry is named" "entry 2" artifact_rows scan-image \
  '[{"name":"A","image":"ghcr.io/o/a","digest":""},{"name":"b","image":"","digest":""}]'

exit "$failed"
