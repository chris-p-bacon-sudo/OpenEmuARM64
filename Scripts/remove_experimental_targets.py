#!/usr/bin/env python3
"""
Remove all experimental build target objects from project.pbxproj.
Surgical: targets specific IDs; everything else is untouched.
"""

import re
import sys

PBXPROJ = "OpenEmu/OpenEmu.xcodeproj/project.pbxproj"

# IDs whose entire block (or single-line entry) should be deleted.
# Blocks begin with \t\t<ID> /* ... */ = { and end with \t\t};
# Single-line PBXBuildFile entries match the same leading pattern but end with };
BLOCK_IDS_TO_REMOVE = {
    # PBXAggregateTarget
    "011FD36125267910006D7C05",
    "01607FC525388361006FCBC8",
    "94EBBCD7183F422500743756",
    # PBXShellScriptBuildPhase
    "01E85CBD25389A3700980F83",
    "01E85CBE25389A8000980F83",
    "0121480E2537D541007F3C84",
    "01607FD725388361006FCBC8",
    # PBXCopyFilesBuildPhase
    "01607FCC25388361006FCBC8",
    "94EBBCFB183F42CE00743756",
    # PBXTargetDependency (exclusive to experimental targets)
    "011FD36625267927006D7C05",
    "011FD36825267927006D7C05",
    "011FD36A25267932006D7C05",
    "011FD36C25267956006D7C05",
    "011FD36E25267973006D7C05",
    "011FD37025267986006D7C05",
    "011FD3722526798B006D7C05",
    "011FD3742526799C006D7C05",
    "011FD376252679A1006D7C05",
    "011FD378252679AD006D7C05",
    "011FD37A252679CB006D7C05",
    "011FD37C252679E9006D7C05",  # OEControlLabelsGenerator dep on experimental
    "01607FC625388361006FCBC8",
    "01607FC825388361006FCBC8",
    "01607FCA25388361006FCBC8",
    "01853AC523C0FB5F00619549",
    # PBXContainerItemProxy
    "011FD36525267927006D7C05",
    "011FD36725267927006D7C05",
    "011FD36925267932006D7C05",
    "011FD36B25267956006D7C05",
    "011FD36D25267973006D7C05",
    "011FD36F25267986006D7C05",
    "011FD3712526798B006D7C05",
    "011FD3732526799C006D7C05",
    "011FD375252679A1006D7C05",
    "011FD377252679AD006D7C05",
    "011FD379252679CB006D7C05",
    "011FD37B252679E9006D7C05",
    "01607FC725388361006FCBC8",
    "01607FC925388361006FCBC8",
    "01607FCB25388361006FCBC8",
    "01853AC423C0FB5F00619549",
    # XCConfigurationList
    "011FD36225267910006D7C05",
    "01607FD825388361006FCBC8",
    "94EBBCF4183F422500743756",
    # XCBuildConfiguration
    "011FD36325267910006D7C05",
    "011FD36425267910006D7C05",
    "01607FD925388361006FCBC8",
    "01607FDA25388361006FCBC8",
    "94EBBCF5183F422500743756",
    "94EBBCF6183F422500743756",
    # PBXBuildFile (single-line) — exclusive to experimental CopyFiles phases
    "01607FD625388361006FCBC8",
    "87FBC0A81C07A22700AECF5A",
    "87FBC0861BFC77AF00AECF5A",
    "3DB744CE1BD8BB0B00C23E74",
    "87DF05411BCE3CEA0060E2C2",
    "081A462F1B9574CE00565444",
    "837964FA1A614C6A00A8DE5C",
    "94A5321918DF8A3700AE11B3",
    "94CE3FB218DE92970079CC16",
    "FE6310A1187F099800D8AE07",
    "94EBBD31183F4DB000743756",
}

# Loose line references inside arrays/dicts that need to be removed.
# These IDs appear on lines like:  \t\t\t\t<ID> /* comment */,
# The entire line is dropped.
LINE_REFS_TO_REMOVE = {
    # targets array
    "011FD36125267910006D7C05",
    "94EBBCD7183F422500743756",
    "01607FC525388361006FCBC8",
    # TargetAttributes entry — 3-line entry; the ID line plus surrounding braces
    # handled separately below
    # OEControlLabelsGenerator dependencies
    "011FD37C252679E9006D7C05",
}

# TargetAttributes multi-line entry to remove:
# 011FD36125267910006D7C05 = {
#     CreatedOnToolsVersion = 11.3.1;
# };
TARGET_ATTR_ID = "011FD36125267910006D7C05"


def remove_blocks(text):
    """Remove multi-line blocks and single-line entries whose leading ID is in BLOCK_IDS_TO_REMOVE."""
    lines = text.split("\n")
    out = []
    i = 0
    id_pattern = re.compile(r'^\t\t([0-9A-Fa-f]{24}) /\*')
    while i < len(lines):
        line = lines[i]
        m = id_pattern.match(line)
        if m and m.group(1) in BLOCK_IDS_TO_REMOVE:
            # Single-line entry ends with }; on the same line
            if line.rstrip().endswith("};"):
                i += 1  # skip just this line
                continue
            # Multi-line block: skip until we find the closing \t\t};
            i += 1
            while i < len(lines):
                if lines[i].rstrip() == "\t\t};":
                    i += 1  # skip the closing line too
                    break
                i += 1
            continue
        out.append(line)
        i += 1
    return "\n".join(out)


def remove_line_refs(text):
    """Remove single lines that are array references to IDs in LINE_REFS_TO_REMOVE."""
    lines = text.split("\n")
    out = []
    id_pattern = re.compile(r'^\s+([0-9A-Fa-f]{24})\s+/\*')
    for line in lines:
        m = id_pattern.match(line)
        if m and m.group(1) in LINE_REFS_TO_REMOVE:
            continue
        out.append(line)
    return "\n".join(out)


def remove_target_attr_entry(text):
    """Remove the 3-line TargetAttributes block for the experimental aggregate target.
    The entry is indented with 5 tabs (inside TargetAttributes dict).
    """
    # Matches:
    #   \t\t\t\t\t011FD36125267910006D7C05 = {
    #   \t\t\t\t\t\tCreatedOnToolsVersion = ...;
    #   \t\t\t\t\t};
    pattern = re.compile(
        r'\t\t\t\t\t' + re.escape(TARGET_ATTR_ID) + r' = \{\n'
        r'\t\t\t\t\t\t[^\n]+\n'
        r'\t\t\t\t\t\};\n',
        re.MULTILINE,
    )
    new = pattern.sub("", text)
    if new == text:
        print("WARNING: TargetAttributes entry not removed — pattern did not match", file=sys.stderr)
    return new


def verify_no_dangling(text, ids):
    """Check that none of the removed IDs appear anywhere in the modified file."""
    found = []
    for oid in ids:
        if oid in text:
            found.append(oid)
    return found


def main():
    with open(PBXPROJ, "r", encoding="utf-8") as f:
        original = f.read()

    result = original
    result = remove_blocks(result)
    result = remove_line_refs(result)
    result = remove_target_attr_entry(result)

    # Verify no dangling references
    all_removed = BLOCK_IDS_TO_REMOVE | LINE_REFS_TO_REMOVE
    # Don't check LINE_REFS_TO_REMOVE IDs that are also block IDs (already checked above)
    # Also skip 011FD37C which might appear in TargetDependency still? No — we removed the block.
    dangling = verify_no_dangling(result, all_removed)
    if dangling:
        print("ERROR: Dangling references remain for these IDs:", file=sys.stderr)
        for d in dangling:
            # Show context
            for i, line in enumerate(result.split("\n")):
                if d in line:
                    print(f"  Line {i+1}: {line.strip()}", file=sys.stderr)
        sys.exit(1)

    # Check "Experimental" count
    exp_count = result.count("Experimental")
    print(f"'Experimental' occurrences remaining: {exp_count}")
    if exp_count > 0:
        for i, line in enumerate(result.split("\n")):
            if "Experimental" in line:
                print(f"  Line {i+1}: {line.strip()}")

    with open(PBXPROJ, "w", encoding="utf-8") as f:
        f.write(result)

    print(f"Done. Wrote {len(result)} bytes to {PBXPROJ}")
    orig_lines = original.count("\n")
    new_lines = result.count("\n")
    print(f"Lines: {orig_lines} -> {new_lines} (removed {orig_lines - new_lines})")


if __name__ == "__main__":
    main()
