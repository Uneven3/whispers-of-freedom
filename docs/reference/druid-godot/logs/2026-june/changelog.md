# Changelog — June 2026

## 2026-06-30: Compact Architecture Reading Policy + Slice Workflow Cleanup

**Problem:** The workflow still treated the long architecture rationale files as first-pass input in several active instructions. That contradicted the later context-management decision: `CONSTITUTION.md` and `ARCHITECTURE-MAP.md` should be the daily sources, while `docs/architecture/rationale/` should be opened only when compact docs are insufficient. Some skills also still referenced the old `res://tests/run_tests.tscn` runner and the deprecated graybox-2/5/6 chain.

**Fix:** Updated AGENTS, mechanic stages, graybox-1, start-stage, explain-artifact, slice, and test skills. The active implementation path is now `/slice`; graybox-2/4/5/6 are documented as deprecated manual references. Architecture artifact detection accepts either root architecture files or `rationale/` files, but first-pass reading remains compact. Test commands now use the GUT CLI runner. Added a revalidation policy to `docs/mechanic-spec.md` so historical graybox code is treated as evidence, not automatic implementation completion.

**Verification:** Searched for stale live references to `res://tests/run_tests.tscn`, old manual slice commands, and `docs/workflow-changelog.md`; remaining matches are historical logs. Ran GUT headless with 31/31 tests passing and 111 asserts. Existing `MovementBroker` fixture warnings still appear on stderr but do not fail the suite.

**Files:**
- `AGENTS.md`
- `.agents/start-stage/SKILL.md`
- `.agents/slice/SKILL.md`
- `.agents/run-stage-tests/SKILL.md`
- `.agents/run-all-tests/SKILL.md`
- `.agents/explain-artifact/SKILL.md`
- `workflow/stages/mechanic/01-mechanic-spec.md`
- `workflow/stages/mechanic/02-mechanic-design.md`
- `workflow/stages/graybox/01-project-initiator.md`
- `docs/mechanic-spec.md`
