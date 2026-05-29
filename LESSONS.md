# Lessons learned

Nine patterns and mistakes from the 4-day refactor this template was extracted
from. Skim before you start — most of them cost real time when ignored.

## 1. Use base64 for writes that cross encoding layers

Writing UTF-8 markdown from your IDE assistant through PowerShell, then through
SSH, then through bash is a tour through every encoding bug ever filed.
Chinese characters become `?`, emoji become mojibake, parentheses break quoting.

Reliable pattern:

```powershell
$content = @'
multi-line UTF-8 content with whatever characters
'@
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
ssh user@host "echo $b64 | base64 -d > /target/path"
```

You won't believe how much time this saves until you don't use it for the
first hundred files.

## 2. Agent self-loops are not as autonomous as they look

Most "agent in a chat panel" UIs (Codex, Cursor, VS Code Claude) don't truly
loop indefinitely between turns. They finish a batch and stop, waiting for
user input. The `FOR_E.md` mailbox + the user occasionally relaying nudges is
what keeps the loop *practically* going. Don't design as if the agent will
self-resume forever — design for "one batch then stop", and let the next
batch start fresh by re-reading the standing docs.

## 3. Event-driven beats timer-driven

A fixed `wake every N minutes` timer in R's harness tends to fire when the
user has switched away from R's window (the harness suspends the timer when
the window isn't foreground). An SSH-tail watcher running as a child process
keeps producing events even while the harness is backgrounded — the events
queue and get delivered when R's window comes back.

The watcher also lets R *do nothing* when E is doing nothing, instead of
waking up just to check and go back to sleep.

## 4. Sim = real is non-negotiable

The single most expensive bug we caught: E was about to pipe a simulation-
only ground-truth signal into the runtime code path "just to make the
dynamic-obstacle scenario pass." Catching that was the most valuable
architectural call of the project.

Rule: anything that's only available in simulation **does not exist** from
the runtime code's perspective. If sim has an oracle the real system can't
replicate, the planner / runtime / whatever's responsibility is to
**degrade gracefully without it**, not to use it.

This applies to obstacle velocities, ground truth poses, sim-only message
fields, anything.

## 5. "Whack-a-mole" is a signal to step back, not patch faster

When fixing one symptom keeps surfacing another, the symptoms share a
root cause that the current architecture is masking. Three good prompts
to stop and rethink:

- "Each fix I do generates a new failure on a different scenario."
- "I just added the third special case for X."
- "The metric passes but the human reviewing the visualization still
  doesn't like it."

In our case, the third one — the user looking at RViz and saying "this
still feels wrong despite passing the tests" — was the trigger to
discover a `yaw ↔ perception ↔ plan` feedback loop and a
"per-frame recompute" jitter source. Fixing those instead of adding more
cost terms is what finally produced smooth behavior.

## 6. Measure what you actually want, not what's easy

Acceptance tests measure what they measure. If you don't measure
*smoothness*, *jitter*, *hesitation*, *yaw rate* — the agent will
optimize for the metrics that exist and you'll end up with paths that
pass acceptance but feel unstable.

Always check: "if I only saw the numbers in this report, would I
conclude the behavior is good?" If not, the report needs new metrics,
not just more tuning.

## 7. Hysteresis as soft bias > state machine as separate code paths

We almost re-introduced a 4-state explicit mode machine to fix
oscillation. The cleaner answer was a tiny `phase_` variable that only
added cost biases to the unified scorer (not separate plan-generation
code paths) and that drove re-plan triggers, not per-frame choices.

Same hysteresis effect, far simpler implementation. State as a soft
input to a unified scorer beats state as a control-flow fork every time.

## 8. Commit-and-follow beats recompute-every-frame

Re-planning from scratch every cycle on slightly changed inputs produces
a slightly different plan every cycle — which feels like "jitter" to
the human, even if every individual cycle is locally optimal.

The architecture fix was to **commit** to a plan and only re-plan on
bounded triggers (safety, deviation, externally-mandated change), not
every cycle. This is also a perception-loop breaker: when the plan is
stable, the things it implies (yaw, FOV, observed inputs) are stable,
the next plan is stable. Stability becomes self-reinforcing instead of
self-disturbing.

## 9. Production-Ready gates need margin

If your hard safety threshold is `clearance ≥ 0.15`, set the
Production-Ready gate at `≥ 0.20`. The extra 5cm pays for real-world
localization drift, mechanical tolerance, environmental disturbance,
and the difference between simulated and actual sensor noise.

Same idea for any "performance" threshold (latency, throughput, error
rate) — leave margin between the simulation gate and the real-world
hard limit, because the real world is always noisier and busier than
simulation.

## Bonus: commit hygiene matters when other WIP is around

If the user is editing unrelated files in the same workspace (the case
in our project — a file from a different subsystem was open in their
IDE), `git add -A` will silently mix that WIP into your refactor commit.
Always add specific files. Make this an explicit instruction in
`EXECUTOR_LOOP.md`.
