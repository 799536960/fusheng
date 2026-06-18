# Fusheng Local Publish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide one repeatable, strict local publish workflow for installing the latest Fusheng build to `/Applications/浮声.app`.

**Architecture:** A project-local Bash script owns test, build, clean install, signing verification, residue checks, launch, and process verification. A small `build_and_run.sh` wrapper exposes the same workflow to Codex's Run action without duplicating build logic.

**Tech Stack:** Bash, Xcode `xcodebuild`, macOS `codesign`, `osascript`, `open`, `pgrep`.

---

### Task 1: Local Publish Script

**Files:**
- Create: `script/publish_local.sh`

- [ ] **Step 1: Create a strict publish script**

Create `script/publish_local.sh` with `set -euo pipefail`. The script must:
- run tests by default;
- build with a separate DerivedData directory from tests;
- stop the old app;
- remove `/Applications/浮声.app` before copying;
- verify the installed app signature;
- fail if XCTest/test bundle residue is present;
- launch the app unless `--no-launch` is passed.

- [ ] **Step 2: Make the script executable**

Run: `chmod +x script/publish_local.sh`

- [ ] **Step 3: Validate shell syntax**

Run: `bash -n script/publish_local.sh`

Expected: no output and exit code 0.

### Task 2: Codex Run Entrypoint

**Files:**
- Create: `script/build_and_run.sh`

- [ ] **Step 1: Create the wrapper**

Create `script/build_and_run.sh` so the default path calls `script/publish_local.sh`. Support `--logs`, `--telemetry`, `--verify`, and `--debug` without duplicating build/install logic.

- [ ] **Step 2: Make the wrapper executable**

Run: `chmod +x script/build_and_run.sh`

- [ ] **Step 3: Validate shell syntax**

Run: `bash -n script/build_and_run.sh`

Expected: no output and exit code 0.

### Task 3: Codex Environment and Documentation

**Files:**
- Create: `.codex/environments/environment.toml`
- Create: `docs/local-publish.md`

- [ ] **Step 1: Add Codex Run action**

Create `.codex/environments/environment.toml` with a single Run action pointing at `./script/build_and_run.sh`.

- [ ] **Step 2: Document the workflow**

Create `docs/local-publish.md` in Chinese. It must state that local publishing must use `./script/publish_local.sh` and must not manually merge-copy over `/Applications/浮声.app`.

### Task 4: End-to-End Verification

**Files:**
- Verify: `script/publish_local.sh`
- Verify: `/Applications/浮声.app`

- [ ] **Step 1: Run full local publish**

Run: `./script/publish_local.sh`

Expected:
- tests pass;
- build succeeds;
- installed app signature verifies;
- no XCTest/test residue is found;
- `/Applications/浮声.app/Contents/MacOS/Fusheng` is running.

- [ ] **Step 2: Confirm app bundle contents are clean**

Run: `find /Applications/浮声.app/Contents -maxdepth 2 -type d | sort`

Expected: no `PlugIns/FushengTests.xctest` and no XCTest frameworks.
