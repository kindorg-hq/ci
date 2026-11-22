#!/usr/bin/env bash
# Cases for the PR title check of pull-request.yml (Accept, step `title`): the
# step's own inputs, read from the workflow, run through the action it pins,
# one title at a time, against a stand-in for the GitHub API that serves the
# title. A title that passes must have the scope git-cliff (cut-release)
# reads: up to the first parenthesis. Runs in self-test and locally (needs
# docker and git):
#   .github/workflows/pull-request.title.test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
YQ=mikefarah/yq:4.54.1@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e
NODE=node:24.22.3-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5
failed=0

# the step as the workflow has it: {uses, with}
step=$(docker run --rm -i "$YQ" -o=json -I=0 \
  '.jobs.accept.steps[] | select(.id == "title") | {"uses": .uses, "with": .with}' \
  < "$here/pull-request.yml") && [ -n "$step" ] || { echo "FAIL no step with id title in pull-request.yml"; exit 1; }
uses=$(docker run --rm -i "$YQ" -p=json '.uses' <<< "$step")
repo=${uses%@*} sha=${uses#*@}
git init -q "$work/action"
if ! git -C "$work/action" fetch -q --depth 1 "https://github.com/$repo" "$sha" ||
  ! git -C "$work/action" checkout -q FETCH_HEAD; then echo "FAIL cannot fetch $uses"; exit 1; fi

# One run of the action, as the runner runs it: inputs as INPUT_*, the event
# payload, the API at githubBaseUrl. Last line: RESULT, pass, scope, error's
# first line, separated by \x1f (empty fields kept).
cat > "$work/run.mjs" <<'EOF'
import fs from 'node:fs';
import http from 'node:http';
const [title, labels, requireIssue, step] = process.argv.slice(2);
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
    field(out.error_message)].join('\x1f'));
  process.exitCode = 0;
});
await import('/action/dist/index.js');
EOF

check() { # check pass <scope>|fail <wanted words> <title> [require-issue] [labels]
  local want=$1 what=$2 title=$3 require=${4:-true} labels=${5:-} out pass scope error
  out=$(timeout 60 docker run --rm -u "$(id -u):$(id -g)" -v "$work/run.mjs:/run.mjs:ro" \
    -v "$work/action:/action:ro" "$NODE" node /run.mjs "$title" "$labels" "$require" "$step" 2>&1)
  IFS=$'\x1f' read -r _ pass scope error < <(grep '^RESULT' <<< "$out" | tail -1)
  local where="\"$title\" (require-issue $require${labels:+, label $labels})"
  if [ "$want" = pass ] && [ "$pass" = true ] && [ "$scope" = "$what" ]; then
    echo "ok   pass  $where: scope $scope"
  elif [ "$want" = fail ] && [ "$pass" = false ] && [[ $error == *"$what"* ]]; then
    echo "ok   fail  $where: $what"
  else
    echo "FAIL want $want ($what), got pass=$pass scope=\"$scope\": $where"
    echo "$out" | sed 's/^/     /'
    failed=1
  fi
}

# the scope ends at the first ")", as git-cliff reads it
check pass '#95' 'docs(#95): base-image bumps are fix(deps): they change what runs'
check pass '#95' 'docs(#95): a fix(deps): b'
check pass '#12' 'feat(#12): a (small) thing'
check pass '#7'  'fix(#7)!: breaking, with ! after the scope'
check pass '#7'  'fix(#7): x'
# known limit: the action's breaking pattern (no input sets it) is tried
# first and still runs to the last ")!: ", so such a subject fails
check fail 'Unknown scope "#7): a fix(deps"' 'fix(#7): a fix(deps)!: b'

# the work item is required
check fail 'No scope found'        'fix: x'
check fail 'Unknown scope "deps"'  'fix(deps): x'
check fail 'No scope found'        'fix(): x'
check fail 'No release type found' 'feat(#1)(#2): x'
check fail 'No release type found' 'fix((#7)): x'
check fail 'No release type found' 'fix(#7) x'
check fail 'No release type found' 'fix(#7):x'
check fail 'Unknown release type'  'feature(#7): x'

# Dependabot's and release-please's PRs are let through by label, unread
check pass '' 'chore(deps): Bump a from 1 to 2' true dependencies
check pass '' 'chore(main): release 4.2.0' true 'autorelease: pending'

# require-issue: false
check pass 'deps' 'fix(deps): x' false
check pass ''     'chore: x' false
check fail 'No release type found' 'feat(#1)(#2): x' false

exit $failed
