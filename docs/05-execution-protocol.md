# Waypoint — Execution Protocol

This is the operating manual for running the 18 Cursor prompts (CURSOR-01 → CURSOR-18) safely, one milestone at a time, with an architectural review (me) between each. It defines the exact loop, the **evidence you must collect before advancing**, a reusable Claude review prompt, how to handle failures, and the final MVP-complete checklist.

**The core discipline:** never advance to the next milestone until the current one has (a) a passing Cursor report with real evidence, and (b) a clean architectural review. Breakage must be fixed *inside* the milestone that caused it — never rolled forward.

---

## 1. The per-milestone loop (do this for every CURSOR-NN)

**Step 1 — Give Cursor the prompt.**
Paste exactly one CURSOR-NN prompt. Nothing else. Don't combine milestones.

**Step 2 — Let Cursor inspect the repo first.**
Before it writes code, have it state: which existing files it will read, which files it will create/modify, and its plan for this milestone only. If the plan reaches into later milestones or unrelated files, stop it and re-paste the "What must NOT be changed" + standing rules from that prompt.

**Step 3 — Let Cursor implement — this milestone only.**
Watch for scope creep (new dependencies, new abstractions, "while I'm here" edits). If it happens, halt and correct before continuing.

**Step 4 — Run the specified tests.**
Run the exact commands the prompt named (`swift test`, `xcodebuild build`, `scripts/ci.sh`, and any manual checks). Don't accept "tests should pass" — actually run them and capture the output yourself.

**Step 5 — Review Cursor's report.**
Confirm the report contains every item from that milestone's **Evidence checklist** (§3). If anything is missing, ask Cursor for it before you do anything else. A report without evidence is not a passing milestone.

**Step 6 — Send the implementation + report to me (Claude) for architectural review.**
Use the **Standard Claude Review Prompt** (§2). Give me the diff (or the changed files), Cursor's report, and the raw test output.

**Step 7 — If there are problems, generate a corrective Cursor prompt.**
I'll return a verdict of **PASS**, **PASS-WITH-FOLLOW-UPS**, or **FAIL**. On FAIL (or for any must-fix follow-up), I'll write you a tight **corrective CURSOR-NN.x prompt** scoped to only the defect — same milestone, no new scope. Paste it, then return to Step 4. Re-review until PASS.

**Step 8 — If everything passes, proceed to the next milestone.**
Commit the milestone as its own commit/PR (green build + green tests). Only then paste the next CURSOR-NN. **Special gate:** do not start CURSOR-12 until CURSOR-11 (the walking skeleton) passes its full manual acceptance run.

**Loop invariant:** at the end of every milestone the repo builds, all pure-logic tests are green, the safety suite is green, and the read-only guarantee is intact.

---

## 2. Standard Claude Review Prompt (reuse after every Cursor milestone)

> Copy this, fill the four blanks, and send it to me each time. Keep it identical across milestones so reviews stay consistent and comparable.

```
Claude — architectural review of a completed Cursor milestone.

MILESTONE: CURSOR-__  (roadmap M__: <title>)
WHAT THIS MILESTONE WAS SUPPOSED TO DELIVER: <paste the prompt's Objective + Requirements>
CURSOR'S REPORT: <paste Cursor's full report>
EVIDENCE / ARTIFACTS: <paste raw test output, diffs or changed-file contents, file hashes, manual-test observations, screenshots/log lines as applicable>

Review the actual changes against the intended milestone and our architecture. Inspect and give me a per-dimension verdict (PASS / CONCERN / FAIL) with specifics for each:

1. IMPLEMENTATION CORRECTNESS — does it actually do what the milestone required? Any logic errors, unhandled cases, or gaps vs the requirements?
2. ARCHITECTURE COMPLIANCE — respects module boundaries and the single-safety-gate design? No architecture redesign? Pure-logic modules (Domain/Config/Safety/CoreEngine/Timing) still free of AppKit/Accessibility imports? Everything that acts routes through SafetyPolicy?
3. TESTS — do the tests actually prove the behavior (not just compile)? Coverage of the milestone's risky paths? Any test weakened, skipped, or made trivially green? Is timing injected (no real sleeps) where required?
4. SECURITY — least privilege honored? No network introduced? No content logged (logs carry only action/target/result/timestamp)? No dynamically-loaded code into the privileged process? No secrets committed?
5. macOS COMPATIBILITY — correct/stable API usage (NSWorkspace, AXUIElement, CGEvent, TCC)? App Sandbox still OFF? Any reliance on fragile foreign AX trees or PID-targeted input? Any deprecated/unreliable activation assumptions?
6. ACCIDENTAL SIDE EFFECTS — any unrelated files touched? Any change to earlier milestones' behavior? New dependencies? Scope creep into later milestones?
7. READ-ONLY GUARANTEES — for editor/interaction paths: only inert primitives (scroll-wheel, arrows, Page/Home/End)? No character/Return/Delete keys, no Cmd/Ctrl chords, no paste/save/command execution anywhere in the code path? Focus guard + self-event tag present where synthetic input is emitted?
8. TECHNICAL DEBT — shortcuts taken, TODOs, brittle constructs, missing error handling, anything that will bite a later milestone.

Also explicitly confirm: nothing in this milestone fabricates activity, falsifies screenshots, manipulates time tracking, or deceives monitoring systems.

Then give:
- OVERALL VERDICT: PASS / PASS-WITH-FOLLOW-UPS / FAIL
- MUST-FIX list (blocking) and SHOULD-FIX list (non-blocking, track for later)
- If FAIL or any MUST-FIX: a ready-to-paste corrective Cursor prompt scoped ONLY to the defect in this same milestone (no new scope).
```

**How I'll respond:** a per-dimension table, the overall verdict, must-fix vs should-fix lists, and — when needed — the corrective prompt. I'll refuse to PASS a milestone whose evidence doesn't actually demonstrate the claim (e.g., a read-only milestone with no before/after file hash).

---

## 3. Evidence to collect before advancing — per milestone

For each milestone, do not move on until you have **all** listed items. "Green" means you ran it and saw it pass.

**Universal (every milestone):** the exact commands run + their raw output; `swift test` green; app still builds (`xcodebuild build`); confirmation no unrelated files were touched (diff scope); Cursor's structured report.

| Milestone | Milestone-specific evidence you must obtain |
|---|---|
| **CURSOR-01** Foundation | App launches + quits (state it); `scripts/ci.sh` exits 0; every listed module compiles; README states read-only + anti-deception invariants. |
| **CURSOR-02** Domain + tags | Test output showing every `ActionKind` has `mutatesText == false`; the tag table (action → primitive/verifiable/focus-guard); proof the tag switch is exhaustive. |
| **CURSOR-03** Config | Round-trip test green; the pinned JSON shape for one action; validator **rejects** an illegal (mutating-on-editor) workflow and **accepts** a legal one; migration fixture green; tests use a temp dir. |
| **CURSOR-04** Logging | A sample JSONL line showing only `{timestamp, actionKind, targetBundleID, result}`; explicit confirmation there is **no** free-form content-logging API; rotation test green. |
| **CURSOR-05** Safety (keystone) | The full decision matrix (every action × target class); the inert-key allowlist contents; property-test green; proof CI **fails** if the safety suite is red (gate wired). |
| **CURSOR-06** Engine + sim | State-transition tests green with a **fake clock** (no real sleeps); loop-cap + retry/skip/abort covered; sovereignty signal halts within one step; confirmation `CoreEngine` imports no AppKit/AX. |
| **CURSOR-07** App detection | `FilteringTests` green (helpers excluded via injected data); **live** result: enumerator lists Chrome/VS Code/Finder and frontmost updates as you switch; manual checklist recorded. |
| **CURSOR-08** Permission | State-transition tests green (injected probe); **live**: prompt appears, deep-link opens the right Settings pane, toggling grants without relaunch; dev signature-reset caveat documented. |
| **CURSOR-09** Coarse AX + focus guard | `FocusGuardTests` green (stable→ok / changed→changed / missing→lost); **live**: correct frontmost/window reads for the three apps; explicit confirmation **no document content** is read or logged. |
| **CURSOR-10** Input synth + monitor | Unit tests: only inert primitives constructable; tag-filter ignores self-events, fires on untagged; **live**: own scrolls don't stop the run, real scroll + hot-key stop it within ~100 ms; Secure Input surfaces a precondition failure. |
| **CURSOR-11** Walking skeleton (MVP GATE) | The **full manual acceptance run**: pointed at frontmost Chrome/VS Code, scrolls up/down touching no text, stops instantly on mouse/keyboard/hot-key, focus restored, truthful log lines pasted; CI green. **Do not proceed to 12 without this.** |
| **CURSOR-12** Chrome adapter | Probe→primitive unit tests (incl. probe-failure → degrade); **live**: scroll/page a long Chrome article, only the viewport moves, nothing entered/changed; no tab switching present. |
| **CURSOR-13** Editor read-only | Adapter emits only inert primitives (unit test); **mutation-guard**: before/after **file hash + mtime identical**, run once normally and once with the **Vim keymap** enabled; safety suite still green. |
| **CURSOR-14** Workflow config surface | Runner tests green (JSON workflow runs via sim seam); validation **rejects** illegal workflows before any action; adapter-resolution test green; a **live** multi-target run summary. |
| **CURSOR-15** UI | XCUITest for onboarding + start/stop green; view-model tests green; a **live** end-to-end: build+save+run a workflow entirely via UI on a fresh account; editor **cannot** save an illegal step. |
| **CURSOR-16** Error recovery | Each failure injection → correct transition + safe stop (tests); **live**: quit target app mid-run and revoke Accessibility mid-run → clean stop, clear message, accurate log, no crash; focus restored or honest "couldn't restore" logged. |
| **CURSOR-17** Testing pass | Full pure-logic suite green in CI; **proof the safety gate blocks merge** (temporarily break a safety test → CI red → revert → green); `docs/testing.md` present; manual matrix (apps × macOS versions) recorded. |
| **CURSOR-18** Packaging | `notarytool` success + staple confirmation; **App Sandbox confirmed OFF**; **clean-machine install** on a second Mac/fresh account: opens without Gatekeeper block, requests Accessibility, runs a workflow; versioned DMG produced. |

---

## 4. Handling failures (Step 7 detail)

- **One defect → one corrective prompt.** I'll scope a `CURSOR-NN.x` prompt to only the failing dimension, referencing the same files. No new features, no new scope.
- **Never let Cursor "fix forward"** by starting the next milestone to patch this one. Fix in place.
- **If a fix touches the safety layer (CURSOR-05) or the read-only path,** re-run the *entire* safety suite and re-review those dimensions specifically — these are the guarantees that must never regress.
- **If Cursor repeatedly misses the same point,** tighten the prompt's "What must NOT be changed" and paste the standing rules again; consider adding the rule to a project-wide `.cursorrules`/`AGENTS.md`.
- **Track SHOULD-FIX items** in a running `docs/tech-debt.md` so non-blocking debt isn't lost — and clear the relevant ones before CURSOR-17.

---

## 5. Regression discipline between milestones

Because later milestones build on earlier ones, run this quick guard at the **start** of each new milestone's review, not just the end:

- Pure-logic suite (Domain/Config/Safety/CoreEngine) still green.
- Safety suite still green (the merge gate).
- App still builds; App Sandbox still off (from CURSOR-06 onward it must never be enabled).
- No new third-party dependency slipped in.
- The mutation-guard test (once CURSOR-13 exists) still shows unchanged file hashes.

If any of these regressed, treat it as a FAIL of the *current* milestone and fix before proceeding.

---

## 6. Final checklist — is the MVP genuinely complete?

The MVP is the **walking skeleton proven and productized through a real, shippable path**. Treat it as done only when **every** box below is true. (If you want the narrowest possible "architecture proven" milestone, that's CURSOR-11; the list below is the full, shippable MVP through CURSOR-18.)

**Functional**
- [ ] A user can create, save, and run a navigation workflow entirely through the UI (no JSON editing), including first-run permission setup on a fresh account.
- [ ] Workflows drive already-open Chrome, VS Code, and Finder: activate/return, switch window, scroll, page, wait — as configured.
- [ ] Loop and wall-clock caps are honored; a workflow cannot run away.

**Read-only & safety (non-negotiable)**
- [ ] The safety suite (CURSOR-05) is green and wired as a merge gate.
- [ ] The editor mutation-guard test shows **identical file hash + mtime** before/after a run, with and without the Vim keymap.
- [ ] No code path can emit character/Return/Delete keys, Cmd/Ctrl chords, paste, save, or command execution; only inert primitives exist.
- [ ] Every synthetic-input path passes the focus guard and safety gate, and events are self-tagged.

**User sovereignty**
- [ ] A real mouse move/keypress and the global hot-key each stop a running workflow within ~100 ms.
- [ ] The run never stops itself on its own synthetic events.
- [ ] On stop, focus is restored to the pre-run app, or an honest "couldn't restore" is logged.

**Honesty & privacy**
- [ ] Logs contain only `{timestamp, actionKind, targetBundleID, result}` — no window text, document content, or keystrokes.
- [ ] No network calls are made.
- [ ] Nothing in the app fabricates activity, falsifies screenshots, manipulates time tracking, or deceives monitoring systems — verified by design (no such code paths exist).

**Robustness**
- [ ] Quitting the target app mid-run and revoking Accessibility mid-run both produce a clean stop, a clear message, an accurate log, and no crash.
- [ ] Secure Input mode is detected and surfaced, not looped on.

**Engineering quality**
- [ ] Pure-logic modules (Domain/Config/Safety/CoreEngine/Timing) contain no AppKit/Accessibility imports and run green in CI.
- [ ] App Sandbox is OFF; the app is signed with Developer ID, notarized, and stapled.
- [ ] `docs/testing.md` documents what's automated vs manual (and the provisioned-runner path); `docs/tech-debt.md` has no open MUST-FIX items.

**Distribution proof**
- [ ] On a second Mac / fresh user account, the notarized DMG installs without Gatekeeper blocking, requests Accessibility correctly, and runs a real workflow end to end.

**Sign-off**
- [ ] Every milestone CURSOR-01 → CURSOR-18 received an OVERALL VERDICT of PASS (or PASS-WITH-FOLLOW-UPS with all MUST-FIX cleared).
- [ ] A final full-suite CI run is green, and you personally watched a real workflow run and stop on a clean machine.

When all of the above are checked, the MVP is genuinely complete — not "code written," but *proven, safe, honest, and installable*.
