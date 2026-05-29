# Two-AI Collaboration Protocol

Two AIs collaborate on this codebase: **R (Reviewer/Architect)** and
**E (Executor)**. This file is the contract; everything else in `handoff/`
follows from it.

## Roles

| Role | Writes | Owns |
|---|---|---|
| **R** | spec.md, review.md, answer.md, FOR_E.md | architecture decisions, step gating |
| **E** | report.md, question.md, source code, commits | implementation, git state |

R never edits source code or runs `git commit`. E never modifies this file or
the loop files (`EXECUTOR_LOOP.md`, `REVIEWER_LOOP.md`).

## Files

```
handoff/
  PROTOCOL.md           ← rules (this file, R-owned, written once)
  ARCHITECTURE.md       ← project invariants (R, persistent)
  REQUIREMENTS.md       ← authoritative user requirements (R, synced)
  EXECUTOR_LOOP.md      ← E's standing instructions (R, persistent)
  REVIEWER_LOOP.md      ← R's standing instructions (R, persistent)
  INDEX.md              ← status tracker, both append
  step-N-spec.md        ← R: what to do this step
  step-N-report.md      ← E: what E did + results
  step-N-review.md      ← R: LGTM or needs-revision
  step-N-question.md    ← E: blocked, needs R (transient)
  step-N-answer.md      ← R: answer to E's question
  FOR_E.md              ← R: mid-step redirect (E consumes & deletes)
  .halt                 ← flag, either side sets, E checks at loop head
```

## Standard cycle

```
R writes step-N-spec.md
       ↓
E reads spec, applies, builds, tests, commits
       ↓
E writes step-N-report.md
       ↓
R reads report + git diff, writes step-N-review.md
       ↓
LGTM → R writes step-(N+1)-spec.md
needs-revision → E fixes, new commits, updated report
```

## FOR_E.md (mid-cycle mailbox)

When R notices something during E's work that E should know **before**
finishing the current step, R writes `FOR_E.md`. E must `cat handoff/FOR_E.md`
at the top of every iteration (each significant action / each test cycle).
After acting on it, E **deletes it** and records "consumed FOR_E.md at
<time>" in the current report draft.

## Question / halt flow

When E hits an architectural question or repeated failure:

1. E writes `step-N-question.md` describing the block, evidence, and 2–3
   candidate directions for R to choose from.
2. E touches `handoff/.halt` and exits.
3. R reads the question, decides, writes `step-N-answer.md`, clears
   `.halt`, removes the question file.
4. E resumes on next launch and reads the answer.

E should **not** halt on the first acceptance failure. Retry the same
failure family at most 3 times, then halt with a question.

## Standing rules (project-agnostic)

- E commits on a working branch only. Never `git push origin` unless a
  spec explicitly says to.
- E never modifies the protocol/loop docs. R never edits source files
  under `src/` (or your project's equivalent).
- Each step's commits are prefixed `[step-N]` for traceability.
- E never `git add -A` / `git add .` — add specific files only, so
  unrelated WIP from the user doesn't ride along.
- Both agents may freely read everything in the workspace.
- Both agents may freely read all `handoff/` files. Writes follow the
  owner table above.

## Standing rules (project-specific)

> Replace this section with hard "never" rules for your domain. Examples:
> - Never modify `<critical_module.cpp>`.
> - Never enable `<dangerous_flag>=true`.
> - Never introduce a runtime dependency on simulation-only data.
> - Never change the public message interface between component X and Y.

Add as many as your project actually has. These are the rules that should
trigger an immediate halt + question if a spec ever asks for them.
