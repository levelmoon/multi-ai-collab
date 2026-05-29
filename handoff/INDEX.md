# Collaboration status

Authoritative refs:
- Protocol: `PROTOCOL.md`
- Architecture: `ARCHITECTURE.md` *(project-specific, R writes)*
- Requirements: `REQUIREMENTS.md` *(project-specific, R syncs)*
- Halt switch: `touch handoff/.halt` (either side)

## Status lines

Append new lines as states change. Older lines stay as history. The newest
line per step wins.

```
step-N | spec=YYYY-MM-DD✓ | apply=⏳ | report=⏳ | review=⏳ | commits=- | branch=<branch> | notes=...
```

Symbols: `✓` done, `⏳` pending, `✗` failed/rejected, `→` in progress.

## Currently waiting on

> One sentence: whose turn it is and what they're doing. Update when status
> changes. Example:
>
> *E is applying step-2 (committed_path scaffolding); R idle until report.*

## History

> Optional: dated notes for important context shifts. Example:
>
> - 2026-05-27 16:00 — Initial setup, baseline commit `<sha>`.
> - 2026-05-28 11:20 — R caught E modifying candidate generation; wrote
>   FOR_E.md to revert; E recovered.
