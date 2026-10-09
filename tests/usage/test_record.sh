#!/bin/sh
. tests/usage/lib.sh
fixture_repo="$task_tmp/repo"
state_dir="$task_tmp/state"
new_fixture_repo "$fixture_repo"
assert_status 0 sh usage.sh record --repo "$fixture_repo" --state-dir "$state_dir" --session session-a --batch empty
assert_status 1 test -e "$state_dir/usage.toon"
receipt=$(sh usage.sh snapshot --repo "$fixture_repo" --rules-path IMPERATIVES.md --state-dir "$state_dir")
record() {
  sh usage.sh record --repo "$fixture_repo" --state-dir "$state_dir" --session session-a --batch "$1" --max-events 2 \
    --event "$receipt" Categorical/1 test/model-a "$2"
}
record prompt-a 'First decision.'
assert_status 0 test -f "$state_dir/usage.toon"
cp "$state_dir/usage.toon" "$task_tmp/first"
record prompt-a 'First decision.'
assert_file_equal "$task_tmp/first" "$state_dir/usage.toon"
assert_status 2 record prompt-a 'Changed payload.'
assert_file_equal "$task_tmp/first" "$state_dir/usage.toon"
record prompt-b 'Second decision.'
record prompt-c 'Third decision.'
assert_status 0 sh usage.sh check --file "$state_dir/usage.toon" --max-events 2
assert_equal 2 "$(awk 'END { print NR-1 }' "$state_dir/usage.toon")"
assert_status 1 grep -F 'First decision.' "$state_dir/usage.toon"
assert_status 0 grep -F 'Third decision.' "$state_dir/usage.toon"
cp "$state_dir/usage.toon" "$task_tmp/last"
assert_status 0 sh usage.sh record --repo "$fixture_repo" --state-dir "$state_dir" --session session-a --batch empty-again --max-events 1
assert_file_equal "$task_tmp/last" "$state_dir/usage.toon"
mkdir "$state_dir/lock"
assert_status 4 record prompt-d Locked
rmdir "$state_dir/lock"
assert_status 2 sh usage.sh record --repo "$fixture_repo" --state-dir "$state_dir" --session other-session --batch a \
  --event "$receipt" Categorical/1 test/model-a Other
cp "$state_dir/usage.toon" "$task_tmp/good"
printf 'broken\n' > "$state_dir/usage.toon"
assert_status 2 record prompt-d Invalid
assert_equal broken "$(cat "$state_dir/usage.toon")"
cp "$task_tmp/good" "$state_dir/usage.toon"
first_receipt=$receipt
printf '\n2. Keep provenance.\n' >> "$fixture_repo/IMPERATIVES.md"
git -C "$fixture_repo" add IMPERATIVES.md
git -C "$fixture_repo" commit -qm '(ADD) Add another fixture rule'
receipt=$(sh usage.sh snapshot --repo "$fixture_repo" --rules-path IMPERATIVES.md --state-dir "$state_dir")
sh usage.sh record --repo "$fixture_repo" --state-dir "$state_dir" --session session-a --batch mixed --max-events 2 \
  --event "$first_receipt" Categorical/1 test/model-a Old \
  --event "$receipt" Categorical/2 test/unknown New
assert_status 0 grep -F "$fixture_base" "$state_dir/usage.toon"
assert_status 0 grep -F "$(git -C "$fixture_repo" rev-parse HEAD)" "$state_dir/usage.toon"
assert_status 0 grep -F test/unknown "$state_dir/usage.toon"
record '../../batch;echo unsafe' '$(touch should-not-exist)'
assert_status 0 grep -F '$(touch should-not-exist)' "$state_dir/usage.toon"
assert_status 1 test -e should-not-exist
test_path="$PWD/tests/usage/fake-bin:$PATH"
assert_status 143 env PATH="$test_path" USAGE_TEST_INTERRUPT=after-preview sh usage.sh record \
  --repo "$fixture_repo" --state-dir "$state_dir" --session session-a --batch interrupted --max-events 2 \
  --event "$receipt" Categorical/1 test/model-a 'Recovered decision.'
assert_status 0 record interrupted 'Recovered decision.'
assert_equal 1 "$(grep -cF 'Recovered decision.' "$state_dir/usage.toon")"
assert_status 143 env PATH="$test_path" USAGE_TEST_INTERRUPT=before-preview sh usage.sh record \
  --repo "$fixture_repo" --state-dir "$state_dir" --session session-a --batch interrupted-before --max-events 2 \
  --event "$receipt" Categorical/1 test/model-a 'Recovered before rename.'
assert_status 0 record interrupted-before 'Recovered before rename.'
assert_equal 1 "$(grep -cF 'Recovered before rename.' "$state_dir/usage.toon")"
cp "$state_dir/usage.toon" "$task_tmp/pre-rollback"
assert_status 4 env PATH="$test_path" USAGE_TEST_TIME=1 sh usage.sh record \
  --repo "$fixture_repo" --state-dir "$state_dir" --session session-a --batch clock-rollback --max-events 2 \
  --event "$receipt" Categorical/1 test/model-a 'Old clock.'
assert_file_equal "$task_tmp/pre-rollback" "$state_dir/usage.toon"
assert_status 0 test -d "$state_dir/held"

large_repo="$task_tmp/large-repo"
new_fixture_repo "$large_repo"
awk -v base="$fixture_base" 'BEGIN {
  printf "events[5000]{ts,base,rule,harness,session,effect}:";
  for(i=1;i<=5000;i++) printf "\n  1,%s,Categorical/1,test/model,other-session,Old event %d",base,i
}' > "$large_repo/usage.toon"
git -C "$large_repo" add usage.toon
git -C "$large_repo" commit -qm '(ADD) Add fixture history'
large_receipt=$(sh usage.sh snapshot --repo "$large_repo" --rules-path IMPERATIVES.md --state-dir "$task_tmp/large-state")
sh usage.sh record --repo "$large_repo" --state-dir "$task_tmp/large-state" --session new-session --batch new-prompt \
  --event "$large_receipt" Categorical/1 test/model 'Newest event.'
assert_equal 5000 "$(awk 'END {print NR-1}' "$task_tmp/large-state/usage.toon")"
assert_status 0 grep -F 'Old event 2' "$task_tmp/large-state/usage.toon"
assert_status 0 grep -F 'Newest event.' "$task_tmp/large-state/usage.toon"
assert_status 1 grep -E 'Old event 1$' "$task_tmp/large-state/usage.toon"
finish record
