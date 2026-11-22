#!/usr/bin/env bash
# Cases for the PR title check of pull-request.yml (Accept, step `title`): the
# step's own inputs, read from the workflow, run through the action it pins,
# one title at a time, against a stand-in for the GitHub API that serves the
# title. Every title that passes is then read by git-cliff as cut-release runs
# it (its image, cliff.toml): the same scope and subject, or the case fails.
# Runs in self-test and locally (needs docker and git):
#   .github/workflows/pull-request.title.test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=$(mktemp -d)
label="kindorg-ci.title-test=$(basename "$work")" # unique per run, not per PID namespace
trap 'docker ps -aq --filter "label=$label" | xargs -r docker rm -f > /dev/null; rm -rf "$work"' EXIT
YQ=mikefarah/yq:4.54.1@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e
# the runtime the action declares (runs.using) → the image it runs in here
NODE24=node:24.22.3-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5
yq() { docker run --rm -i --network none "$YQ" "$@"; }
failed=0

# the step as the workflow has it: {uses, with}
step=$(yq -o=json -I=0 '.jobs.accept.steps[] | select(.id == "title") | {"uses": .uses, "with": .with}' \
  < "$here/pull-request.yml") && [ -n "$step" ] || { echo "FAIL no step with id title in pull-request.yml"; exit 1; }
uses=$(yq -p=json '.uses' <<< "$step")
repo=${uses%@*} sha=${uses#*@}
git init -q "$work/action"
if ! git -C "$work/action" fetch -q --depth 1 "https://github.com/$repo" "$sha" ||
  ! git -C "$work/action" checkout -q FETCH_HEAD; then echo "FAIL cannot fetch $uses"; exit 1; fi
using=$(yq '.runs.using' < "$work/action/action.yml")
main=$(yq '.runs.main' < "$work/action/action.yml")
case $using in
  node24) node=$NODE24 ;;
  *) echo "FAIL $uses runs on '$using': pin a node image for it in this test"; exit 1 ;;
esac
[ -f "$work/action/$main" ] || { echo "FAIL $uses: runs.main '$main' not found"; exit 1; }

# One run of the action, as the runner runs it: inputs as INPUT_*, the event
# payload, the API at githubBaseUrl. Last line: RESULT, pass, scope, subject,
# error's first line, separated by \x1f (empty fields kept).
cat > "$work/run.mjs" <<'EOF'
import fs from 'node:fs';
import http from 'node:http';
const [main, title, labels, requireIssue, step] = process.argv.slice(2);
// the two expressions the step's inputs use; any other is the test's to learn
const evaluate = (v) => String(v).replace(/\$\{\{(.*?)\}\}/g, (_, e) => {
  e = e.trim();
  if (e === 'inputs.require-issue') return requireIssue;
  const m = e.match(/^inputs\.require-issue && '([^']*)' \|\| ''$/);
  if (m) return requireIssue === 'true' ? m[1] : '';
  throw new Error(`the test cannot evaluate \${{ ${e} }}`);
});
const server = http.createServer((req, res) => {
  res.setHeader('content-type', 'application/json');
  res.setHeader('connection', 'close');
  res.end(JSON.stringify({ number: 1, title,
    labels: labels ? labels.split(',').map((name) => ({ name })) : [] }));
  server.close();
});
await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
server.unref(); // an action that fails before it asks for the PR still exits
const api = `http://127.0.0.1:${server.address().port}`;
const tmp = fs.mkdtempSync('/tmp/title-');
fs.writeFileSync(`${tmp}/event.json`, JSON.stringify({ pull_request:
  { number: 1, base: { user: { login: 'o' }, repo: { name: 'r' } } } }));
fs.writeFileSync(`${tmp}/output`, '');
Object.assign(process.env, { GITHUB_EVENT_NAME: 'pull_request',
  GITHUB_EVENT_PATH: `${tmp}/event.json`, GITHUB_OUTPUT: `${tmp}/output`,
  GITHUB_API_URL: api, GITHUB_TOKEN: 'test', INPUT_GITHUBBASEURL: api });
for (const [k, v] of Object.entries(JSON.parse(step).with))
  process.env[`INPUT_${k.replace(/ /g, '_').toUpperCase()}`] = evaluate(v);
process.on('exit', (code) => {
  const out = {};
  for (const m of fs.readFileSync(`${tmp}/output`, 'utf8').matchAll(/^(\w+)<<(\S+)\n([\s\S]*?)\n\2$/gm))
    out[m[1]] = m[3];
  const field = (v) => (v ?? '').split('\n')[0].replace(/\x1f/g, ' ');
  console.log(['RESULT', code === 0 && !process.exitCode, field(out.scope),
    field(out.subject), field(out.error_message)].join('\x1f'));
  process.exitCode = 0;
});
await import(`/action/${main}`);
EOF

read_by_cliff=() # title, scope, subject (\x1f between) of each title that passed, for git-cliff
check() { # check pass <scope>|fail <wanted words> <title> [require-issue] [labels]
  local want=$1 what=$2 title=$3 require=${4:-true} labels=${5:-} out pass scope subject error
  out=$(timeout 60 docker run --rm --init --network none --label "$label" -u "$(id -u):$(id -g)" \
    -v "$work/run.mjs:/run.mjs:ro" -v "$work/action:/action:ro" \
    "$node" node /run.mjs "$main" "$title" "$labels" "$require" "$step" 2>&1)
  IFS=$'\x1f' read -r _ pass scope subject error < <(grep '^RESULT' <<< "$out" | tail -1)
  local where="\"$title\" (require-issue $require${labels:+, label $labels})"
  if [ "$want" = pass ] && [ "$pass" = true ] && [ "$scope" = "$what" ]; then
    echo "ok   pass  $where: scope $scope"
    # let through by label: not parsed, nothing to compare
    [ -n "$labels" ] || [ "${CLIFF:-yes}" = no ] || read_by_cliff+=("$title"$'\x1f'"$scope"$'\x1f'"$subject")
  elif [ "$want" = fail ] && [ "$pass" = false ] && [[ $error == *"$what"* ]]; then
    echo "ok   fail  $where: $what"
  else
    echo "FAIL want $want ($what), got pass=${pass:-none} scope=\"$scope\": $where"
    echo "$out" | sed 's/^/     /'
    failed=1
  fi
}

# the scope ends at the first ")", as git-cliff reads it
check pass '#95' 'docs(#95): base-image bumps are fix(deps): they change what runs'
check pass '#95' 'docs(#95): a fix(deps): b'
check pass '#12' 'feat(#12): a (small) thing'
check pass '#7'  'fix(#7)!: breaking, with ! after the scope'
check pass '#7'  'feat(#7)!: drop fix(deps): y'
check pass '#7'  'fix(#7): x'
check pass '#7'  'fix(#7): a | b'

# the work item is required
check fail 'No scope found'                   'fix: x'
check fail 'Unknown scope "deps"'             'fix(deps): x'
check fail 'No release type found'            'fix(): x'
check fail 'No release type found'            'feat(#1)(#2): x'
check fail 'Unknown scope "#1)(#2"'           'feat(#1)(#2)!: x'
check fail 'No release type found'            'fix((#7)): x'
check fail 'No release type found'            'fix(#7) x'
check fail 'No release type found'            'fix(#7):x'
check fail 'Unknown release type'             'feature(#7): x'
check fail 'No scope found'                   'feat()!: x'

# Dependabot's and release-please's PRs are let through by label, unread
check pass '' 'chore(deps): Bump a from 1 to 2' true dependencies
check pass '' 'chore(main): release 4.2.0' true 'autorelease: pending'

# require-issue: false
check pass 'deps' 'fix(deps): x' false
check pass ''     'chore: x' false
check fail 'No release type found'            'fix(): x' false
check fail 'No release type found'            'feat(#1)(#2): x' false
check fail 'Disallowed scope was found: #1)(#2' 'feat(#1)(#2)!: x' false

# Known limits: the action tries the preset's breakingHeaderPattern first,
# /^(\w*)(?:\((.*)\))?!: (.*)$/, and no input sets it. Its scope runs to the
# last ")!: ", so a subject containing ")!: " fails (a valid title refused);
# and it allows an empty scope, so "feat()!: x" passes when no issue is
# required, though git-cliff cannot parse it and leaves it out of the notes.
check fail 'Unknown scope "#7): a fix(deps"'           'fix(#7): a fix(deps)!: b'
check fail 'Disallowed scope was found: #7): a fix(deps' 'fix(#7): a fix(deps)!: b' false
CLIFF=no check pass '' 'feat()!: x' false

# Each title that passed, read by git-cliff as cut-release reads it: the
# same scope and subject (a title it cannot parse is missing from its notes)
cliff_image=$(yq '.runs.steps[].env.GIT_CLIFF | select(.)' < "$root/actions/cut-release/action.yml")
[ -n "$cliff_image" ] || { echo "FAIL no GIT_CLIFF image in actions/cut-release/action.yml"; exit 1; }
# the temporary repo ignores the developer's git config (signing, hooks)
cgit() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$work/cliff" \
  -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
commit() { cgit commit -q --no-verify --allow-empty -m "$1" || { echo "FAIL cannot commit \"$1\" for git-cliff"; exit 1; }; }
if ! mkdir "$work/cliff" || ! cgit init -q; then echo "FAIL cannot make the repo for git-cliff"; exit 1; fi
commit "chore: base"
cgit tag v0.0.0 || { echo "FAIL cannot tag the base for git-cliff"; exit 1; }
for entry in "${read_by_cliff[@]}"; do commit "${entry%%$'\x1f'*}"; done
if ! context=$(docker run --rm --network none --label "$label" -u "$(id -u):$(id -g)" --entrypoint git-cliff \
  -v "$work/cliff:/app" -v "$root/actions/cut-release/cliff.toml:/cliff.toml:ro" -w /app \
  "$cliff_image" --config /cliff.toml --unreleased --context 2> "$work/cliff.err"); then
  echo "FAIL git-cliff failed:"; sed 's/^/     /' "$work/cliff.err"; exit 1
fi
# per commit three lines: title, scope, subject
declare -A read_as=()
while IFS= read -r t && IFS= read -r sc && IFS= read -r sub; do
  read_as[$t]="$sc"$'\x1f'"$sub"
done < <(yq -p=json '.[0].commits[] | [(.raw_message | split("\n") | .[0]), (.scope // ""), (.message | split("\n") | .[0])] | .[]' <<< "$context")
for entry in "${read_by_cliff[@]}"; do
  IFS=$'\x1f' read -r t sc sub <<< "$entry"
  if [ "${read_as[$t]+set}" != set ]; then
    echo "FAIL git-cliff leaves \"$t\" out: it cannot parse it"; failed=1
  elif [ "${read_as[$t]}" = "$sc"$'\x1f'"$sub" ]; then
    echo "ok   git-cliff reads \"$t\" the same: scope \"$sc\", subject \"$sub\""
  else
    IFS=$'\x1f' read -r csc csub <<< "${read_as[$t]}"
    echo "FAIL git-cliff reads \"$t\" otherwise: scope \"$csc\", subject \"$csub\"; the check: scope \"$sc\", subject \"$sub\""
    failed=1
  fi
done

exit $failed
