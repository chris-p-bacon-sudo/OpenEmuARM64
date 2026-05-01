#!/bin/bash
# NOTE: This script was created during the original ARM64 port and contains
# hardcoded paths from the original developer's machine. It is kept for
# historical reference only and is not intended to be run directly.
# Set PROJECT_DIR to your local checkout path before using.
set -e

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
VICE_DIR="$PROJECT_DIR/vice-3.10"
CORE_DIR="$PROJECT_DIR/VICE-Core"
BUILD_DIR="$PROJECT_DIR/Build/OpenEmu.app/Contents/PlugIns/Cores"
FRAMEWORK_PATH="$PROJECT_DIR/Build/OpenEmu.app/Contents/Frameworks"

mkdir -p "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data"

# Copy full data directories
echo "Copying data directories..."
cp -R "$VICE_DIR/data/C64" "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data/"
cp -R "$VICE_DIR/data/DRIVES" "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data/"
cp -R "$VICE_DIR/data/PRINTER" "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data/"

# Rename ROMs to expected standard names (symlink or copy)
# OpenEmu/VICE expects 'kernal', 'basic', 'chargen' without version numbers in some contexts
# But we should ensure the specific 'official' versions are mapped
cp "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data/C64/kernal-901227-03.bin" "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data/C64/kernal"
cp "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data/C64/basic-901226-01.bin" "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data/C64/basic"
cp "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data/C64/chargen-901225-01.bin" "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data/C64/chargen"

# Verify copy
ls -l "$BUILD_DIR/VICE.oecoreplugin/Contents/Resources/data/C64/"

# Define sources and objects (Reusing existing .o files)
HEADLESS_SRCS="$VICE_DIR/src/arch/headless/ui.c $VICE_DIR/src/arch/headless/uimon.c $VICE_DIR/src/arch/headless/console.c $VICE_DIR/src/arch/headless/kbd.c $VICE_DIR/src/arch/headless/mousedrv.c $VICE_DIR/src/arch/headless/uistatusbar.c $VICE_DIR/src/arch/headless/archdep.c $VICE_DIR/src/arch/headless/c128ui.c $VICE_DIR/src/arch/headless/c64dtvui.c $VICE_DIR/src/arch/headless/c64scui.c $VICE_DIR/src/arch/headless/c64ui.c $VICE_DIR/src/arch/headless/cbm2ui.c $VICE_DIR/src/arch/headless/cbm5x0ui.c $VICE_DIR/src/arch/headless/petui.c $VICE_DIR/src/arch/headless/plus4ui.c $VICE_DIR/src/arch/headless/scpu64ui.c $VICE_DIR/src/arch/headless/vic20ui.c $VICE_DIR/src/arch/headless/vsidui.c"

# Gather all compiled objects
SRC_OBJS=$(find "$VICE_DIR/src" -maxdepth 1 -name "*.o" ! -name "main.o" ! -name "c1541.o" ! -name "c1541-stubs.o" ! -name "cartconv.o" ! -name "petcat.o" | tr '\n' ' ')
# Add shared objects
SHARED_OBJS=$(find "$VICE_DIR/src/arch/shared" -maxdepth 1 -name "*.o" ! -name "macOS-util.o" ! -name "archdep_exit.o" ! -name "archdep_cbmfont.o" ! -name "uiactions.o" ! -name "archdep_get_vice_datadir.o" ! -name "archdep_default_logger.o" | tr '\n' ' ')
# Add extra objects
SOCKETDRV_OBJ="$VICE_DIR/src/arch/shared/socketdrv/socketdrv.o"
C64KEYBOARD_OBJ="$VICE_DIR/src/c64/c64keyboard.o"

# Add manually compiled cartridge objects and others
# Only include objects NOT in src root (subdirectories)
MANUAL_OBJS="$VICE_DIR/src/c64/c64export.o $(find "$VICE_DIR/src/c64/cart" -name "*.o" | tr '\n' ' ')"

# Compile missing dma.o if needed (required for Fast VICII)
echo "Compiling dma.c..."
clang -c "$VICE_DIR/src/dma.c" -o "$VICE_DIR/src/dma.o" \
    -arch arm64 \
    -I"$VICE_DIR/src" \
    -I"$VICE_DIR/src/c64" \
    -I"$VICE_DIR/src/vicii" \
    -I"$VICE_DIR/src/sid" \
    -I"$VICE_DIR/src/drive" \
    -I"$VICE_DIR/src/lib/p64" \
    -I"$VICE_DIR/src/core" \
    -D_REENTRANT -DMACOS_COMPILE

# Compile main.c locally to ensure consistency with Fast Core
echo "Compiling main.c locally..."
clang -c "$VICE_DIR/src/main.c" -o "$VICE_DIR/src/my_main.o" \
    -arch arm64 \
    -I"$VICE_DIR/src" \
    -I"$VICE_DIR/src/c64" \
    -I"$VICE_DIR/src/vicii" \
    -I"$VICE_DIR/src/sid" \
    -I"$VICE_DIR/src/drive" \
    -I"$VICE_DIR/src/lib/p64" \
    -I"$VICE_DIR/src/core" \
    -I"$VICE_DIR/src/core/rtc" \
    -I"$VICE_DIR/src/monitor" \
    -I"$VICE_DIR/src/imagecontents" \
    -I"$VICE_DIR/src/arch/headless" \
    -I"$VICE_DIR/src/arch/shared" \
    -I"$VICE_DIR/src/arch/shared/hotkeys" \
    -I"$VICE_DIR/src/arch/unix" \
    -I"$VICE_DIR/src/joyport" \
    -I"$VICE_DIR/src/arch/headless" \
    -I"$VICE_DIR/src/arch/shared" \
    -I"$VICE_DIR/src/arch/shared/hotkeys" \
    -I"$VICE_DIR/src/arch/unix" \
    -I"$VICE_DIR/src/joyport" \
    -D_REENTRANT -DMACOS_COMPILE

# SRC_OBJS construction
# Start with found objects excluding main.o
SRC_OBJS=$(find "$VICE_DIR/src" -maxdepth 1 -name "*.o" \
    ! -name "main.o" \
    ! -name "c1541.o" \
    ! -name "c1541-stubs.o" \
    ! -name "cartconv.o" \
    ! -name "petcat.o" \
    ! -name "vsid.o" \
    ! -name "gentranslate.o" \
    ! -name "dma.o" \
    ! -name "my_main.o" \
    | tr '\n' ' ')

# Add manual and compiled objects ONCE
SRC_OBJS="$SRC_OBJS $MANUAL_OBJS $VICE_DIR/src/dma.o $VICE_DIR/src/my_main.o"

LIBS=$(find "$VICE_DIR/src" -name "*.a" \
    ! -name "libffmpeg.a" \
    ! -name "liblame.a" \
    ! -name "libmp3lame.a" \
    ! -name "libx264.a" \
    ! -name "libgnuintl.a" \
    ! -name "libviciisc-stubs.a" \
    ! -name "libvicii-stubs.a" \
    ! -name "*dtv*" \
    ! -name "*x128*" \
    ! -name "*vic20*" \
    ! -name "*plus4*" \
    ! -name "*pet*" \
    ! -name "*cbm2*" \
    ! -name "*b500*" \
    ! -name "*cbm5x0*" \
    ! -name "*c128*" \
    ! -name "*scpu64*" \
    ! -name "libvsidstubs.a" \
    ! -name "libvsid.a" \
    ! -name "libc64sc.a" \
    ! -name "libviciisc.a" \
    | tr '\n' ' ')

echo "Linking..."
clang -bundle -o "$BUILD_DIR/VICE.oecoreplugin/Contents/MacOS/VICE" \
    -isysroot $(xcrun --show-sdk-path) \
    -arch arm64 \
    -mmacosx-version-min=10.14 \
    -I"$VICE_DIR/src" \
    -I"$VICE_DIR/src/video" \
    -I"$VICE_DIR/src/c64" \
    -I"$VICE_DIR/src/sid" \
    -I"$VICE_DIR/src/vicii" \
    -I"$VICE_DIR/src/raster" \
    -I"$VICE_DIR/src/monitor" \
    -I"$VICE_DIR/src/lib/p64" \
    -I"$VICE_DIR/src/platform" \
    -I"$VICE_DIR/src/drive" \
    -I"$VICE_DIR/src/vdrive" \
    -I"$VICE_DIR" \
    -I"$VICE_DIR/src/arch/shared" \
    -I"$VICE_DIR/src/arch/shared/hotkeys" \
    -I"$VICE_DIR/src/monitor" \
    -I"$VICE_DIR/src/parallel" \
    -I"$VICE_DIR/src/arch/headless" \
    -I"$VICE_DIR/src/core/rtc" \
    -I"$VICE_DIR/src/joyport" \
    -I"$VICE_DIR/src/hvsc" \
    -I"$PROJECT_DIR/OpenEmu/SystemPlugins/Commodore 64" \
    -I"$PROJECT_DIR/OpenEmu-SDK" \
    -I"$VICE_DIR/src/c64/cart" \
    -I"$VICE_DIR/src/rs232drv" \
    -I"$VICE_DIR/src/core" \
    -I"$VICE_DIR/src/samplerdrv" \
    -D_REENTRANT \
    -DMACOS_COMPILE \
    -UUSE_VICE_THREAD \
    -F"$FRAMEWORK_PATH" \
    -framework OpenEmuBase \
    -framework Cocoa \
    -framework OpenGL \
    -framework IOKit \
    -framework CoreVideo \
    -framework CoreServices \
    -framework AudioToolbox \
    -framework CoreAudio \
    "$CORE_DIR/VICEGameCore.m" \
    $HEADLESS_SRCS \
    $SRC_OBJS \
    $SHARED_OBJS \
    $SOCKETDRV_OBJ \
    $C64KEYBOARD_OBJ \
    $LIBS $LIBS \
    -lstdc++ -lz -liconv

echo "Fast Relink Complete!"
