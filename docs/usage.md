# Optional imperative usage evidence

This mechanism records an agent's declaration that a rule mattered to a decision. It does not read hidden reasoning, prove compliance, or make a rarely used rule obsolete. Use it alongside issue history when considering compaction.

The implementation does not enable itself. Adopt the usage instruction separately, after reviewing it. It never edits imperatives or merges a PR.

## Requirements

- Linux or macOS with a POSIX shell, AWK, standard command-line utilities and Git.
- Publication additionally needs an existing authenticated `gh` installation and the `logs` label. No dependency is automatically installed.
- A local checkout of the memory instance with committed rules. Its `origin` must match the explicit GitHub destination. Do not send private instance events to a public template.
- A private state directory outside the repository, dedicated to one repository, harness and session. It contains rule snapshots, pending events and recovery data; protect it like the logs themselves.

Validation on 2026-10-09: the full shell suite passed on macOS. The codec tests passed in Linux; full Linux publication/provenance tests have not yet run. GitHub calls in tests use a deterministic substitute with real local Git repositories; live publication is not yet validated. Treat adoption as a pilot until those checks are complete.

## Capture the rules you actually use

Set paths for your instance and choose its real session ID. These are examples, not defaults:

```sh
repo=/absolute/path/to/project-memory
state_dir=/absolute/path/outside-the-repo/session-state
session=actual-session-id
snapshot=$(sh "$repo/usage.sh" snapshot --repo "$repo" \
  --rules-path IMPERATIVES.md --state-dir "$state_dir")
cat "$snapshot/rules.snapshot"
```

Read that snapshot before using it as an event's origin. A receipt identifies the full commit, rules path and blob; dirty rules are rejected. Capture and read another snapshot when the rules change. An older receipt remains valid for decisions made against the older text. Identity of content is verifiable; whether the agent actually read it remains a declaration.

## Record a prompt's events

One event per rule and decision, including when the rule confirms the chosen action. Merely loading or quoting a rule is not an event. Supply the actual tool/model identifier when available, otherwise `tool/unknown`. Do not guess the model.

```sh
sh "$repo/usage.sh" record --repo "$repo" --state-dir "$state_dir" \
  --session "$session" --batch actual-prompt-id --max-events 5000 \
  --event "$snapshot" 'Categorical/The file/1' 'my-agent/unknown' \
    'Kept task state out of the permanent rule.'
```

Repeat `--event SNAPSHOT RULE HARNESS EFFECT` for more events in the same prompt. Rule references identify section and item against the snapshot, not today's numbering. Each event can have a different snapshot or model. `effect` is a short operational situation and consequence, not a chain of thought or transcript. Do not include credentials, personal data or private details in a public destination.

Keep the same batch ID when retrying the same prompt. An identical retry is a no-op; different content under the same ID is rejected. Distinct decisions are not deduplicated by text. Without events, do not call the command, or call `record` without `--event`: no log is created and no commit is made.

If the harness has no turn ID, its integration must generate and retain an operational ID before recording. If it exposes no session ID, obtain one explicitly rather than inventing a harness-native ID. The program installs no hooks; invocation just before the final response is the portable baseline.

## Publish and merge

During explicit setup, create the label in the chosen instance if absent:

```sh
gh label create logs --repo owner/project-memory \
  --color 1D76DB --description 'Imperative usage evidence'
```

GitHub templates do not copy labels. Publication reports a pending state if the label or authentication is missing; it does not create them silently.

```sh
sh "$repo/usage.sh" publish --repo "$repo" --state-dir "$state_dir" \
  --session "$session" --session-name 'Your session name' \
  --github-repo owner/project-memory
```

The program uses a dedicated clone under the state directory. It never switches the task checkout's branch or stages its files. Each recorded prompt becomes one commit containing only `usage.toon`. Pending offline batches retain separate commits. A retry of publication does not record events again.

The PR title is the session name; if empty, it uses the session ID. Its body identifies the session and models, and it carries `logs`. You review and merge manually. Further events use the same open PR. After a merge, a new cycle starts from the current default branch and links the previous PR. Closing without merge pauses publication until you decide what to do.

If a merge races with publication and inclusion cannot be proved, publication stops with the local batches intact. Do not blindly replay them. Conflicts between different sessions' PRs remain a manual decision.

## Format and retention

`usage.toon` is a fixed-profile TOON table:

```text
events[N]{ts,base,rule,harness,session,effect}:
```

The script fills the count and data rows. `ts` is Unix seconds when recording, `base` is the full rules commit, and the remaining columns are strings. One physical line per event; line breaks inside strings are escaped. The writer follows the [pinned TOON specification](https://github.com/toon-format/spec/blob/d09c3d33e37389345a74bd96981eb96dd9be6c5e/SPEC.md), with comma delimiters and two-space indentation. It is not a general TOON decoder: nested structures, alternate headers/delimiters and non-writer Unicode escape forms are outside this profile. NUL is rejected, not silently stripped.

The configurable default is 5,000 events. Retention selects the newest timestamps and preserves input order for ties. The limit is not an age, byte or token limit, and does not shrink Git history or the local recovery journal. Keep clocks synchronized. If retention would discard an entire new batch, it is held locally for inspection instead of creating an empty commit.

```sh
sh "$repo/usage.sh" check --file /path/to/usage.toon --max-events 5000
```

Check the combined file before merging concurrent log PRs. A malformed existing file is never replaced. An event log can contain inaccurate declarations even when its format is valid.

## Recovery and stopping

| Exit | Meaning | Action |
|---|---|---|
| `0` | Success or no-op | Continue normal work |
| `2` | Invalid input, format or provenance | Correct the identified input; do not invent missing evidence |
| `3` | Publication pending | Restore access and retry `publish`, not `record` |
| `4` | Lock, closed PR or ambiguous recovery | Inspect state and remote history before retrying |

Failures in observability should be reported briefly, not stop the primary task or relax its rules. A stale lock is not automatically removed; first confirm no writer is active. Never delete the whole state directory to repair a publication problem: it holds batch identities needed to avoid duplicates.

To pause, stop invoking the commands or disable only the integration you explicitly installed. Existing logs, branches and pending data remain intact. No background process or automatic compaction is installed.

## Verification and cost

Run `sh tests/usage/run.sh` from the repository root. Tests create synthetic repositories in a unique temporary directory and remove that exact directory on exit. They do not access GitHub or a database.

Recording validates and sorts the retained file plus the incoming batch: sorting cost grows as `O(n log n)` with that event count; bytes also depend on effect length. Publication adds Git/network operations. Batch journaling trades local disk space for recoverability and keeps copies until explicitly maintained. Token savings compared with JSONL, real GitHub latency and completeness of the agent's declarations have not been measured. Do not infer them from the file format or test success.
