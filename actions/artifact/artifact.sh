# The Artifact list: how a service's images travel from Build to the GitOps
# record. Sourced (bash) by the actions and workflows that make or read it:
#
#   source "$GITHUB_ACTION_PATH/../artifact/artifact.sh"
#
# The list is JSON, one entry per image in the order of the service's
# `images` input:
#
#   [{"name": "pepic", "image": "ghcr.io/kindorg-hq/pepic", "digest": "sha256:<64 hex>"}]
#
#   name    the service's name for the image, as in its `images` input
#   image   the full address, without tag or digest. Made here, from the
#           name (artifact_image), and only read afterwards.
#   digest  the pushed manifest's digest; "" for an image only built
#           locally (a pull request: loaded under `image` itself)
#
# A ref is image@digest, or image alone when there is no digest
# (artifact_ref). Made once: by build-image from the service's `images`, and
# on re-delivery by find-artifact from the release commit (both through
# artifact_images). promote-image adds the version tag and returns the list
# as it took it; scan-image, the accepted = promoted check and gitops-pr (the
# pin and the Application annotations) only read it. Every reader checks the
# list with artifact_rows, which names the offending entry.
#
# Cases: artifact.test.sh (self-test, and locally with docker).

_ARTIFACT_JQ=ghcr.io/jqlang/jq:1.8.2@sha256:b9c68867e5766576263a222e91db3de422d802069c7af70440e667a95344e486
_artifact_jq() { docker run --rm -i "$_ARTIFACT_JQ" "$@"; }

# an image name, as ghcr takes it
_ARTIFACT_NAME='^[a-z0-9][a-z0-9._-]*$'

# artifact_image NAME — the full address of the service's image NAME. The
# one place a name becomes an address: ghcr.io/<owner, lowercase>/<name>.
artifact_image() {
  local name=$1 owner=${GITHUB_REPOSITORY_OWNER:?GITHUB_REPOSITORY_OWNER is not set}
  [[ $name =~ $_ARTIFACT_NAME ]] || {
    echo "::error::\"${name}\" is not an image name (lowercase letters, digits, . _ -)" >&2; return 1; }
  echo "ghcr.io/${owner,,}/${name}"
}

# artifact_ref IMAGE DIGEST — what docker, Trivy and kustomize are given
artifact_ref() { echo "${1}${2:+@$2}"; }

# Prints the problems of a list ("bad<TAB>why"), or its rows ("ok<TAB>…").
_artifact_check() { # WHO JSON [JQ ARG...] PROGRAM → rows on stdout
  local who=$1 json=$2 out line bad=0
  shift 2
  out=$(printf '%s' "$json" | _artifact_jq -r "$@" 2>/dev/null) || {
    echo "::error::${who}: images is not JSON: ${json}" >&2; return 1; }
  while IFS= read -r line; do
    case $line in
      bad$'\t'*) echo "::error::${who}: images ${line#bad$'\t'}" >&2; bad=1 ;;
    esac
  done <<< "$out"
  [ "$bad" = 0 ] || return 1
  while IFS= read -r line; do printf '%s\n' "${line#ok$'\t'}"; done <<< "$out"
}

# artifact_images WHO IMAGES — the service's `images` input
# ([{"name", "context"?, "dockerfile"?}]) checked, as rows
# "name<TAB>image<TAB>context<TAB>dockerfile" (context "." and dockerfile
# "Dockerfile" when left out). The resolver build-image and find-artifact
# start from.
artifact_images() {
  local who=$1 json=$2 rows name rest image
  rows=$(_artifact_check "$who" "$json" --arg re "$_ARTIFACT_NAME" '
    if type != "array" or length == 0 then
      "bad\tmust be a non-empty JSON list of {\"name\", \"context\", \"dockerfile\"}, got: \(tojson)"
    else to_entries[] | .key as $i | .value as $e | "entry \($i + 1) \($e | tojson)" as $at |
      if ($e | type) != "object" then "bad\t\($at): not an object"
      elif ($e.name | type) != "string" or ($e.name | test($re) | not) then
        "bad\t\($at): name must be an image name (lowercase letters, digits, . _ -)"
      elif ($e | has("context")) and (($e.context | type) != "string" or $e.context == "") then
        "bad\t\($at): context must be a path"
      elif ($e | has("dockerfile")) and (($e.dockerfile | type) != "string" or $e.dockerfile == "") then
        "bad\t\($at): dockerfile must be a path"
      else "ok\t\($e.name)\t\($e.context // ".")\t\($e.dockerfile // "Dockerfile")" end
    end') || return 1
  while IFS=$'\t' read -r name rest; do
    image=$(artifact_image "$name") || return 1
    printf '%s\t%s\t%s\n' "$name" "$image" "$rest"
  done <<< "$rows"
}

# artifact_rows WHO LIST [digest] — the Artifact list checked, as rows
# "name<TAB>image<TAB>digest". With "digest", every entry must have one (what
# is promoted, scanned in Deliver and recorded was pushed). A malformed list
# fails, each offending entry named.
artifact_rows() {
  local who=$1 json=$2 need=${3:-}
  _artifact_check "$who" "$json" --arg need "$need" '
    if type != "array" or length == 0 then
      "bad\tmust be a non-empty Artifact list [{\"name\", \"image\", \"digest\"}], got: \(tojson)"
    else to_entries[] | .key as $i | .value as $e | "entry \($i + 1) \($e | tojson)" as $at |
      if ($e | type) != "object" then "bad\t\($at): not an object"
      elif ($e | keys) != ["digest", "image", "name"] then
        "bad\t\($at): must have exactly name, image and digest"
      elif ($e.name | type) != "string" or ($e.name | test("^[a-z0-9][a-z0-9._-]*$") | not) then
        "bad\t\($at): name must be an image name (lowercase letters, digits, . _ -)"
      elif ($e.image | type) != "string" or ($e.image | test("^[a-z0-9][a-z0-9._-]*(/[a-z0-9][a-z0-9._-]*)+$") | not) then
        "bad\t\($at): image must be a full address without tag or digest"
      elif ($e.digest | type) != "string" or ($e.digest | test("^(sha256:[0-9a-f]{64})?$") | not) then
        "bad\t\($at): digest must be sha256:<64 hex>"
      elif $need == "digest" and $e.digest == "" then
        "bad\t\($at): no digest — only a pushed image can be promoted, re-scanned or recorded"
      else "ok\t\($e.name)\t\($e.image)\t\($e.digest)" end
    end'
}

# artifact_refs WHO LIST [digest] — one ref per line
artifact_refs() {
  local rows name image digest
  rows=$(artifact_rows "$@") || return 1
  while IFS=$'\t' read -r name image digest; do artifact_ref "$image" "$digest"; done <<< "$rows"
}

# artifact_list — rows "name<TAB>image<TAB>digest" on stdin → the list, one
# line of JSON (always the same bytes for the same list: two lists compare as
# strings)
artifact_list() {
  _artifact_jq -Rnc '[inputs | select(. != "") | split("\t") | {name: .[0], image: .[1], digest: (.[2] // "")}]'
}
