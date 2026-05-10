Draft a monthly Progress Report and companion release notes for OpenEmu-Silicon.

## Usage

Run `/progress-report` at any point to generate a draft. Optionally specify a date range:
- `/progress-report` — drafts for the past 30 days
- `/progress-report 2026-04-01 2026-04-30` — drafts for April 2026

## Steps

### 1. Determine the date range

If the user specified dates, use them. Otherwise, default to the past 30 days:

```bash
SINCE=$(date -v-30d +%Y-%m-%d)
UNTIL=$(date +%Y-%m-%d)
echo "Date range: $SINCE to $UNTIL"
```

### 2. Pull merged PRs with contributors

```bash
gh pr list \
  --repo nickybmon/OpenEmu-Silicon \
  --state merged \
  --search "merged:>$SINCE" \
  --limit 50 \
  --json number,title,author,mergedAt,labels,body \
  | python3 -c "
import json, sys
prs = json.load(sys.stdin)
for pr in sorted(prs, key=lambda x: x['mergedAt']):
    labels = [l['name'] for l in pr['labels']]
    author = pr['author']['login']
    print(f\"#{pr['number']} [{author}] {pr['title']}\")
    print(f\"  Labels: {', '.join(labels) if labels else 'none'}\")
    print()
"
```

### 3. Pull recently closed issues

```bash
gh issue list \
  --repo nickybmon/OpenEmu-Silicon \
  --state closed \
  --limit 30 \
  --json number,title,closedAt,labels \
  | python3 -c "
import json, sys
from datetime import datetime, timezone
issues = json.load(sys.stdin)
since = '$SINCE'
for issue in issues:
    if issue['closedAt'] and issue['closedAt'][:10] >= since:
        labels = [l['name'] for l in issue['labels']]
        print(f\"#{issue['number']} {issue['title']}\")
        print(f\"  Labels: {', '.join(labels) if labels else 'none'}\")
        print()
"
```

### 4. Pull core submodule changes (version bumps)

```bash
git log \
  --since="$SINCE" \
  --oneline \
  --all \
  -- '*.gitmodules' \
  | head -20

# Also check for submodule commits in merged PRs
git log \
  --since="$SINCE" \
  --oneline \
  --merges \
  | grep -i "core\|submodule\|bump\|update" \
  | head -20
```

### 5. Identify first-time contributors

Cross-reference PR authors against the full contributor list to flag first-timers:

```bash
gh api \
  repos/nickybmon/OpenEmu-Silicon/contributors \
  --paginate \
  --jq '.[].login' \
  2>/dev/null | sort > /tmp/all_contributors.txt

# PR authors from step 2 — check which are new
```

### 6. Draft the Progress Report

Using the data above and the template in `docs/progress-report-template.md`, draft a filled-in Progress Report. Structure:

- **Opening paragraph** — what was the big theme of this period?
- **Highlights** — 3–5 most significant changes, with PR numbers and contributors
- **Core Updates** — submodule bumps with version changes (skip if none)
- **RetroAchievements** — RA-specific news (skip section entirely if none)
- **Bug Fixes** — fixes not covered in Highlights
- **Contributors This Period** — everyone, code and non-code; flag first-timers explicitly
- **What's Next** — pull from open `help wanted` and `good first issue` issues

```bash
# Pull current help wanted issues for the "What's Next" section
gh issue list \
  --repo nickybmon/OpenEmu-Silicon \
  --state open \
  --label "help wanted" \
  --limit 5 \
  --json number,title \
  --jq '.[] | "#\(.number) \(.title)"'
```

### 7. Draft the companion Release Notes

Draft a slim release note that complements, not duplicates, the Progress Report:

```
v[VERSION] — [ONE-LINE SUMMARY]

[ONE PARAGRAPH — what's in this release, why it matters]

#### Changes
[BULLET LIST of fixes/improvements with PR numbers]

#### Contributors
[NAMES]

Full details in the [Month Year Progress Report](LINK_PLACEHOLDER — fill in after publishing the Discussion).

#### Installation
Download from the assets below. Requires macOS 11.0 or later on Apple Silicon.

#### Known Issues
[None / list]
```

### 8. Output

Present both drafts in sequence:
1. **Progress Report** (for GitHub Discussions → Announcements) — ready to copy-paste and edit
2. **Release Notes** (for the GitHub Release) — short, with a placeholder for the Discussion link

Label any section where data was ambiguous or missing. The user fills in judgment calls — this is a first draft, not a finished document.

## Notes

- Always credit the contributor handle (not just the PR number) — recognition is the point.
- Flag first-time contributors explicitly in both drafts.
- If the RA section has nothing to report, omit it entirely rather than leaving it empty.
- The release notes link to the Discussion — fill in that link after the Discussion is published.
- Run the pre-publish checklist from `docs/progress-report-template.md` before handing off to the user.
