Start a new work session. Run this at the beginning of every session before touching any code.

## Steps

### 1. Sync main

```bash
git checkout main
git fetch origin && git merge origin/main
```

If there are uncommitted changes on main, stop and report — do not proceed until they are resolved.

### 2. Pull live project state

```bash
gh issue list --repo nickybmon/OpenEmu-Silicon --state open
gh project item-list 3 --owner nickybmon --format json
```

Read the output. Summarize the open issues and board status so there's a clear picture of what's in flight.

### 3. Confirm the task

Ask: "What are we working on today?" if the user hasn't already said. Once the task is clear, derive a branch name from it.

Branch naming:
- `fix/short-description` — bug fix
- `feat/short-description` — new feature
- `chore/short-description` — tooling, config, docs

### 4. Create the branch

```bash
git checkout -b <type>/short-description
```

### 5. Report

Confirm:
- Branch created and active
- Summary of open issues / board state
- Ready to work
