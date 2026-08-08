Start a new work session. Run this at the beginning of every session before touching any code.

## Steps

### 1. Clean up and sync

```bash
git cleanup
```

This fetches, prunes stale remote refs, syncs main, and deletes any local branches whose remote was deleted after merge. Run it first, every time — this is what keeps the repo from accumulating dozens of orphaned branches.

If there are uncommitted changes on main, stop and report — do not proceed until they are resolved.

Also clear any stale stashes — list them and drop any that are orphaned (saved on a branch that no longer exists or describes work that's been merged):

```bash
git stash list
```

### 2. Pull live project state

```bash
gh issue list --repo nickybmon/OpenEmu-Silicon --state open
```

Read the output. Summarize the open issues so there's a clear picture of what's in flight.

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
- Summary of open issues
- Ready to work
