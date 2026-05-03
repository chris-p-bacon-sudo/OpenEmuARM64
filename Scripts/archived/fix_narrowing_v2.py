import os

files_to_fix = [
    "Nestopia/core/board/NstBoardBtlSmb3.cpp",
    "Nestopia/core/board/NstBoardBmcFk23c.cpp",
    "Nestopia/core/board/NstBoardMmc5.cpp",
    "Nestopia/core/board/NstBoardBandaiLz93d50ex.cpp",
    "Nestopia/core/NstApu.cpp"
]

for filepath in files_to_fix:
    full_path = os.path.abspath(filepath)
    if not os.path.exists(full_path):
        print(f"Skipping {filepath}, not found.")
        continue
        
    with open(full_path, 'r') as f:
        lines = f.readlines()
        
    new_lines = []
    for line in lines:
        # Simple heuristic for the narrowing cases in initializer lists
        if "irq.unit.count & 0xFF" in line and "static_cast" not in line:
            line = line.replace("irq.unit.count & 0xFF", "static_cast<byte>(irq.unit.count & 0xFF)")
        if "irq.unit.count >> 8" in line and "static_cast" not in line:
            line = line.replace("irq.unit.count >> 8", "static_cast<byte>(irq.unit.count >> 8)")
        if "data[0]" in line and "{" in line and "static_cast" not in line:
             # Generic case for some data arrays
             pass
        new_lines.append(line)
        
    with open(full_path, 'w') as f:
        f.writelines(new_lines)

# Specific fix for NstApiCheats.cpp
cheats_path = os.path.abspath("Nestopia/core/api/NstApiCheats.cpp")
if os.path.exists(cheats_path):
    with open(cheats_path, 'r') as f:
        content = f.read()
    content = content.replace("addresses[index]", "addresses[static_cast<dword>(index)]")
    content = content.replace("values[index]", "values[static_cast<dword>(index)]")
    content = content.replace("compare[index]", "compare[static_cast<dword>(index)]")
    content = content.replace("masks[index]", "masks[static_cast<dword>(index)]")
    with open(cheats_path, 'w') as f:
        f.write(content)
