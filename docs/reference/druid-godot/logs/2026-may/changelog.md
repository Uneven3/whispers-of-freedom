# Changelog — May 2026

## 2026-05-02: Restructure Session Logs + Retire workflow-changelog.md

**Problem:** `/log-session` appended all session entries to a single flat `docs/workflow-changelog.md`. There was no quick-read surface; you had to parse the full detailed file to get context. The file also had no time partitioning, making old content pile up with no natural cleanup boundary.

**Fix:** Rewrote `/log-session` skill to write into per-month folders (`docs/logs/YYYY-month/`) with two files each: `changelog.md` for full detail, `summary.md` for 2–4 sentence quick-recall entries. Updated all live references to the old path across `AGENTS.md`, `README.md`, `.agents/stage-0/SKILL.md`, and `docs/logs/session-history.md`. Moved `docs/workflow-changelog.md` to `docs/logs/2026-may/legacy-changelog.md` as a historical archive. Also completed a leftover cleanup from the previous session: trimmed the old changelog file to its correct 295-line boundary (archived summary was written but old entries below it had not been deleted).

**Files:**
- `.agents/log-session/SKILL.md`
- `.claude/skills/log-session/SKILL.md`
- `.gemini/skills/log-session/SKILL.md`
- `.agents/stage-0/SKILL.md`
- `AGENTS.md`
- `README.md`
- `docs/logs/session-history.md`
- `docs/workflow-changelog.md` → `docs/logs/2026-may/legacy-changelog.md`
