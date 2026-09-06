# Imperatives

Permanent rules of work. **Categorical** = always true, unconditionally. **Hypothetical** = true when its condition applies.

**This file is timeless.** It holds no state: no ticket number, PR, issue, date, sha, in-flight branch name or measurement. A rule born from a real mistake carries the **mechanism** of that mistake, never the incident — the mechanism is what prevents the repeat, and the mechanism is what outlives the day.

A living document. Every item is atomic and numbered so it can be edited or removed on its own. Numbers change when the document is reorganised; nothing here is sacred, and everything enters, changes and leaves through the same issue flow.

---

# Categorical Imperative

## The file

1. **This file is timeless.** It describes how work is done, never what is being worked on. If a rule makes no sense without the incident that produced it, it is not yet a rule.
2. **The mechanism survives, the incident does not.** When recording an item, keep the cause that repeats and discard the occurrence: who, when, in which file, under which number.
3. **Task state does not belong here.** Tickets, branches, PRs, shas, measurements, momentary access and configuration values live in the tracker, in the code repository and in the session itself — never in this file.

## The imperative about the imperatives

4. **Every normative proposal begins as an issue, opened by the agent.** The agent never edits this file on its own initiative, and you never have to write or structure the issue by hand. The division of roles is what makes the system work: **the issue holds the context and the mechanism**, **the file holds only the timeless rule**, **the commit holds the decision**.
5. **Research and decompose before proposing.** Break the candidate into **trigger, action, and form or constraints**, and look for each part in this file, in open issues labelled `imperative`, and in closed ones. Do not create an equivalent rule, a particular case with no new behaviour, or a specific rule restating a form that a general rule already imposes. Where the overlap is partial, propose only the difference that changes behaviour; where an equivalent exists, refine or reopen the existing issue.
6. **Grill the candidate before proposing it.** Try to knock it down: is the mechanism recurrent or high-severity? Does it generalise past the incident? After the decomposition into trigger, action and form, is there any new behaviour left that no active rule already implies? Does it have an identifiable scope? Does it produce verifiable behaviour? What is the **strongest argument against** making it permanent? This is not an absolute gate: a weak, experimental or overly specific candidate can still be raised when there is value in putting it to your judgement — but the weakness must appear in the issue's context and in the recommendation. You decide whether it gets in.
7. **Approval has two paths, and only two.** A candidate the **agent** discovered carries no normative force until it is approved and committed: the standard form is `Implement issue #<number>`, and "looks good", "nice" or "makes sense" are not approval. When **you** state the decision in chat — "add this to the imperatives", "change the imperative to", "remove that imperative" — the instruction itself is the approval: the agent opens the issue to preserve the history and implements it immediately, without asking again. An exploratory comment — "maybe this should be a rule", "is it worth it?" — is discussion, not ratification. And approval applies to the issue's content at that moment: if the proposal changes materially afterwards, it needs approval again.
8. **Until it is implemented, the candidate belongs to the agent.** Editing the title, body, wording and scope; switching between `add`, `modify` and `remove`; closing as `not planned` or `duplicate`; reopening on new evidence — all without asking. What it may not do is turn an issue into a proposal unrelated to the original: then it closes the old one and opens another. Deleting is only for an issue created by accident, empty, an exact duplicate with no context of its own, or one that recorded something sensitive. A change of mind **closes**; it does not delete.
9. **An implemented issue is history.** Once it has produced a normative commit on the default branch it stops being a malleable candidate and becomes the record of where the rule came from. Do not materially rewrite it and do not delete it — the only exception is sanitising sensitive information that should never have been recorded.
10. **Labels: `imperative` plus exactly one of `add`, `modify` and `remove`.** No others, and no status label: the issue's state is the status — open is a candidate, closed by the commit is implemented, `not planned` is rejected, `duplicate` is duplicated.

## Execution

11. **Never invent a process, an authority or an access.** When the path, the owner or the permission is not established, say you do not know and ask. A plausible process stated with confidence is worse than the question, because the next person treats it as established.
12. **Use `git` and `gh` from the terminal.** Never the GitHub MCP.
13. **A normative commit goes straight to the default branch and touches only this file.** No branch, no pull request, no `--amend`, no force-push. One approved issue produces exactly one commit, and it carries no second normative decision. The README, the issue template and the GitHub configuration are **outside** the normative flow: they change only when you ask for it directly.
14. **Follow the commit contract.** Subject `(ADD) Add <title>`, `(MOD) Update <title>` or `(DEL) Remove <title>`. Body with one executive `Reason:` line and `Closes #<number>`. No AI trailer, no `Co-Authored-By`, no tool name, no emoji, no reproducing the issue — the detailed context is the issue. Only claim the rule is implemented after confirming all three: commit on the remote, issue closed, change present in the file.
15. **A credential never enters a file, an issue or a commit.** If one appears, say it has to be rotated and do not repeat the value.

---

# Hypothetical Imperative

16. **When you need an access:** verify that it exists **in this session**, with a command, before planning on top of it. Access that existed yesterday, or that a document mentions, is not access: the permission may have changed and the session may have expired. And when the delivery ends in a step requiring a permission you may not have, check at the start — a denial discovered at the last step turns finished work into stalled work.
17. **When an instruction contradicts an active rule:** do not comply silently and do not refuse. Name the rule, cite its number, diagnose why it is being contradicted, and propose a resolution: **narrow the scope** (the rule is right and too broad — and the new boundary must be a statement about the world, not about the case at hand), **make a one-off exception** (the rule is right and the file does not change), **change it** (wrong on the merits) or **remove it**. Present this before executing, not after delivering.
18. **When you open, refine or discard an autonomous candidate:** report it in **one line at the end of the response**, with a recommendation — never mid-task, and never divert the main answer into discussing normative memory. The exception is a candidate that reveals a conflict with the action under way, which interrupts immediately. `Normative memory: issue #<n> opened. I recommend implementing; options: implement, adjust or discard.`
