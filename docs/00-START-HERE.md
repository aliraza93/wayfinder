# Waypoint — Start Here

This folder is the project root for **Waypoint**: a macOS menu-bar app that runs user-defined, strictly read-only navigation workflows across your already-open apps. *Hands-free navigation. Never touches your work.*

Everything here is planning + control documentation. The actual code repository gets created by the first Cursor milestone (CURSOR-01), inside this same folder.

## Read in this order

1. **`docs/01-build-plan.md`** — the phased engineering plan and the reasoning behind the technology choices. Start here to understand *what* you're building and *why*.
2. **`docs/02-architecture-review.md`** — a critical review that fixes the weak spots and lands on the **authoritative architecture**. If the build plan and this review ever disagree, this review wins.
3. **`docs/03-implementation-roadmap.md`** — the work broken into 18 small milestones (M0–M17), each independently testable and buildable.
4. **`docs/04-cursor-prompts.md`** — 18 copy/paste-ready prompts (CURSOR-01 → CURSOR-18), one per milestone.
5. **`docs/05-execution-protocol.md`** — how to actually run the build: the per-milestone loop, the evidence to collect, the reusable Claude review prompt, and the final MVP-complete checklist.
6. **`docs/testing.md`** — test pyramid, SafetyTests merge gate, manual matrix, and provisioned GUI runner (TCC cannot be granted in ordinary CI).
7. **`AGENTS.md`** (repo root) — binding rules Cursor loads automatically every session (read-only invariant, no-deception rule, safety gate, module boundaries). You don't need to paste these; Cursor reads them. They back-stop the prompts.

## Before you paste CURSOR-01

Confirm the two project constants in `AGENTS.md`:

- **Product name:** Waypoint
- **Bundle identifier:** `com.twixrsolutions.waypoint` — baked into code signing and the Accessibility permission grant. It's set; don't change it after CURSOR-01, since changing it later forces users to re-grant permission.

## How to build (the short version)

Paste the prompts **in order**, one at a time, into Cursor. After each one:

1. Let Cursor inspect, implement, and run its tests.
2. Collect the evidence listed for that milestone in `docs/05-execution-protocol.md`.
3. Send the diff + Cursor's report + test output back to Claude using the **Standard Claude Review Prompt** in that same doc.
4. Fix any problems inside the same milestone before advancing.

**Hard gate:** do not start CURSOR-12 until CURSOR-11 (the walking-skeleton MVP) passes its full manual acceptance run. That milestone is the proof the whole architecture works.

The MVP is done when every box in the final checklist of `docs/05-execution-protocol.md` is true — not "code written," but *proven, safe, honest, and installable*.
