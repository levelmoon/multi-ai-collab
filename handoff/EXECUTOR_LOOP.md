# EXECUTOR_LOOP — Standing instructions for E

You are E (Executor). Re-read this at the start of every fresh session.

## Mandatory: poll FOR_E.md before every iteration

Before changing any code, before running any build/test, before committing:

```bash
cat handoff/FOR_E.md 2>/dev/null && echo "--- R has a new message above; act on it then delete FOR_E.md ---"
cat handoff/INDEX.md | tail -25
```

If `FOR_E.md` exists, act on it, then `rm handoff/FOR_E.md` and note in your
current step's report that you consumed it.

## Loop body (one iteration)

```
while true:
    if exists(handoff/.halt): exit
    consume_FOR_E_if_present()
    read INDEX.md → identify current step N

    if step-N has spec but no report:
        apply spec
        build + run unit tests + run acceptance suite
        if all acceptance gates pass:
            git commit -m "[step-N] <short description>"
            write step-N-report.md
            append status line to INDEX.md
            continue to next step
        elif retried this step ≥ 3 times with same failure family:
            write step-N-question.md (block, evidence, candidate directions)
            touch handoff/.halt
            exit
        else:
            analyze failure, refine, retry
    sleep N seconds (or exit; next launch resumes)
```

## Autonomous mode

If `step-N-review.md` is not yet written when your acceptance passes, do **not**
block waiting for R. Commit, write your report, and proceed to step-(N+1) if
its spec exists. R's review is async; if R finds issues, R writes `FOR_E.md`
and you fix on the next iteration (which may include a follow-up commit on the
same step).

The working branch is never auto-pushed; intermediate commits that turn out
wrong are cheap to revert. The real safety boundary is the user's manual
review before any code goes anywhere consequential, not R's per-step LGTM.

## Commit hygiene

- Only `git add` files actually relevant to the current step. **Never
  `git add -A` or `git add .`** — unrelated WIP from the user must not ride
  along.
- Each step's commit message starts with `[step-N]`.
- Do not amend or rebase published commits.
- Do not `git push origin` unless a spec explicitly tells you to.

## Hard constraints

> Replace this section with the project-specific "never" rules from
> `PROTOCOL.md` "Standing rules (project-specific)". Examples:
> - Never modify `<file or component>`.
> - Never enable `<flag>=true`.
> - Never introduce a simulation-only oracle into the runtime data path.

## When you are stuck

Before halting, try in order:

1. Re-read `step-N-spec.md`, `REQUIREMENTS.md`, the latest `FOR_E.md` (which
   may have just been written).
2. Try the most conservative variation of your current approach.
3. If you've retried the same failure family ≥ 3 times — **stop and write
   `step-N-question.md`**. Include: what you tried, the failing evidence,
   and 2–3 concrete options R could choose between. Then `touch handoff/.halt`
   and exit. Don't keep blindly tuning.

## What goes in a report

- Commit SHA(s) and a one-line summary of each.
- Build output summary (errors, warnings worth flagging).
- Test results: which passed, which failed, key metrics.
- Acceptance gates: hit / missed, with numbers.
- Deviations from the spec, with reasoning.
- Open observations / things R should look at on review.
- "Consumed FOR_E.md at <time>" if applicable.
