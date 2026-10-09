#!/bin/sh
. tests/usage/lib.sh
fixture_repo="$task_tmp/repo with spaces"
state_dir="$task_tmp/state"
new_fixture_repo "$fixture_repo"
assert_status 0 sh usage.sh snapshot --repo "$fixture_repo" --rules-path IMPERATIVES.md --state-dir "$state_dir"
receipt=$(cat "$task_tmp/stdout")
assert_file_equal "$fixture_repo/IMPERATIVES.md" "$receipt/rules.snapshot"
assert_equal "$fixture_base" "$(cat "$receipt/base")"
old_receipt=$receipt
printf '\nlocal change\n' >> "$fixture_repo/IMPERATIVES.md"
assert_status 2 sh usage.sh snapshot --repo "$fixture_repo" --rules-path IMPERATIVES.md --state-dir "$state_dir"
git -C "$fixture_repo" add IMPERATIVES.md
git -C "$fixture_repo" commit -qm '(MOD) Change fixture rule'
receipt=$(sh usage.sh snapshot --repo "$fixture_repo" --rules-path IMPERATIVES.md --state-dir "$state_dir")
assert_equal "$(git -C "$fixture_repo" rev-parse HEAD)" "$(cat "$receipt/base")"
assert_equal "$fixture_base" "$(cat "$old_receipt/base")"
assert_status 2 sh usage.sh snapshot --repo "$fixture_repo" --rules-path ../outside --state-dir "$state_dir"
assert_status 2 sh usage.sh snapshot --repo "$fixture_repo" --rules-path absent.md --state-dir "$state_dir"
assert_status 2 sh usage.sh snapshot --repo "$fixture_repo" --rules-path IMPERATIVES.md --state-dir "$fixture_repo/state"
assert_status 2 sh usage.sh snapshot --repo "$fixture_repo" --rules-path IMPERATIVES.md --state-dir "$state_dir" --unexpected yes
cp "$receipt/rules.snapshot" "$task_tmp/rules-before"
printf 'tampered\n' > "$receipt/rules.snapshot"
assert_status 2 sh usage.sh snapshot --repo "$fixture_repo" --rules-path IMPERATIVES.md --state-dir "$state_dir"
cp "$task_tmp/rules-before" "$receipt/rules.snapshot"
ln -s "$fixture_repo/IMPERATIVES.md" "$fixture_repo/link.md"
assert_status 2 sh usage.sh snapshot --repo "$fixture_repo" --rules-path link.md --state-dir "$state_dir"
printf 'events[0]{ts,base,rule,harness,session,effect}:' > "$task_tmp/empty.toon"
assert_status 0 sh usage.sh check --file "$task_tmp/empty.toon"
assert_status 2 sh usage.sh check --file "$task_tmp/empty.toon" --max-events 0
printf 'events[0]{ts,base,rule,harness,session,effect}:\000hidden' > "$task_tmp/nul.toon"
assert_status 2 sh usage.sh check --file "$task_tmp/nul.toon"
finish provenance
