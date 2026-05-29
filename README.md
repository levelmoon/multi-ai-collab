# multi-ai-collab

Two AI agents collaborating on one codebase via a file-based mailbox: one
**Reviewer/Architect (R)**, one **Executor (E)**. Drop the templates into a
project's `handoff/` directory and launch each agent with a one-line prompt.

Battle-tested on a 4-day drone path-planner refactor (2900 LOC, 11 sim
scenarios, Production-Ready gate). The pattern + the gotchas in
[`LESSONS.md`](LESSONS.md) are the durable take-aways.

## Setup (5 minutes)

1. **Copy `handoff/` into your project.**
   ```bash
   cp -r handoff/ /path/to/your-project/
   ```
2. **Fill in project-specific docs.** In your project's `handoff/` you now have
   `PROTOCOL.md`, `EXECUTOR_LOOP.md`, `REVIEWER_LOOP.md`, `INDEX.md`. They are
   generic. You should also add:
   - `REQUIREMENTS.md` — the user's actual goals + safety rules + acceptance
     thresholds. R keeps this current.
   - `ARCHITECTURE.md` — project invariants and contracts with other systems.
   - Append project-specific "never" rules to the bottom of `PROTOCOL.md`.
3. **Drop the R-side event watcher on E's host.**
   ```bash
   scp scripts/r_watch.sh user@<E-HOST>:/tmp/
   # edit WORKSPACE and LOG_DIR at the top to match your project
   ```
4. **Launch E** in a fresh agent session (Codex, Cursor, etc.):
   > 读 `<workspace>/handoff/PROTOCOL.md` 和 `EXECUTOR_LOOP.md`,你是 E,开始干。
5. **Launch R** in your IDE assistant:
   > 读 `<workspace>/handoff/PROTOCOL.md` 和 `REVIEWER_LOOP.md`,我是 R。

That's it. R will idle until E writes a report/question/halt; E will iterate
through the steps polling `FOR_E.md` each cycle.

## Repo layout

```
multi-ai-collab/
├── README.md             ← you are here
├── LESSONS.md            ← 9 gotchas worth reading before you start
├── LICENSE               ← MIT
├── handoff/              ← copy this into your project
│   ├── PROTOCOL.md       ← roles, files, blocking flow, FOR_E mailbox
│   ├── EXECUTOR_LOOP.md  ← E's standing instructions (autonomous mode)
│   ├── REVIEWER_LOOP.md  ← R's standing instructions
│   └── INDEX.md          ← blank status tracker
└── scripts/
    └── r_watch.sh        ← R-side event watcher (runs on E's host)
```

## How it actually works

- **`handoff/`** is the only channel between R and E. Each file has a single
  owner (R or E); see `PROTOCOL.md` for the table.
- **R writes specs and reviews; E writes reports and questions.** R never
  edits source code or runs git. E owns all git operations.
- **`FOR_E.md`** is R's mid-task mailbox. E `cat`s it at the top of every
  iteration, acts on anything found, then deletes it.
- **Halt** = E writes `step-N-question.md` and `touch handoff/.halt` when
  stuck. R answers, removes `.halt`, E resumes.
- **`r_watch.sh`** runs on E's host and emits an event line each time
  something meaningful happens (commit, question file appears, halt flag,
  long idle). R's harness wakes on each line — no fixed-interval polling.

## Customize per project

The mailbox mechanism is reusable as-is. Three files are project-specific:

| File | What you fill in |
|---|---|
| `REQUIREMENTS.md` | The user's real goals, safety boundaries, numeric acceptance gates |
| `ARCHITECTURE.md` | Project invariants, contracts with other components, out-of-scope boundaries |
| `PROTOCOL.md` bottom section | Hard "never" rules specific to your domain |

Everything else (`EXECUTOR_LOOP.md`, `REVIEWER_LOOP.md`, `INDEX.md`,
`r_watch.sh`, the `FOR_E.md` convention, the question/halt protocol)
generalizes.

## Before you start

Read [`LESSONS.md`](LESSONS.md). It's nine specific things that will bite
you otherwise — base64 for UTF-8 over SSH, agents don't truly self-loop,
event-driven vs timer-driven wakes, sim=real as a non-negotiable, when
whack-a-mole means step back, measuring what you actually want, and a
few more.

## License

MIT.
