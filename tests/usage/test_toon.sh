#!/bin/sh
. tests/usage/lib.sh
codec=lib/usage-toon.awk
base=0123456789012345678901234567890123456789
header='events[1]{ts,base,rule,harness,session,effect}:'
row='  1791540000,"0123456789012345678901234567890123456789",Categorical/1,test/model,session-a,Kept read-only scope.'
printf '%s\n%s' "$header" "$row" > "$task_tmp/valid"
printf 'events[2]{ts,base,rule,harness,session,effect}:\n%s' "$row" > "$task_tmp/bad"
assert_status 0 awk -v mode=check -f "$codec" "$task_tmp/valid"
assert_status 2 awk -v mode=check -f "$codec" "$task_tmp/bad"
mkdir "$task_tmp/event"
printf '%s\n' 1791540000 > "$task_tmp/event/ts"
printf '%s\n' "$base" > "$task_tmp/event/base"
printf '%s\n' Categorical/1 > "$task_tmp/event/rule"
printf '%s\n' test/model > "$task_tmp/event/harness"
printf '%s\n' session-a > "$task_tmp/event/session"
printf '%s\n' 'Kept read-only scope.' > "$task_tmp/event/effect"
awk -v mode=encode -f "$codec" "$task_tmp/event" > "$task_tmp/encoded"
assert_file_equal "$task_tmp/valid" "$task_tmp/encoded"

for value in 'comma,value' 'say "yes"' 'back\slash' 'ação' '42' true false null '-name' '#tag' ' edge ' '[x]' '{x}' 'x:y'; do
  printf '%s\n' "$value" > "$task_tmp/event/effect"
  awk -v mode=encode -f "$codec" "$task_tmp/event" > "$task_tmp/encoded"
  assert_status 0 awk -v mode=check -f "$codec" "$task_tmp/encoded"
done
printf 'line1\nline2\tend\r\001\n' > "$task_tmp/event/effect"
awk -v mode=encode -f "$codec" "$task_tmp/event" > "$task_tmp/encoded"
printf '%s\n%s' "$header" '  1791540000,"0123456789012345678901234567890123456789",Categorical/1,test/model,session-a,"line1\nline2\tend\r\u0001"' > "$task_tmp/expected"
assert_file_equal "$task_tmp/expected" "$task_tmp/encoded"
assert_status 0 awk -v mode=check -f "$codec" "$task_tmp/encoded"
for invalid in '"bad\xescape"' '"unterminated' '"x"extra' '"\ud800"' '"\u12"' 'null' '' 'x,extra'; do
  printf '%s\n  1791540000,"%s",Categorical/1,test/model,session-a,%s' "$header" "$base" "$invalid" > "$task_tmp/bad"
  assert_status 2 awk -v mode=check -f "$codec" "$task_tmp/bad"
done
printf '%s\n%s\n<<<<<<< HEAD' "$header" "$row" > "$task_tmp/bad"
assert_status 2 awk -v mode=check -f "$codec" "$task_tmp/bad"
printf '\300\257\n' > "$task_tmp/event/effect"
assert_status 2 awk -v mode=encode -f "$codec" "$task_tmp/event"
printf 'events[0]{ts,base,rule,harness,session,effect}:' > "$task_tmp/empty"
assert_status 0 awk -v mode=check -f "$codec" "$task_tmp/empty"
finish toon
