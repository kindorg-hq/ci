#!/usr/bin/env bash
# No downgrade: refuse to record a version lower than the one the GitOps repo
# already records for the app. An older run finishing after a newer one would
# otherwise roll Production back.
#
#   no-downgrade.sh <dir with kustomization.yaml> <version to record>
#
# The current version is the app.kubernetes.io/version label that gitops-pr
# writes into the kustomization (labels[].pairs). Equal is allowed
# (re-delivery), no label is allowed (first delivery). Versions are SemVer; a
# leading "v" is ignored, build metadata (+...) does not count.
# Plain bash, no GitHub: self-test runs it against fixtures/gitops.
set -euo pipefail
export LC_ALL=C  # ASCII order for pre-release identifiers

dir=${1:?usage: no-downgrade.sh <kustomization dir> <version>}
next=${2:?usage: no-downgrade.sh <kustomization dir> <version>}

file=
for f in kustomization.yaml kustomization.yml Kustomization; do
  [ -f "$dir/$f" ] && { file="$dir/$f"; break; }
done
[ -n "$file" ] || { echo "::error::no kustomization in $dir"; exit 1; }

semver='^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

# compare a b -> prints -1, 0 or 1 (SemVer 2.0.0 precedence)
compare() {
  local a=${1#v} b=${2#v}
  a=${a%%+*}; b=${b%%+*}
  local ac=${a%%-*} bc=${b%%-*} ap= bp=
  [[ $a == *-* ]] && ap=${a#*-}
  [[ $b == *-* ]] && bp=${b#*-}
  local -a x y
  IFS=. read -ra x <<< "$ac"; IFS=. read -ra y <<< "$bc"
  for i in 0 1 2; do
    if ((10#${x[i]} != 10#${y[i]})); then
      ((10#${x[i]} < 10#${y[i]})) && echo -1 || echo 1; return
    fi
  done
  # a release ranks above its pre-releases
  if [ -z "$ap" ] && [ -z "$bp" ]; then echo 0; return; fi
  [ -z "$ap" ] && { echo 1; return; }
  [ -z "$bp" ] && { echo -1; return; }
  IFS=. read -ra x <<< "$ap"; IFS=. read -ra y <<< "$bp"
  local n=$(( ${#x[@]} > ${#y[@]} ? ${#x[@]} : ${#y[@]} ))
  for ((i = 0; i < n; i++)); do
    [ $i -ge ${#x[@]} ] && { echo -1; return; }
    [ $i -ge ${#y[@]} ] && { echo 1; return; }
    local p=${x[i]} q=${y[i]}
    [ "$p" = "$q" ] && continue
    if [[ $p =~ ^[0-9]+$ && $q =~ ^[0-9]+$ ]]; then
      ((10#$p < 10#$q)) && echo -1 || echo 1
    elif [[ $p =~ ^[0-9]+$ ]]; then echo -1   # numeric ranks below alphanumeric
    elif [[ $q =~ ^[0-9]+$ ]]; then echo 1
    else [[ $p < $q ]] && echo -1 || echo 1
    fi
    return
  done
  echo 0
}

[[ $next =~ $semver ]] || { echo "::error::$next is not a SemVer version"; exit 1; }

current=$(sed -nE "s/^[[:space:]]*app\.kubernetes\.io\/version:[[:space:]]*['\"]?([^'\"[:space:]#]+)['\"]?.*$/\1/p" "$file" | sort -u)
if [ -z "$current" ]; then
  echo "No app.kubernetes.io/version in $file yet: first delivery, recording $next"
  exit 0
fi
if [ "$(wc -l <<< "$current")" -gt 1 ]; then
  echo "::error::$file labels more than one app.kubernetes.io/version: $(echo "$current" | paste -sd' ' -); fix it by hand first"
  exit 1
fi
[[ $current =~ $semver ]] || {
  echo "::error::$file records app.kubernetes.io/version $current, which is not SemVer; fix it by hand first"; exit 1; }

case $(compare "$next" "$current") in
  -1)
    echo "::error::refusing to record $next: $file already records $current, which is higher. Deliveries never go backwards — an older run finished after a newer one, or this is not the latest Release. To go back, fix forward with a new Release (break-glass: homelab-k8s README)."
    exit 1 ;;
  0) echo "Re-delivery: $file already records $current, recording $next again" ;;
  1) echo "Recording $next over $current" ;;
esac
