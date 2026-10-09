#!/bin/sh
. tests/usage/lib.sh
fixture_repo="$task_tmp/repo"
state_dir="$task_tmp/state"
new_fixture_repo "$fixture_repo"
git -C "$fixture_repo" branch -M main
mkdir "$task_tmp/github"
git clone -q --bare "$fixture_repo" "$task_tmp/github/remote.git"
git -C "$fixture_repo" remote add origin "$task_tmp/github/remote.git"
receipt=$(sh usage.sh snapshot --repo "$fixture_repo" --rules-path IMPERATIVES.md --state-dir "$state_dir")
export USAGE_GH_FIXTURE="$task_tmp/github"
export PATH="$PWD/tests/usage/fake-bin:$PATH"
publish() {
  sh usage.sh publish --repo "$fixture_repo" --state-dir "$state_dir" --session session-a \
    --session-name 'Test session' --github-repo example/memory
}
record() {
  sh usage.sh record --repo "$fixture_repo" --state-dir "$state_dir" --session session-a --batch "$1" \
    --event "$receipt" Categorical/1 test/model-a "$2"
}
record prompt-a First
source_head=$(git -C "$fixture_repo" rev-parse HEAD)
printf 'do not include\n' > "$fixture_repo/unrelated.txt"
git -C "$fixture_repo" add unrelated.txt
source_status=$(git -C "$fixture_repo" status --porcelain)
assert_status 0 publish
branch=$(cat "$USAGE_GH_FIXTURE/pr-branch")
assert_equal 'Test session' "$(cat "$USAGE_GH_FIXTURE/pr-title")"
assert_equal 1 "$(cat "$USAGE_GH_FIXTURE/pr-number")"
assert_equal 1 "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-list --count "main..$branch")"
assert_equal usage.toon "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" diff --name-only "main...$branch")"
assert_status 0 publish
assert_equal 1 "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-list --count "main..$branch")"
record prompt-b Second
assert_status 0 publish
assert_equal 2 "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-list --count "main..$branch")"
assert_equal "$source_head" "$(git -C "$fixture_repo" rev-parse HEAD)"
assert_equal "$source_status" "$(git -C "$fixture_repo" status --porcelain)"

touch "$USAGE_GH_FIXTURE/offline"
record prompt-c Third
assert_status 3 publish
rm "$USAGE_GH_FIXTURE/offline"
assert_status 0 publish
assert_equal 3 "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-list --count "main..$branch")"

# Simulate the human merge in a separate clone, without touching the task checkout.
git clone -q "$USAGE_GH_FIXTURE/remote.git" "$task_tmp/human"
git -C "$task_tmp/human" config user.name 'Usage test'
git -C "$task_tmp/human" config user.email 'usage@example.invalid'
git -C "$task_tmp/human" -c commit.gpgsign=false merge --no-ff -qm 'Merge log evidence' "origin/$branch"
git -C "$task_tmp/human" push -q origin main
git -C "$task_tmp/human" rev-parse HEAD > "$USAGE_GH_FIXTURE/pr-merge"
printf 'MERGED\n' > "$USAGE_GH_FIXTURE/pr-state"
record prompt-d Fourth
assert_status 0 publish
new_branch=$(cat "$USAGE_GH_FIXTURE/pr-branch")
assert_equal 2 "$(cat "$USAGE_GH_FIXTURE/pr-number")"
assert_status 1 test "$new_branch" = "$branch"
assert_equal 1 "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-list --count "main..$new_branch")"
assert_status 0 grep -F 'Previous PR: #1' "$USAGE_GH_FIXTURE/pr-body"
blob=$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" ls-tree "$new_branch" -- usage.toon | awk '{print $3}')
git --git-dir="$USAGE_GH_FIXTURE/remote.git" cat-file blob "$blob" > "$task_tmp/published"
assert_equal 4 "$(awk 'END {print NR-1}' "$task_tmp/published")"
printf 'CLOSED\n' > "$USAGE_GH_FIXTURE/pr-state"
record prompt-e Fifth
assert_status 4 publish
assert_equal 2 "$(cat "$USAGE_GH_FIXTURE/pr-number")"
printf 'OPEN\n' > "$USAGE_GH_FIXTURE/pr-state"
assert_status 0 publish
assert_status 0 publish
assert_equal 2 "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-list --count "main..$new_branch")"
record prompt-f Sixth
cp tests/usage/cases/reject-push.sh "$USAGE_GH_FIXTURE/remote.git/hooks/pre-receive"
chmod +x "$USAGE_GH_FIXTURE/remote.git/hooks/pre-receive"
assert_status 3 publish
local_after_failure=$(git -C "$state_dir/publisher" rev-parse HEAD)
rm "$USAGE_GH_FIXTURE/remote.git/hooks/pre-receive"
assert_status 0 publish
assert_equal "$local_after_failure" "$(git -C "$state_dir/publisher" rev-parse HEAD)"
assert_equal 3 "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-list --count "main..$new_branch")"

record prompt-g Seventh
assert_status 143 env USAGE_TEST_INTERRUPT=before-commit-journal sh usage.sh publish \
  --repo "$fixture_repo" --state-dir "$state_dir" --session session-a --session-name 'Test session' --github-repo example/memory
committed_before_journal=$(git -C "$state_dir/publisher" rev-parse HEAD)
assert_status 0 publish
assert_equal "$committed_before_journal" "$(git -C "$state_dir/publisher" rev-parse HEAD)"
assert_equal 4 "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-list --count "main..$new_branch")"

second_state="$task_tmp/session-b"
second_receipt=$(sh usage.sh snapshot --repo "$fixture_repo" --rules-path IMPERATIVES.md --state-dir "$second_state")
sh usage.sh record --repo "$fixture_repo" --state-dir "$second_state" --session session-b --batch first \
  --event "$second_receipt" Categorical/1 test/model-b Other
touch "$USAGE_GH_FIXTURE/no-label"
assert_status 3 sh usage.sh publish --repo "$fixture_repo" --state-dir "$second_state" --session session-b --session-name 'Test session' --github-repo example/memory
rm "$USAGE_GH_FIXTURE/no-label"
touch "$USAGE_GH_FIXTURE/lose-create-response"
assert_status 3 sh usage.sh publish --repo "$fixture_repo" --state-dir "$second_state" --session session-b --session-name 'Test session' --github-repo example/memory
assert_equal 3 "$(cat "$USAGE_GH_FIXTURE/pr-number")"
second_branch=$(cat "$USAGE_GH_FIXTURE/pr-branch")
assert_status 1 test "$new_branch" = "$second_branch"
rm "$USAGE_GH_FIXTURE/lose-create-response"
assert_status 0 sh usage.sh publish --repo "$fixture_repo" --state-dir "$second_state" --session session-b --session-name 'Test session' --github-repo example/memory
assert_equal 3 "$(cat "$USAGE_GH_FIXTURE/pr-number")"
assert_equal 1 "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-list --count "main..$second_branch")"
assert_equal "$source_status" "$(git -C "$fixture_repo" status --porcelain)"
git -C "$task_tmp/human" fetch -q origin
git -C "$task_tmp/human" merge --squash "origin/$second_branch" > /dev/null
git -C "$task_tmp/human" -c commit.gpgsign=false commit -qm 'Squash log evidence'
git -C "$task_tmp/human" push -q origin main
git -C "$task_tmp/human" rev-parse HEAD > "$USAGE_GH_FIXTURE/pr-merge"
printf 'MERGED\n' > "$USAGE_GH_FIXTURE/pr-state"
sh usage.sh record --repo "$fixture_repo" --state-dir "$second_state" --session session-b --batch after-squash \
  --event "$second_receipt" Categorical/1 test/model-c 'After squash'
assert_status 0 sh usage.sh publish --repo "$fixture_repo" --state-dir "$second_state" --session session-b --session-name 'Test session' --github-repo example/memory
third_branch=$(cat "$USAGE_GH_FIXTURE/pr-branch")
assert_equal 4 "$(cat "$USAGE_GH_FIXTURE/pr-number")"
assert_equal 1 "$(git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-list --count "main..$third_branch")"

git -C "$task_tmp/human" fetch -q origin
git -C "$task_tmp/human" -c commit.gpgsign=false merge --no-ff -qm 'Merge before late push' "origin/$third_branch"
git -C "$task_tmp/human" push -q origin main
git -C "$task_tmp/human" rev-parse HEAD > "$USAGE_GH_FIXTURE/pr-merge"
git --git-dir="$USAGE_GH_FIXTURE/remote.git" rev-parse "$third_branch" > "$USAGE_GH_FIXTURE/race-head"
sh usage.sh record --repo "$fixture_repo" --state-dir "$second_state" --session session-b --batch late-prompt \
  --event "$second_receipt" Categorical/1 test/model-c 'Late evidence'
assert_status 4 sh usage.sh publish --repo "$fixture_repo" --state-dir "$second_state" --session session-b --session-name 'Test session' --github-repo example/memory
assert_equal 4 "$(cat "$USAGE_GH_FIXTURE/pr-number")"
assert_status 0 grep -F 'Late evidence' "$second_state/usage.toon"
assert_status 4 sh usage.sh publish --repo "$fixture_repo" --state-dir "$second_state" --session session-b --session-name 'Test session' --github-repo example/memory
finish publish
