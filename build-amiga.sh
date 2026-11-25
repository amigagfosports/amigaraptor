#!/bin/sh
# Raptor: Call of the Shadows (skynettx's open engine) for AmigaOS 3.x /
# AmiCradle (68040 + FPU, SDL2 through GFOpenGPU), built with the os32-gcc16
# stove: OpenAmigaGCC 16.2.0-open3, or open4 (Cradle's os32-gcc16 stove since
# 2 November 2026); the receipt says which. This is the build Cradle's
# stove_build runs (STOVE= and OUT= set).
#   STOVE   the stove (default ~/AmigaChrome/stoves/os32-gcc16)
#   OUT     the output directory (default build-amiga)
#   JOBS    parallel compiles (default 2)
# The engine source is the upstream tree imported into this repository
# (gameports/catalog.json holds the upstream commit); patches/ is applied to
# a copy, never to the tree itself, and nothing is fetched. The textscreen
# library (upstream's setup screens) and TinySoundFont are built from the
# copies upstream carries in include/.
# Outputs: Raptor/raptor (the program), Raptor/LICENSE, receipt.json,
# build.log. The game data is not built here: runtime-data/build-amiga.sh
# fetches the shareware episode on the PC that runs it and stages it beside
# the program; it is never committed.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STOVE=${STOVE:-"$HOME/AmigaChrome/stoves/os32-gcc16"}
OUT=${OUT:-"$HERE/build-amiga"}
JOBS=${JOBS:-2}
P="$STOVE/prefix"
SDK="$P/m68k-amigaos"
CC="$P/bin/m68k-amigaos-gcc"
CXX="$P/bin/m68k-amigaos-g++"

# the compiler is recorded, not checked (BL-144): scripts/record_stove.py
# prints "RELEASE ARCHIVE-SHA256" (the release the compiler's --version names;
# "unpublished" when the stove names no archive) and the compiler's own
# --version line on stderr; it fails only when the stove has no compiler
COMPILER=$(python3 "$HERE/scripts/record_stove.py" --stove "$STOVE")
RELEASE=${COMPILER% *}
ARCHIVE=${COMPILER#* }
"$CC" --version | head -n 1

PIN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ports"]["raptor"]["source"]["commit"])' "$HERE/gameports/catalog.json")
REPO_REV=$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)
EPOCH=$(git -C "$HERE" show -s --format=%ct HEAD 2>/dev/null || date +%s)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/raptor-build.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
mkdir -p "$WORK/src" "$WORK/include" "$OUT"
cp -R "$HERE/src/." "$WORK/src/"
cp -R "$HERE/include/textscreen" "$HERE/include/TinySoundFont" "$WORK/include/"
for patch in "$HERE"/patches/*.patch; do
    [ -f "$patch" ] || continue
    echo "patch: $(basename "$patch")"
    patch --batch --forward --fuzz=0 -p1 -d "$WORK" < "$patch"
done

# upstream's source list (CMakeLists.txt, BUILD_WITH_SETUP on); the system
# MIDI back ends (Windows, ALSA, Core Audio, CoreMIDI) compile to nothing here
SOURCES="tile.cpp gssapi.cpp objects.cpp tile_a.cpp windows.cpp flame.cpp
i_lastscr.cpp joyapi.cpp kbdapi.cpp glbapi.cpp i_video.cpp musapi.cpp
movie_a.cpp ptrapi_a.cpp swdapi.cpp imsapi.cpp store.cpp i_oplmusic.cpp
bonus.cpp anims.cpp shadow.cpp movie.cpp m_misc.cpp shots.cpp opl3.cpp
eshot.cpp gfxapi_a.cpp dspapi.cpp vmemapi.cpp rap.cpp demo.cpp prefapi.cpp
gfxapi.cpp intro.cpp help.cpp input.cpp fx.cpp ptrapi.cpp loadsave.cpp
enemy.cpp mpuwinmm.cpp mputsf.cpp mpualsa.cpp mpucorea.cpp mpucorem.cpp
setup/se_input.cpp setup/se_main.cpp setup/se_music.cpp setup/se_prefapi.cpp
setup/se_sound.cpp setup/se_txt_joyinput.cpp setup/se_txt_keyinput.cpp
setup/se_txt_mouseinput.cpp"
TXT="txt_conditional.c txt_checkbox.c txt_desktop.c txt_dropdown.c
txt_fileselect.c txt_gui.c txt_inputbox.c txt_io.c txt_button.c txt_label.c
txt_radiobutton.c txt_scrollpane.c txt_separator.c txt_spinctrl.c txt_sdl.c
txt_strut.c txt_table.c txt_utf8.c txt_widget.c txt_window.c
txt_window_action.c"

# -fno-delete-null-pointer-checks: address 0 is memory on an Amiga
ARCH="-noixemul -m68040 -m68881 -fno-delete-null-pointer-checks -pthread"
COMMON="$ARCH -O2 -ffile-prefix-map=$WORK=. -I$SDK/include -I$SDK/include/SDL2
 -I$WORK/include/textscreen/include -I$WORK/include/TinySoundFont -DBUILD_WITH_SETUP=1"
CXXFLAGS="$COMMON -std=gnu++11"
CFLAGS="$COMMON -std=gnu11"

(
    cd "$WORK"
    export SOURCE_DATE_EPOCH="$EPOCH"
    mkdir -p obj
    for s in $SOURCES; do echo "src/$s"; done | xargs -P "$JOBS" -I{} sh -c \
        'echo "c++ {}"; o=obj/$(basename {} .cpp).o; "$0" $1 -c {} -o "$o"' "$CXX" "$CXXFLAGS"
    for s in $TXT; do echo "include/textscreen/include/$s"; done | xargs -P "$JOBS" -I{} sh -c \
        'echo "cc {}"; o=obj/$(basename {} .c).o; "$0" $1 -c {} -o "$o"' "$CC" "$CFLAGS"
    echo "link raptor"
    # shellcheck disable=SC2086
    "$CXX" $ARCH -o raptor obj/*.o -L"$SDK/lib" -lSDL2 -lGL -lm -pthread
) > "$OUT/build.log" 2>&1 || { tail -n 80 "$OUT/build.log"; exit 1; }
tail -n 5 "$OUT/build.log"
echo "warnings: $(grep -c 'warning:' "$OUT/build.log" || true)"

EXE="$WORK/raptor"
[ -f "$EXE" ] || { echo "no executable: see build.log"; exit 2; }
[ "$(od -An -tx1 -N4 "$EXE" | tr -d ' \n')" = "000003f3" ] || { echo "not an Amiga HUNK executable"; exit 2; }

# the drawer: the program and the licence (runtime-data/build-amiga.sh stages
# the shareware data beside it; the game makes PROGDIR:User itself)
D="$OUT/Raptor"
mkdir -p "$D"
cp "$EXE" "$D/raptor"
cp "$HERE/LICENSE" "$D/LICENSE"

python3 - "$HERE" "$OUT" "$PIN" "$REPO_REV" "$EPOCH" "$STOVE" "$RELEASE" "$ARCHIVE" <<'EOF'
import hashlib, json, sys
from pathlib import Path
here, out, pin, rev, epoch, stove, release, archive = Path(sys.argv[1]), Path(sys.argv[2]), *sys.argv[3:]
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
sdk = Path(stove) / "prefix/m68k-amigaos"
drawer = out / "Raptor"
receipt = {
    "upstream_commit": pin, "repository_commit": rev, "source_date_epoch": epoch,
    "patches": {p.name: sha(p) for p in sorted((here / "patches").glob("*.patch"))},
    "compiler_release": release, "compiler_archive_sha256": archive,
    "sdk_inputs": {n: sha(sdk / n) for n in ("lib/libSDL2.a", "lib/libGL.a", "include/SDL2/SDL.h")},
    "setup": True, "network": False,
    "executable_sha256": sha(drawer / "raptor"),
    "executable_bytes": (drawer / "raptor").stat().st_size,
    "scope": "Source build only; no game data, runtime or release pass implied",
}
(out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt, indent=2))
EOF
