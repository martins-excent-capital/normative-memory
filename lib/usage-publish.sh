# Loaded only by usage.sh from its own installation directory.
atomic_line() {
  printf '%s\n' "$2" > "$scratch/value"
  mv "$scratch/value" "$1"
}
query_pr() {
  gh pr list --repo "$github_repo" --head "$log_branch" --state all \
    --json number,state,mergeCommit,headRefOid \
    --jq '.[] | [.number,.state,(.mergeCommit.oid // ""),.headRefOid] | join("|")' > "$scratch/pr" \
    || die 3 'cannot read the session PR; retry publish'
  [ "$(awk 'END {print NR+0}' "$scratch/pr")" -le 1 ] || die 4 'multiple PRs found for the session branch'
  pr_number= pr_state= pr_merge= pr_head=
  [ -s "$scratch/pr" ] || return 0
  IFS='|' read -r pr_number pr_state pr_merge pr_head < "$scratch/pr"
  case "$pr_number" in ''|*[!0-9]*) die 3 'invalid PR response' ;; esac
  case "$pr_state" in OPEN|MERGED|CLOSED) ;; *) die 3 'invalid PR state' ;; esac
}
log_blob() {
  git -C "$publisher" ls-tree "$1" -- usage.toon | awk '$2=="blob" && $1 ~ /^100/ {print $3}'
}
batch_queue() {
  : > "$scratch/queue-unsorted"
  for queued in "$state_dir"/batches/*; do
    [ -d "$queued" ] || continue
    printf '%s %s\n' "$(cat "$queued/sequence")" "${queued##*/}" >> "$scratch/queue-unsorted"
  done
  sort -k1,1n "$scratch/queue-unsorted" > "$scratch/queue"
}
publish() {
  [ -n "$session" ] && [ -n "$github_repo" ] || die 2 'session and github-repo are required'
  case "$github_repo" in *[!A-Za-z0-9_./-]*|/*|*/../*|*/*/*) die 2 'invalid GitHub repository name' ;; esac
  case "$github_repo" in */*) ;; *) die 2 'expected owner/repository' ;; esac
  setup_state
  acquire_lock
  [ -f "$state_dir/session" ] || return 0
  [ "$(cat "$state_dir/session")" = "$session" ] || die 2 'state belongs to another session'
  recover_preview
  batch_queue
  pending_count=0
  while read -r sequence batch_key; do
    [ -f "$state_dir/batches/$batch_key/delivered" ] || pending_count=$((pending_count+1))
  done < "$scratch/queue"
  [ "$pending_count" -gt 0 ] || return 0
  command -v gh >/dev/null 2>&1 || die 3 'gh is unavailable; local batches are preserved'
  gh auth status >/dev/null 2>&1 || die 3 'GitHub authentication is unavailable'
  gh repo view "$github_repo" --json nameWithOwner,defaultBranchRef,isPrivate,sshUrl,url \
    --jq '.nameWithOwner, .defaultBranchRef.name, (.isPrivate|tostring), .sshUrl, (.url + ".git")' \
    > "$scratch/repository" || die 3 'cannot inspect the destination repository'
  remote_name=$(sed -n '1p' "$scratch/repository")
  default_branch=$(sed -n '2p' "$scratch/repository")
  private=$(sed -n '3p' "$scratch/repository")
  ssh_url=$(sed -n '4p' "$scratch/repository")
  https_url=$(sed -n '5p' "$scratch/repository")
  [ "$remote_name" = "$github_repo" ] || die 2 'destination identity differs'
  case "$private" in true|false) ;; *) die 3 'destination visibility is unavailable' ;; esac
  git check-ref-format "refs/heads/$default_branch" >/dev/null || die 3 'invalid default branch'
  origin=$(git -C "$repo" remote get-url origin) || die 2 'origin is required'
  [ "$origin" = "$ssh_url" ] || [ "${origin%.git}" = "${https_url%.git}" ] || die 2 'destination differs from source origin'
  if [ -f "$state_dir/destination" ]; then
    [ "$(cat "$state_dir/destination")" = "$github_repo/$private" ] || die 4 'destination identity or visibility changed'
  else
    atomic_line "$state_dir/destination" "$github_repo/$private"
  fi
  gh label list --repo "$github_repo" --search logs --json name --jq '.[] | select(.name == "logs") | .name' \
    > "$scratch/labels" || die 3 'cannot inspect the logs label'
  [ "$(cat "$scratch/labels")" = logs ] || die 3 'create the logs label before enabling publication'
  publisher="$state_dir/publisher"
  [ ! -L "$publisher" ] || die 2 'publisher must not be redirected'
  if [ ! -d "$publisher" ]; then
    git clone -q --no-checkout "$repo" "$publisher" || die 3 'cannot prepare isolated publisher'
    git -C "$publisher" remote set-url origin "$origin"
    for config_key in user.name user.email commit.gpgsign; do
      config_value=$(git -C "$repo" config --get "$config_key" || :)
      [ -z "$config_value" ] || git -C "$publisher" config "$config_key" "$config_value"
    done
  fi
  [ "$(git -C "$publisher" remote get-url origin)" = "$origin" ] || die 2 'publisher origin changed'
  git -C "$publisher" fetch -q origin || die 3 'fetch failed; local batches are preserved'
  # Every recorded base must already belong to the authorized remote's history.
  while read -r sequence batch_key; do
    batch_dir="$state_dir/batches/$batch_key"
    [ ! -f "$batch_dir/delivered" ] || continue
    for event in "$batch_dir"/events/*; do
      event_base=$(cat "$event/base")
      git -C "$publisher" cat-file -e "$event_base^{commit}" 2>/dev/null || die 3 'recorded base is not available remotely'
      refs=$(git -C "$publisher" for-each-ref --contains "$event_base" --format='%(refname)' refs/remotes/origin/)
      [ -n "$refs" ] || die 3 'recorded base is not published to origin'
    done
  done < "$scratch/queue"
  cycle=1
  [ ! -f "$state_dir/cycle" ] || cycle=$(cat "$state_dir/cycle")
  case "$cycle" in ''|*[!0-9]*|0*) die 2 'invalid cycle state' ;; esac
  identity=$(printf '%s\n%s\n%s\n' "$github_repo" "$session" "$(cat "$state_dir/harness")" | git -C "$repo" hash-object --stdin)
  log_branch="usage/$identity-$cycle"
  query_pr
  [ "$pr_state" != CLOSED ] || die 4 'PR was closed without merge; decide before retrying'
  if [ "$pr_state" = MERGED ]; then
    [ -n "$pr_merge" ] || die 4 'merge provenance is unavailable'
    old_head=$(git -C "$publisher" rev-parse "refs/heads/$log_branch")
    if ! git -C "$publisher" merge-base --is-ancestor "$old_head" "$pr_merge"; then
      merged_blob=$(log_blob "$pr_merge")
      old_blob=$(log_blob "$old_head")
      [ -n "$merged_blob" ] && [ "$merged_blob" = "$old_blob" ] || die 4 'cannot prove which batches the merge included'
    fi
    for old_batch in "$state_dir"/batches/*; do
      [ -f "$old_batch/publish-$cycle/commit" ] || continue
      atomic_line "$old_batch/delivered" "$pr_number"
    done
    atomic_line "$state_dir/previous-pr" "$pr_number"
    cycle=$((cycle+1))
    atomic_line "$state_dir/cycle" "$cycle"
    log_branch="usage/$identity-$cycle"
    query_pr
  fi
  git check-ref-format "refs/heads/$log_branch" >/dev/null || die 2 'invalid log branch'
  if git -C "$publisher" show-ref --verify --quiet "refs/heads/$log_branch"; then
    git -C "$publisher" switch -q "$log_branch" || die 4 'publisher checkout needs inspection'
  else
    git -C "$publisher" switch -qc "$log_branch" "origin/$default_branch" || die 4 'cannot start a log cycle'
  fi
  atomic_line "$state_dir/cycle" "$cycle"
  changed=0
  while read -r sequence batch_key; do
    batch_dir="$state_dir/batches/$batch_key"
    [ ! -f "$batch_dir/delivered" ] || continue
    intent="$batch_dir/publish-$cycle"
    if [ ! -d "$intent" ]; then
      [ -z "$(git -C "$publisher" status --porcelain)" ] || die 4 'publisher has unrecognized edits'
      mkdir "$scratch/intent"
      git -C "$publisher" rev-parse HEAD > "$scratch/intent/parent"
      if [ -f "$publisher/usage.toon" ]; then
        [ ! -L "$publisher/usage.toon" ] || die 2 'published log must not be a symlink'
        cp "$publisher/usage.toon" "$scratch/before"
      else
        empty_log "$scratch/before"
      fi
      limit=$(cat "$batch_dir/max-events")
      combine_logs "$scratch/before" "$batch_dir/events.toon" "$scratch/intent/candidate" "$limit"
      cmp -s "$scratch/before" "$scratch/intent/candidate" && die 4 'retention would discard the entire pending batch'
      git -C "$publisher" hash-object --no-filters "$scratch/intent/candidate" > "$scratch/intent/blob"
      mv "$scratch/intent" "$intent"
    fi
    parent=$(cat "$intent/parent")
    expected_blob=$(cat "$intent/blob")
    if [ ! -f "$intent/commit" ]; then
      current_head=$(git -C "$publisher" rev-parse HEAD)
      if [ "$current_head" != "$parent" ]; then
        [ "$(git -C "$publisher" rev-parse HEAD^)" = "$parent" ] &&
          [ "$(log_blob HEAD)" = "$expected_blob" ] &&
          [ "$(git -C "$publisher" diff-tree --no-commit-id --name-only -r HEAD)" = usage.toon ] \
          || die 4 'commit recovery needs inspection'
      else
        alien=$(git -C "$publisher" status --porcelain -- . ':!usage.toon')
        [ -z "$alien" ] || die 4 'publisher has unrelated changes'
        cp "$intent/candidate" "$scratch/publish-candidate"
        mv "$scratch/publish-candidate" "$publisher/usage.toon"
        git -C "$publisher" add -- usage.toon
        [ "$(git -C "$publisher" diff --cached --name-only)" = usage.toon ] || die 4 'staged files are not exclusively usage.toon'
        git -C "$publisher" commit -qm '(MOD) Record imperative usage events' || die 3 'commit failed; batch preserved'
        current_head=$(git -C "$publisher" rev-parse HEAD)
      fi
      atomic_line "$intent/commit" "$current_head"
    fi
    committed=$(cat "$intent/commit")
    git -C "$publisher" merge-base --is-ancestor "$committed" HEAD || die 4 'recorded commit is not on the log branch'
    changed=1
  done < "$scratch/queue"
  [ "$changed" -eq 1 ] || return 0
  git -C "$publisher" push -q origin "HEAD:refs/heads/$log_branch" || die 3 'push failed; retry publish without recording again'
  query_pr
  case "$pr_state" in MERGED|CLOSED) die 4 'PR changed during publication; preserve pending batches for reconciliation' ;; esac
  [ -n "$session_name" ] || session_name=$session
  {
    printf 'Session: %s\n\n' "$session"
    printf 'Harness/models:\n'
    for body_batch in "$state_dir"/batches/*; do
      [ -d "$body_batch/publish-$cycle" ] || continue
      for event in "$body_batch"/events/*; do cat "$event/harness"; done
    done | sort -u
    if [ -f "$state_dir/previous-pr" ]; then printf '\nPrevious PR: #%s\n' "$(cat "$state_dir/previous-pr")"; fi
    printf '\nUsage evidence only. Manual merge; no normative changes.\n'
  } > "$scratch/body"
  if [ -z "$pr_number" ]; then
    gh pr create --repo "$github_repo" --base "$default_branch" --head "$log_branch" \
      --title "$session_name" --label logs --body-file "$scratch/body" > /dev/null \
      || die 3 'PR creation was not confirmed; retry publish to discover it'
  else
    gh pr edit "$pr_number" --repo "$github_repo" --body-file "$scratch/body" > /dev/null \
      || die 3 'PR metadata update is pending'
  fi
  query_pr
  [ "$pr_state" = OPEN ] && [ "$pr_head" = "$(git -C "$publisher" rev-parse HEAD)" ] \
    || die 4 'remote PR no longer matches the published head'
  while read -r sequence batch_key; do
    batch_dir="$state_dir/batches/$batch_key"
    [ ! -f "$batch_dir/publish-$cycle/commit" ] || atomic_line "$batch_dir/delivered" "$pr_number"
  done < "$scratch/queue"
  printf 'usage: logs published in PR #%s; merge is manual\n' "$pr_number"
}
