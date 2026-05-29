# Multi-AI Pair Collaboration Pattern (R + E)

A reusable, file-based mailbox protocol for letting two AI agents collaborate on a
substantial software task — one acts as **Reviewer/Architect (R)** and the other as
**Executor (E)** — with each operating in its own host/IDE and communicating
through a shared `handoff/` directory.

Distilled from a real 4-day drone local-path-planner refactor where this pattern
turned a "whack-a-mole bug fixing" loop into a stable, observable, and ultimately
production-ready collaboration.

---

## TL;DR

- **R** reads code, writes specs and reviews. Read-only on the workspace. No
  source edits, no commits.
- **E** writes code, runs builds/tests, commits. Self-drives via spec files.
  Halts and asks when stuck.
- Shared `handoff/` dir is the only channel. Files there have **single-direction
  ownership** — each is written by exactly one role.
- Two patterns make this work in practice:
  1. **`FOR_E.md` mailbox** — R drops messages here mid-task; E polls before every
     iteration and consumes (deletes after acting).
  2. **Event-driven Monitor** on R's side — a background SSH-tail watches the
     workspace for new commits / questions / halts and wakes R immediately,
     instead of R polling on a fixed timer.

This repository is the **portable starting kit**: protocol docs, loop instruction
templates for both sides, a status tracker, the R-side event watcher, and the
lessons learned that make the pattern actually behave well in practice.

---

## When to use this

This pattern earns its weight when **all** of the following are true:

- The task is **large or open-ended** (refactor, new subsystem, multi-step
  feature) — small one-shots don't need two roles.
- You want one side **driving hands-on iteration** (build, test, commit) and the
  other **gating architectural decisions** asynchronously.
- The two agents **can't easily share a single process / window** (e.g. R is your
  desktop coding assistant; E is a Codex/Cursor agent inside a remote workspace).
- You're OK with **file-based communication + occasional human relay** when one
  side's session ends.

If you have one agent that can do everything fluently in a single hot loop —
just use that. Two-agent pair is for when one role needs persistent local access
and the other needs to step back for judgment.

---

## Architecture

```
   ┌──────────────────┐                      ┌────────────────────┐
   │  R (Reviewer)    │      handoff/        │  E (Executor)      │
   │                  │   <─────────────>    │                    │
   │ • reads code     │  step-N-spec.md      │ • edits source     │
   │ • writes spec    │  step-N-report.md    │ • runs build/test  │
   │ • writes review  │  step-N-review.md    │ • commits          │
   │ • writes FOR_E   │  step-N-question.md  │ • writes report    │
   │ • answers Q's    │  step-N-answer.md    │ • writes question  │
   │                  │  FOR_E.md            │ • polls FOR_E.md   │
   │ has SSH read     │  INDEX.md            │ owns git state     │
   │                  │  PROTOCOL.md         │                    │
   └──────────────────┘                      └────────────────────┘
       │                                              │
       │ event monitor (SSH tail of handoff/+ git)    │
       └──────── wakes R on commit/question/halt ─────┘
```

**Roles**

| Role | What it does | What it never does |
|---|---|---|
| **R (Reviewer/Architect)** | Reads code, writes spec/review/answer, drops FOR_E.md when E goes off-track | Edits source, runs `git add/commit/push`, switches branches |
| **E (Executor)** | Applies spec, builds, runs tests, commits, writes reports, polls FOR_E.md each iteration, writes question.md if stuck | Pushes to origin (unless explicitly asked), changes scope unilaterally, modifies the protocol docs |

**The mailbox (`handoff/`)**

| File | Owner | Lifetime | Purpose |
|---|---|---|---|
| `PROTOCOL.md` | R writes once | persistent | Rules of engagement |
| `ARCHITECTURE.md` | R | persistent | Project-specific invariants |
| `REQUIREMENTS.md` | R | persistent (synced) | Authoritative user requirements |
| `EXECUTOR_LOOP.md` | R writes once | persistent | E's standing instructions |
| `REVIEWER_LOOP.md` | R writes once | persistent | R's standing instructions |
| `STARTUP_E.md` | R writes once | persistent | One-shot launch prompt for E |
| `INDEX.md` | both append | persistent | Status tracker (per-step lines) |
| `step-N-spec.md` | R | persistent | What to do this step |
| `step-N-report.md` | E | persistent | What E did + results |
| `step-N-review.md` | R | persistent | LGTM or needs-revision |
| `step-N-question.md` | E | transient | E is blocked, needs R |
| `step-N-answer.md` | R | persistent | R's answer; E reads then resumes |
| `FOR_E.md` | R | **consumed by E** | Mid-task redirect / clarification |
| `.halt` | either | flag | E checks at loop head; if present, stop |

---

## Protocol files (templates)

Drop these into `<workspace>/handoff/` and adapt the bracketed bits to your
project. They are written to be read top-to-bottom by either agent without prior
context.

### `PROTOCOL.md`

````markdown
# Two-AI Collaboration Protocol

Two AIs collaborate on this codebase: **R (Reviewer/Architect)** and **E (Executor)**.
This file defines the rules; everything else in `handoff/` follows from these.

## Roles

| Role | Writes | Owns |
|---|---|---|
| **R** | spec.md, review.md, answer.md, FOR_E.md | architecture decisions, gating |
| **E** | report.md, question.md, source code, commits | implementation, git state |

R never edits source code or runs `git commit`. E never changes the protocol
docs or the spec files.

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

## The FOR_E.md mailbox (mid-cycle channel)

Used when R notices something during E's work that E needs to know
*before* finishing the current step. E **must** `cat handoff/FOR_E.md` at
the top of every iteration (each probe / each significant change). After
acting on it, E deletes it and records "consumed FOR_E.md at <time>" in
its current report draft.

## Blocking flow

If E hits an architectural question or repeated failure:

1. E writes `step-N-question.md` describing the block, evidence, and 2–3
   candidate directions.
2. E touches `handoff/.halt` and exits.
3. R reads the question, decides, writes `step-N-answer.md`, clears
   `.halt` (and removes the question file).
4. E resumes on next launch.

## Standing rules (project-agnostic)

- E commits on a working branch only. Never `git push` unless a spec
  explicitly says to.
- Never modify the protocol docs (PROTOCOL, EXECUTOR_LOOP, REVIEWER_LOOP,
  REQUIREMENTS) without R's explicit instruction.
- Both agents may freely read everything in the workspace.
- Each step's commits should be prefixed `[step-N]` for traceability.

## Standing rules (project-specific)

[Replace this section with hard "never" rules for your domain — e.g.
"never modify `flight_controller.cpp`", "never enable
`auto_takeoff_enable=true`", "never introduce a fake-only data path",
etc.]
````

### `REQUIREMENTS.md`

The authoritative log of what the user actually wants. R is responsible for keeping
this current — when the user clarifies or updates a requirement during a
conversation with R, R writes it here so E sees the latest at the next iteration.

```markdown
# REQUIREMENTS — Authoritative user requirements

Last updated: <date>. R is responsible for syncing this when user gives new
or revised requirements.

## §1 Goal
[The final acceptance criterion the user actually cares about, e.g.
"simulation passing = production-ready deployment on real hardware,
no further code changes required."]

## §2 Generality
[Hard rules against scenario-specific hacks, e.g. "no per-scenario
parameter tuning — one set of weights/thresholds must clear every
acceptance scenario."]

## §3 Domain constraints
[Project-specific physical/operational constraints, e.g.
yaw policy, control interface contract, what the agent must never
assume from simulation that real perception cannot provide.]

## §4 Safety boundaries
[Things that are absolutely off-limits, with reasons.]

## §N Acceptance gates
[Concrete numeric thresholds that mean "this is done".]
```

### `EXECUTOR_LOOP.md`

E's persistent standing instructions. E should re-read this at the start of
every fresh session.

````markdown
# EXECUTOR_LOOP — Standing instructions for E

You are E (Executor). You work in `<WORKSPACE_PATH>`. Your collaborator R
gives you specs and feedback through `handoff/`. You apply them, build/test,
commit, and report.

## Mandatory rule: poll FOR_E.md before every iteration

Before changing any code, before running any build/test, before committing:

```bash
cat handoff/FOR_E.md 2>/dev/null && echo "--- R has a new message above; act on it then delete FOR_E.md ---"
cat handoff/INDEX.md | tail -25
```

If `FOR_E.md` exists, read it, act on it, then `rm handoff/FOR_E.md` and note in
your current step's report that you consumed it.

## Loop body (single iteration)

```
while true:
    if exists(handoff/.halt): exit
    consume_FOR_E_if_present()
    read INDEX.md → identify current step

    if current step-N has spec but no report:
        apply spec
        build + run unit tests + run scenario suite
        if all acceptance gates pass:
            git commit -m "[step-N] <short description>"
            write step-N-report.md (commits, build summary, test summary,
                deviations, observations)
            append status line to INDEX.md
            continue to next step
        elif retried this step ≥ 3 times with same failure family:
            write step-N-question.md (block description, evidence,
                candidate directions)
            touch handoff/.halt
            exit
        else:
            analyze failure, refine, retry
    sleep N seconds
```

## Autonomous mode (commit without waiting for R LGTM)

If `step-N-review.md` is not yet written when your acceptance passes, do
not block — commit, write your report, and proceed to step-N+1 if its
spec exists. R's review is async; if R finds issues, R writes `FOR_E.md`
and you fix on the next iteration (which may include a follow-up commit).

The branch is never auto-pushed; bad intermediate commits are cheap to
revert. The real safety boundary is the final Production-Ready gate plus
the user's manual review, not R's per-step approval.

## Commit hygiene

- Only `git add` files actually relevant to the current step. **Never
  `git add -A` or `git add .`** — unrelated WIP from the user must not
  ride along.
- Each step's commit message starts with `[step-N]`.
- Do not amend or rebase published commits.
- Do not `git push origin` unless a spec explicitly tells you to.

## Hard constraints

[Insert project-specific "never" rules from REQUIREMENTS §4 here, e.g.
"never modify `<path>`", "never enable `<flag>=true`", "never introduce
a simulation-only oracle into the runtime data path".]

## When you are stuck

Before halting, try this in order:
1. Re-read `step-N-spec.md`, `REQUIREMENTS.md`, the latest `FOR_E.md`.
2. Try the most conservative variation of your approach.
3. If you've retried the same failure family ≥ 3 times, **stop and write
   `step-N-question.md`**. Describe what you tried, what evidence you
   have, and what concrete options R could choose between. Then touch
   `.halt` and exit. Don't keep blindly tuning.
````

### `REVIEWER_LOOP.md`

R's persistent standing instructions. Read these when starting fresh / after a
break.

````markdown
# REVIEWER_LOOP — Standing instructions for R

You are R (Reviewer/Architect). You have read-only access to
`<WORKSPACE_PATH>` (typically over SSH to <E_HOST_IP>). You never edit
source code, never run `git commit`. You write spec / review / answer
files in `handoff/`.

## When you wake (event or user ping)

1. `ssh <user>@<E_HOST_IP> 'cat <WORKSPACE>/handoff/INDEX.md | tail -25'`
2. Quick state check:
   ```bash
   ssh ... 'test -f .../handoff/.halt && echo HALT
            git -C <WORKSPACE> log --oneline -3
            ls -t <WORKSPACE>/<log_dir>/ | head -3'
   ```
3. Decide which file to write:
   - new `step-N-report.md` and no `step-N-review.md` → write review
   - new `step-N-question.md` → write `step-N-answer.md` + clear .halt
   - E going off-track mid-step (regression in metrics, scope creep,
     touching forbidden files) → write `FOR_E.md`
   - LGTM already given but no `step-(N+1)-spec.md` yet → write next spec
   - none of the above → do nothing, stay idle

## What goes in a review

- Verdict (`LGTM` or `needs-revision`).
- Per-spec-item checklist (✓/✗ against the spec's "What" list).
- Commit hygiene check (no out-of-scope files, no `git push origin`,
  no protected files touched).
- Gate metrics check against acceptance.
- Open observations / non-blocking notes.
- For LGTM: "trigger next step" line; for needs-revision: explicit
  file:line + before/after expected.

## What goes in FOR_E.md (mid-step)

Use when you need to interrupt or steer E mid-task. Be precise: file:line
references, exact commands to run, concrete numeric thresholds. End with
"消费完删除本文件" so E knows to remove it after acting.

## Hard constraints

- Never run `git add/commit/push` yourself.
- Never edit source files in `<WORKSPACE>/src/...`.
- Never modify the protocol docs without flagging it explicitly.
- If unsure whether a decision is yours to make, ask the user.

## Anti-patterns to catch in review

- E started touching files outside the current step's scope.
- E loosened an acceptance threshold to pass instead of fixing the code.
- E introduced a per-scenario branch / parameter.
- E built a runtime dependency on simulation-only data.
- E added complexity (state machines, retry logic, fallbacks) where the
  spec didn't ask for it.

These warrant a `needs-revision` even if metrics technically pass.
````

### `INDEX.md` (status tracker)

Both R and E append to this. Keep entries short — one line per status change.

```markdown
# Collaboration status

Authoritative refs:
- Protocol: `PROTOCOL.md`
- Architecture: `ARCHITECTURE.md`
- Requirements: `REQUIREMENTS.md`
- Halt switch: `touch handoff/.halt`

## Status lines

step-N | spec=YYYY-MM-DD✓ | apply=⏳ | report=⏳ | review=⏳ | commits=- | branch=<refactor-branch> | notes=...

[Append new lines as states change; older lines stay as history. The newest
line for each step wins.]

## Currently waiting on

[One sentence: who's turn it is and what they're doing.]
```

### `STARTUP_E.md` (one-shot launch prompt)

The exact text the user pastes into E's first conversation to bring it up to
speed. Make it complete — E should be able to start cold from this alone.

````markdown
# STARTUP_E

Paste the block between `=== BEGIN ===` and `=== END ===` into a fresh E
agent session (e.g. a new Codex agent chat with terminal access).

=== BEGIN ===

You are E (Executor) for this project. Before doing anything else:

```bash
cat <WORKSPACE>/handoff/PROTOCOL.md
cat <WORKSPACE>/handoff/REQUIREMENTS.md
cat <WORKSPACE>/handoff/EXECUTOR_LOOP.md
cat <WORKSPACE>/handoff/INDEX.md
cat <WORKSPACE>/handoff/FOR_E.md 2>/dev/null
```

Then identify the current step from INDEX.md, read its spec, and begin
the loop body described in EXECUTOR_LOOP.md.

Reminders:
- `cat FOR_E.md` before every iteration. Consume + delete after acting.
- Commit with `[step-N]` prefix; never `git add -A`.
- If stuck for ≥ 3 retries on the same failure family, write
  `step-N-question.md` and `touch handoff/.halt`.

=== END ===
````

---

## R-side event Monitor (event-driven wake)

In practice, R doing fixed-interval polling (e.g. every 15 min) burns tokens on
empty checks and is slow to catch problems. Better: a small bash watcher on
**E's host** that emits one line each time something meaningful happens —
new commit, new question file, halt flag, or no activity for X minutes.

R wires that line stream into a foreground SSH tail; each line becomes a
wake-up event in R's agent harness. R only consumes tokens when E has actually
done something.

### `r_watch.sh` (drop on E's host, e.g. `/tmp/r_watch.sh`)

```bash
#!/bin/bash
# R event detector: emits only on checkpoint events (commit / question /
# halt / extended idle). Dedupes question/halt so one appearance = one event.
set -u
WORKSPACE=${WORKSPACE:-<WORKSPACE_PATH>}
HANDOFF=$WORKSPACE/handoff
LOG_DIR=${LOG_DIR:-$WORKSPACE/<your_logs_dir>}
IDLE_TIMEOUT_SEC=${IDLE_TIMEOUT_SEC:-1200}

cd "$WORKSPACE" || exit 1
LAST_HEAD=$(git log --oneline -1 2>/dev/null)
LAST_PROBE=$(ls -t "$LOG_DIR" 2>/dev/null | head -1)
LAST_PROBE_TS=$(date +%s)
IDLE_NOTIFIED=0
Q_SEEN=0
HALT_SEEN=0

echo "R_WATCH_START $(date +%H:%M:%S) baseline_head=$LAST_HEAD"

while true; do
  echo "R-monitor alive $(date +%H:%M:%S) pid=$$" > /tmp/r_heartbeat

  HEAD=$(git log --oneline -1 2>/dev/null)
  if [ -n "$HEAD" ] && [ "$HEAD" != "$LAST_HEAD" ]; then
    LAST_HEAD="$HEAD"
    echo "COMMIT_NEW $HEAD"
  fi

  Q=$(ls "$HANDOFF"/step-*-question.md 2>/dev/null | head -1)
  if [ -n "$Q" ]; then
    [ "$Q_SEEN" -eq 0 ] && { Q_SEEN=1; echo "QUESTION_FILE $Q"; }
  else
    Q_SEEN=0
  fi

  if [ -f "$HANDOFF/.halt" ]; then
    [ "$HALT_SEEN" -eq 0 ] && { HALT_SEEN=1; echo "HALT_FLAG"; }
  else
    HALT_SEEN=0
  fi

  NEWP=$(ls -t "$LOG_DIR" 2>/dev/null | head -1)
  NOW=$(date +%s)
  if [ "$NEWP" != "$LAST_PROBE" ]; then
    LAST_PROBE="$NEWP"; LAST_PROBE_TS=$NOW; IDLE_NOTIFIED=0
  else
    GAP=$((NOW - LAST_PROBE_TS))
    if [ "$GAP" -gt "$IDLE_TIMEOUT_SEC" ] && [ "$IDLE_NOTIFIED" -eq 0 ]; then
      IDLE_NOTIFIED=1
      echo "E_IDLE no new probe ${GAP}s"
    fi
  fi
  sleep 30
done
```

### R-side wiring

R runs (in a background monitor task in its harness, with auto-reconnect):

```bash
while true; do
  ssh -o ServerAliveInterval=30 <user>@<E_HOST_IP> "bash /tmp/r_watch.sh" 2>&1 \
    | grep --line-buffered -vE "post-quantum|store now"
  echo "SSH_DROPPED reconnecting $(date)"
  sleep 5
done
```

Each non-noise stdout line becomes a wake-up event. R reads the event line,
SSHs in for details if needed, writes the appropriate file in `handoff/`,
and goes back idle.

### Heartbeat (so the user can verify R is listening)

`r_watch.sh` writes a timestamp to `/tmp/r_heartbeat` every loop. The human in
the loop can check `cat /tmp/r_heartbeat` at any time to confirm R's listener
is alive without bothering R.

---

## Setup checklist

1. **Decide hosts.** Typically R runs on your laptop (in your IDE assistant
   panel), E runs on the remote workstation/Jetson/cloud VM where the source
   lives. R needs SSH read access to E's host.
2. **Create the mailbox.** `mkdir -p <WORKSPACE>/handoff/` on E's host.
3. **Drop the protocol templates.** Copy the files above into `handoff/`,
   adapting bracketed placeholders.
4. **Write project-specific docs.** Fill in `ARCHITECTURE.md` and
   `REQUIREMENTS.md` with the actual user goals, invariants, and constraints.
5. **Drop the watcher.** Copy `r_watch.sh` to E's host (e.g. `/tmp/`) and
   wire R's side to it via the SSH-tail loop above.
6. **Launch E.** Open a fresh agent session for E and paste in `STARTUP_E.md`.
7. **Brief R.** Make sure R's session has read the protocol docs once
   (alternatively: paste the URL to this README into R's first message).

After this, the steady state is:
- R is idle most of the time, woken by events.
- E grinds autonomously inside its session, polling `FOR_E.md` each iteration.
- The user occasionally relays nudges when E's agent session ends and needs
  to be re-engaged.

---

## Customization

The **collaboration mechanism** in this repo is the durable part. The
**project-specific** parts live in three files and should be rewritten per
project:

| File | What to swap |
|---|---|
| `ARCHITECTURE.md` | Your project's invariants, contracts with other systems, "out of scope" boundaries |
| `REQUIREMENTS.md` | The user's actual goals + safety boundaries + acceptance thresholds |
| `PROTOCOL.md`'s "Standing rules (project-specific)" section | Hard "never" rules for your domain |

Everything else (`EXECUTOR_LOOP.md`, `REVIEWER_LOOP.md`, `STARTUP_E.md`, the
status tracker shape, the watcher, the FOR_E mailbox convention) generalizes.

---

## Lessons learned (the painful kind)

These are the patterns and mistakes that turned out to matter most. Skim them
before adapting.

### Use base64 for writes that cross encoding layers

Writing UTF-8 markdown from your IDE assistant through PowerShell, then through
SSH, then through bash heredocs is a tour through every encoding bug ever
filed. Chinese characters become `?`, emoji become mojibake, parentheses break
quoting.

The reliable pattern is to base64-encode locally, decode on the remote:

```powershell
$content = @'
multi-line UTF-8 content with whatever characters
'@
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
ssh user@host "echo $b64 | base64 -d > /target/path"
```

You won't believe how much time this saves until you don't use it for the
first hundred files.

### Agent self-loops are not as autonomous as they look

Most "agent in a chat panel" UIs (Codex, Cursor, VS Code Claude) don't truly
loop indefinitely between turns. They finish a batch and stop, waiting for
user input. The `FOR_E.md` mailbox + the user occasionally relaying nudges is
what keeps the loop *practically* going. Don't design as if the agent will
self-resume forever — design for "one batch then stop", and let the next
batch start fresh by re-reading the standing docs.

### Event-driven beats timer-driven

A fixed `wake every N minutes` timer in R's harness tends to fire when the
user has switched away from R's window (the harness suspends the timer when
the window isn't foreground). An SSH-tail watcher running as a child process
keeps producing events even while the harness is backgrounded — the events
queue and get delivered when R's window comes back.

The watcher also lets R *do nothing* when E is doing nothing, instead of
waking up just to check and go back to sleep.

### Sim = real is non-negotiable

The most expensive bug in our 4-day refactor was a moment when E was about
to pipe a simulation-only ground-truth signal into the runtime code path
"just to make the dynamic-obstacle scenario pass." Catching that as R was
the single most valuable architectural call of the project.

Rule: anything that's only available in simulation **does not exist** from
the planner / runtime code's perspective. If sim has an oracle the real
system can't replicate, the planner's responsibility is to **degrade
gracefully without it**, not to use it.

This applies to obstacle velocities, ground truth poses, sim-only message
fields, anything.

### "Whack-a-mole" is a signal to step back, not patch faster

When fixing one symptom keeps surfacing another, that means the symptoms
share a root cause that the current architecture is masking. Three good
prompts to step back:
- "Each fix I do generates a new failure on a different scenario."
- "I just added the third special case for X."
- "The metric passes but the human reviewing the visualization still
  doesn't like it."

In our case, the third one — the user looking at RViz and saying "this
still feels wrong despite passing the tests" — was the trigger to step
back and realize there was a `yaw ↔ perception ↔ plan` feedback loop and
a "per-frame recompute" jitter source. Fixing those instead of adding
more cost terms is what finally produced smooth behavior.

### Measure what you actually want, not what's easy

Acceptance tests measure what they measure. If you don't measure
*smoothness*, *jitter*, *hesitation*, *yaw rate* — the agent will
optimize for the metrics that exist and you'll end up with paths that
pass acceptance but feel unstable. Always check: "if I only saw the
numbers in this report, would I conclude the behavior is good?" If not,
the report needs new metrics, not just more tuning.

### Hysteresis as soft bias > state machine as separate code paths

We almost re-introduced a 4-state explicit mode machine to fix oscillation.
The cleaner answer was a tiny `phase_` variable that only added cost
biases to the unified scorer (not separate plan-generation code paths)
and that drove re-plan triggers, not per-frame choices. Same hysteresis
effect, far simpler implementation.

### Commit-and-follow > recompute-every-frame

Re-planning from scratch every control cycle on slightly changed inputs
produces a slightly different path every cycle — which feels like
"jitter" to the human, even if every individual frame is locally
optimal. The architecture fix was to **commit** to a path and only
re-plan on bounded triggers (safety, extend, deviation, global change),
not every frame.

This is also a perception-loop-breaker: when the path is stable, the
yaw it implies is stable, the camera direction is stable, the depth
input is stable, the next plan is stable. Stability becomes self-
reinforcing instead of self-disturbing.

### Production-Ready gates need margin

If the acceptance threshold is `min_clearance ≥ 0.15`, set the
Production-Ready gate at `≥ 0.20`. The extra 5cm pays for real-world
localization drift, arm radius, wind disturbance, and the difference
between simulated and actual depth noise. Same for `p95 < 80ms` vs the
hard limit at 100ms — leave margin for the on-board CPU being busier
than the test machine.

### Commit hygiene matters when other WIP is around

If the user happens to be editing unrelated files in the same workspace
(the case in our project — `surfel_map.cpp` from a different subsystem),
`git add -A` will silently mix that WIP into your refactor commit. Always
add specific files. Make this an explicit instruction in `EXECUTOR_LOOP.md`.

---

## Credits & origin

This pattern was extracted from a 4-day collaboration where an R agent
(Claude Code in a desktop IDE) and an E agent (Codex in a Remote-SSH
VS Code window connected to a Jetson) successfully completed a 2900-line
refactor of a drone local-path planner, taking it from a stalled
"whack-a-mole" state to passing all 11 simulation scenarios at the
Production-Ready gate, with end-to-end path-output jitter of essentially
zero across every scenario.

The repository is intended as a starting kit — the protocol files and
the watcher script will save someone a lot of trial-and-error. The
lessons-learned section will save them even more.

## License

MIT. Use it, fork it, improve it. If you find a better pattern for one
of the lessons-learned items, please open an issue or PR.
