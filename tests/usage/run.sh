#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
if [ "$#" -eq 0 ]; then
  set -- tests/usage/test_*.sh
fi
for test_file do
  case "$test_file" in tests/usage/*) ;; *) test_file="tests/usage/$test_file" ;; esac
  sh "$test_file"
done
