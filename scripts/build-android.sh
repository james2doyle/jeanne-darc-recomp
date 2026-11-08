#!/usr/bin/env bash
# Builds the Android APK and optionally installs it and the game data on a device.
#
#   scripts/build-android.sh                         # -> android/app/build/outputs/apk/release/app-release.apk
#   scripts/build-android.sh --install                # also installs the APK (adb)
#   scripts/build-android.sh --install --install-data # ... and copies the game folder and cooked/ to the device
#                                                     # (packing edited HD textures first, as a Linux build does)
#   scripts/build-android.sh --install-data           # only copies the data (no build); the app must be installed
#   scripts/build-android.sh --install --device Pixel_10_Pro   # pick the device: adb serial or model (adb devices -l)
#   scripts/build-android.sh --list-devices            # shows the connected devices and exits
#   scripts/build-android.sh --driver turnip.zip      # copies a custom GPU driver package (Adreno; installed by the
#                                                     # app at its next start, then chosen in the pause menu)
#   scripts/build-android.sh --install --smoke         # ... then starts the app silently for 2 seconds of game time
#                                                     # and checks that it got there (library loads, game boots)
#   scripts/build-android.sh --profile --install       # the profile build (preset android-arm64-profile: Tracy);
#                                                     # replaces the installed app, its data stays. Capture with
#                                                     # adb forward tcp:8086 tcp:8086, then Tracy on localhost
#
# With several devices connected and no --device (or ANDROID_SERIAL), the script asks which one to use.
#
# Game data goes to Android/data/com.jdarcrecomp/files/ ("Jeanne d'Arc/PSP_GAME/..." and
# "cooked/"). Copies are incremental (adb push --sync). The app must create that folder itself, so --install-data starts
# it once if needed: a folder created earlier by adb belongs to the shell user and the app cannot read it.
# --reset-app-data repairs that by uninstalling the app first, which DELETES its files folder including saves (it needs
# --install to put the app back).
#
# Needs: Android SDK (ANDROID_HOME) with NDK 29.0.14206865, JDK 17 or 21 (auto-selected;
# JDK 22+ breaks AGP's androidJdkImage transform), the Vulkan SDK (VULKAN_SDK: slangc, volk, VMA),
# and data/generated from psprecomp. CMake/Ninja come from PATH.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package=com.jdarcrecomp
remote_files="/sdcard/Android/data/$package/files"
game_name="Jeanne d'Arc"  # the folder name the app looks for (on the device)

install=0; install_data=0; device=""; game_dir=""; cooked_dir=""
reset_app_data=0; skip_build=0; list_devices=0; smoke=0; driver=""; profile=0
while [ $# -gt 0 ]; do
    case "$1" in
        --install) install=1; shift ;;
        --install-data) install_data=1; shift ;;
        --device) device="$2"; shift 2 ;;
        --game-dir) game_dir="$2"; shift 2 ;;
        --cooked-dir) cooked_dir="$2"; shift 2 ;;
        --reset-app-data) reset_app_data=1; shift ;;
        --skip-build) skip_build=1; shift ;;
        --list-devices) list_devices=1; shift ;;
        --smoke) smoke=1; shift ;;
        --driver) driver="$2"; shift 2 ;;
        --profile) profile=1; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[ -n "$game_dir" ] || game_dir="$root/data/original"
[ -n "$cooked_dir" ] || cooked_dir="$root/data/cooked"

: "${ANDROID_HOME:=$HOME/Android/Sdk}"
adb="$ANDROID_HOME/platform-tools/adb"
[ -x "$adb" ] || { echo "adb not found at $adb (set ANDROID_HOME)" >&2; exit 1; }

# Connected devices as "serial model" lines.
get_devices() { "$adb" devices -l | tail -n +2 | grep -E '^[^ ]+[ ]+device\b' || true; }
device_serial() { echo "$1" | awk '{print $1}'; }
device_model() { echo "$1" | grep -oE 'model:[^ ]*' | cut -d: -f2; }

# Resolves the target: --device (serial or model), then ANDROID_SERIAL, then the only device, else a prompt.
select_device() {
    mapfile -t devices < <(get_devices)
    [ "${#devices[@]}" -gt 0 ] || { echo 'No Android device is connected (adb devices).' >&2; exit 1; }
    if [ -n "$device" ]; then
        for d in "${devices[@]}"; do
            s="$(device_serial "$d")"; m="$(device_model "$d")"
            if [ "$s" = "$device" ] || [ "$m" = "$device" ] || [ "$m" = "${device// /_}" ]; then echo "$s"; return; fi
        done
        echo "Device '$device' not found (or ambiguous)." >&2; exit 1
    fi
    if [ -n "${ANDROID_SERIAL:-}" ]; then echo "$ANDROID_SERIAL"; return; fi
    if [ "${#devices[@]}" -eq 1 ]; then device_serial "${devices[0]}"; return; fi
    if [ -t 0 ]; then
        local i=0
        for d in "${devices[@]}"; do i=$((i + 1)); echo "  [$i] $d"; done
        read -rp "Which device? (1-${#devices[@]}) " choice
        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#devices[@]}" ]; then
            device_serial "${devices[$((choice - 1))]}"; return
        fi
        echo 'No device selected.' >&2; exit 1
    fi
    echo 'Several devices are connected; pass --device <serial or model>.' >&2; exit 1
}

invoke_adb() { "$adb" -s "$target" "$@" || { echo "adb $* failed" >&2; exit 1; }; }
adb_shell() { "$adb" -s "$target" shell "$@" 2>/dev/null | tr -d '\r' | tr '\n' ' ' | sed 's/^ *//;s/ *$//'; }

# Remote paths are double-quoted for the device shell (single quotes break on this game's
# folder "Jeanne d'Arc"), escaping \, ", $, and `.
shquote() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//\$/\\\$}"; s="${s//\`/\\\`}"
    printf '"%s"' "$s"
}

# adb push --sync of a local folder into the remote folder $2. Folders are made first with mkdir in
# the shell: on some phones adbd cannot create folders under Android/data itself, while it pushes into existing ones.
push_tree() { # local remoteParent
    local local="$1" remote_parent="$2" base d
    base="$(dirname "$(readlink -f "$local")")"
    batch=()
    push_one() { batch+=("$1"); [ "${#batch[@]}" -ge 50 ] && flush_batch; }
    flush_batch() {
        [ "${#batch[@]}" -gt 0 ] || return 0
        invoke_adb shell "mkdir -p ${batch[*]}"
        batch=()
    }
    batch+=("$(shquote "$remote_parent/$(basename "$local")")")
    while IFS= read -r d; do
        rel="${d#$base/}"
        batch+=("$(shquote "$remote_parent/$rel")")
        [ "${#batch[@]}" -ge 50 ] && flush_batch
    done < <(find "$local" -mindepth 1 -type d)
    flush_batch
    invoke_adb push --sync "$local" "$remote_parent/"
}

# Makes sure the app has created its own files folder (starting it once if needed) and that the app owns it.
initialize_app_folder() {
    local uid
    uid="$(adb_shell "pm list packages -U $package" | grep -oE 'uid:[0-9]+' | cut -d: -f2)"
    [ -n "$uid" ] || { echo "$package is not installed on $target; add --install." >&2; exit 1; }
    if [ -z "$(adb_shell "ls -d $remote_files 2>/dev/null")" ]; then
        echo 'Starting the app once so that it creates its files folder...'
        invoke_adb shell am start -n "$package/.GameActivity" > /dev/null
        local i=0
        while [ $i -lt 30 ] && [ -z "$(adb_shell "ls -d $remote_files 2>/dev/null")" ]; do sleep 0.5; i=$((i + 1)); done
        invoke_adb shell am force-stop "$package"
        [ -n "$(adb_shell "ls -d $remote_files 2>/dev/null")" ] || { echo "The app did not create $remote_files." >&2; exit 1; }
    fi
    local owner
    owner="$(adb_shell "stat -c %u $remote_files")"
    if [ -n "$owner" ] && [ "$owner" != "$uid" ]; then
        echo "$remote_files belongs to user $owner, not to the app ($uid): rerun with --install --reset-app-data." >&2
        exit 1
    fi
}

# Packs edited textures (assets/textures, assets/textures-hd, assets/textures-ai) into cooked/textures, as every
# Linux build does: the Android build has no host tools, so without this the phone would get whatever a Linux
# build packed last.
update_textures() {
    local assets="$root/assets/textures"
    [ -f "$assets/index.tsv" ] || return 0
    local psptex="$root/build/linux-x64-release/psprecore/tools/psptex/psptex"
    if [ ! -x "$psptex" ]; then
        echo 'Building psptex (linux-x64-release) to pack the textures...'
        "$root/scripts/build.sh" --preset linux-x64-release --target psptex
        [ -x "$psptex" ] || { echo "psptex was not built ($psptex)" >&2; exit 1; }
    fi
    echo 'Packing edited textures (assets/textures, textures-hd, textures-ai -> cooked/textures)...'
    "$psptex" pack "$assets" "$cooked_dir" --layer "$root/assets/textures-hd" --layer "$root/assets/textures-ai" \
        --originals "$root/data/collected-textures"
}

copy_game_data() {
    [ -f "$game_dir/PSP_GAME/SYSDIR/BOOT.BIN" ] || { echo "No game at $game_dir (expected PSP_GAME/SYSDIR/BOOT.BIN)." >&2; exit 1; }
    initialize_app_folder
    echo "Copying the game to $remote_files/$game_name (unchanged files are skipped)..."
    invoke_adb shell "mkdir -p $(shquote "$remote_files/$game_name")"
    push_tree "$game_dir/PSP_GAME" "$remote_files/$game_name"
    if [ -d "$cooked_dir" ]; then
        echo "Copying cooked media to $remote_files/cooked..."
        invoke_adb shell "mkdir -p '$remote_files/cooked'"
        for d in "$cooked_dir"/*/; do
            [ -d "$d" ] || continue
            n="$(basename "$d")"
            case "$n" in tmp|textures-tmp|textures) continue ;; esac
            push_tree "$d" "$remote_files/cooked"
        done
        # Baked HD textures: phones sample ASTC, so only those files go (hard links in a staging folder).
        update_textures
        local textures="$cooked_dir/textures"
        if [ -d "$textures" ]; then
            local stage="$root/build/android-stage/textures"
            rm -rf "$stage"; mkdir -p "$stage"
            count=0
            for f in "$textures"/*.astc.ktx2; do
                [ -f "$f" ] || continue
                ln -f "$f" "$stage/$(basename "$f")"
                count=$((count + 1))
            done
            echo "Copying $count HD textures (ASTC; unchanged ones are skipped)..."
            push_tree "$stage" "$remote_files/cooked"
            # push --sync never removes anything: textures no longer packed stay on the phone. Listed, not deleted.
            stale="$(adb_shell "ls '$remote_files/cooked/textures'" | tr ' ' '\n' | grep '\.astc\.ktx2$' || true)"
            for s in $stale; do
                [ -f "$textures/$s" ] || echo "stale HD texture on the phone: $s"
            done | head -n 5
        fi
    else
        echo "Warning: no cooked media at $cooked_dir (run cccook); music and movies will be silent or black." >&2
    fi
    echo 'Game data installed.'
}

if [ "$list_devices" -eq 1 ]; then get_devices; exit 0; fi
if [ "$reset_app_data" -eq 1 ] && [ "$install" -eq 0 ]; then echo '--reset-app-data uninstalls the app; it needs --install to put it back.' >&2; exit 2; fi
target=""
if [ "$install" -eq 1 ] || [ "$install_data" -eq 1 ] || [ "$smoke" -eq 1 ] || [ -n "$driver" ]; then
    target="$(select_device)"  # before the long build: fail fast
fi
build=1
if [ "$skip_build" -eq 1 ] || { [ "$install" -eq 0 ] && { [ "$install_data" -eq 1 ] || [ -n "$driver" ]; }; }; then build=0; fi

command -v cmake >/dev/null && command -v ninja >/dev/null || { echo 'cmake and ninja are required on PATH' >&2; exit 1; }
# Android takes volk and VMA (and matching headers) from the host Vulkan SDK; the NDK does not ship them.
# Located automatically (an explicit VULKAN_SDK wins); override by exporting VULKAN_SDK.
find_vulkan_sdk() {
    local cands=()
    [ -n "${VULKAN_SDK:-}" ] && cands+=("${VULKAN_SDK}")
    cands+=("$HOME"/VulkanSDK/*/x86_64 "$HOME"/.local/share/vulkansdk/*/x86_64 /opt/vulkan-sdk
            /opt/VulkanSDK/*/x86_64 /usr/local /usr)
    local c inc
    for c in "${cands[@]}"; do
        [ -e "$c" ] || continue
        for inc in "$c/Include" "$c/include"; do
            if [ -f "$inc/Volk/volk.c" ] && [ -d "$inc/vma" ]; then echo "$c"; return 0; fi
        done
        [ "$c" = "${VULKAN_SDK:-}" ] && echo "warning: VULKAN_SDK=$c has no Volk/volk.c + vma/, looking elsewhere" >&2
    done
    return 1
}
if [ -z "${VULKAN_SDK:-}" ]; then
    if ! VULKAN_SDK="$(find_vulkan_sdk)"; then
        echo 'No Vulkan SDK with Volk/volk.c and vma/ found; install the LunarG SDK or set VULKAN_SDK.' >&2
        exit 1
    fi
    echo "Using Vulkan SDK: $VULKAN_SDK" >&2
fi
sdk_include=""
for d in "${VULKAN_SDK}/Include" "${VULKAN_SDK}/include"; do
    if [ -f "$d/Volk/volk.c" ] && [ -d "$d/vma" ]; then sdk_include="$d"; break; fi
done
[ -n "$sdk_include" ] || { echo 'VULKAN_SDK must point at a Vulkan SDK with Volk/volk.c and vma/ (volk and VMA sources)' >&2; exit 1; }
export VULKAN_SDK

# AGP's androidJdkImage transform (core-for-system-modules.jar via jlink) only runs on JDK 17/21;
# a newer default JDK (e.g. 27) fails compileReleaseJavaWithJavac. Prefer an explicit JAVA_HOME when
# suitable, otherwise auto-select 17, then 21.
find_android_jdk() {
    local c ver
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/javac" ]; then
        ver="$("$JAVA_HOME/bin/java" -version 2>&1 | head -n 1 | grep -oE 'version "[0-9]+' | grep -oE '[0-9]+$')"
        if [ "$ver" = "17" ] || [ "$ver" = "21" ]; then echo "$JAVA_HOME"; return 0; fi
        echo "warning: JAVA_HOME=$JAVA_HOME is JDK $ver; need 17 or 21, looking elsewhere" >&2
    fi
    for c in "$HOME"/.jdks/* /usr/lib/jvm/java-17-openjdk* /usr/lib/jvm/java-21-openjdk* \
             /opt/android-studio/jbr /opt/java/* /opt/jdk-17* /opt/jdk-21* /usr/lib/jvm/default-java; do
        [ -x "$c/bin/javac" ] || continue
        ver="$("$c/bin/java" -version 2>&1 | head -n 1 | grep -oE 'version "[0-9]+' | grep -oE '[0-9]+$')"
        # Prefer 17 (AGP's baseline) over 21: check 17 candidates on the first pass.
        if [ "$ver" = "17" ]; then echo "$c"; return 0; fi
    done
    for c in "$HOME"/.jdks/* /usr/lib/jvm/java-17-openjdk* /usr/lib/jvm/java-21-openjdk* \
             /opt/android-studio/jbr /opt/java/* /opt/jdk-17* /opt/jdk-21* /usr/lib/jvm/default-java; do
        [ -x "$c/bin/javac" ] || continue
        ver="$("$c/bin/java" -version 2>&1 | head -n 1 | grep -oE 'version "[0-9]+' | grep -oE '[0-9]+$')"
        if [ "$ver" = "21" ]; then echo "$c"; return 0; fi
    done
    return 1
}

# A profile preset's first configure takes the third-party sources its release preset fetched (no second download).
reused=()
if [ "$profile" -eq 1 ]; then
    deps="$root/build/android-arm64-release/_deps"
    if [ -d "$deps" ]; then
        for d in "$deps"/*-src; do
            [ -d "$d" ] || continue
            name="$(basename "$d")"; name="${name%-src}"
            reused+=("-DFETCHCONTENT_SOURCE_DIR_${name^^}=$d")
        done
    fi
fi

cd "$root"
preset=android-arm64-release; variant=release
[ "$profile" -eq 1 ] && { preset=android-arm64-profile; variant=profile; }
apk="android/app/build/outputs/apk/$variant/app-$variant.apk"
if [ "$build" -eq 1 ]; then
    ndk="$ANDROID_HOME/ndk/29.0.14206865"
    [ -d "$ndk" ] || { echo "NDK 29.0.14206865 not found under $ANDROID_HOME/ndk" >&2; exit 1; }
    export ANDROID_NDK_HOME="$ndk"
    cmake --preset "$preset" "${reused[@]}"
    cmake --build --preset "$preset"

    native="$root/build/$preset"
    jni="$native/jniLibs/arm64-v8a"
    mkdir -p "$jni"
    cp -f "$native/libmain.so" "$jni/"
    # libadrenotools' hook libraries (custom GPU drivers), loaded at run time from the app's library folder.
    cp -f "$native"/lib*hook*.so "$jni/" 2>/dev/null || true

    cd "$root/android"
    if ! JAVA_HOME="$(find_android_jdk)"; then
        echo 'No JDK 17 or 21 found (need one for AGP; JDK 22+ fails the androidJdkImage transform). Set JAVA_HOME.' >&2
        exit 1
    fi
    export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"
    echo "Using JDK: $JAVA_HOME ($("$JAVA_HOME/bin/java" -version 2>&1 | head -n 1))" >&2
    gradle_jdk_home="-Dorg.gradle.java.home=$JAVA_HOME"
    if [ "$profile" -eq 1 ]; then
        # SDL's Java sources: in the profile build tree, or the release one's it reused.
        sdl="$native/_deps/sdl3-src"
        [ -d "$sdl" ] || sdl="$root/build/android-arm64-release/_deps/sdl3-src"
        sh gradlew assembleProfile "-PnativePreset=$preset" "-PsdlSource=$sdl" "$gradle_jdk_home" --console=plain
    else
        sh gradlew assembleRelease "$gradle_jdk_home" --console=plain
    fi
    cd "$root"
    echo "APK: $apk"
fi
if [ "$install" -eq 1 ]; then
    [ -f "$apk" ] || { echo "No APK at $apk; build it first." >&2; exit 1; }
    if [ "$reset_app_data" -eq 1 ]; then
        echo "Warning: uninstalling $package from $target: its files folder and saves are deleted." >&2
        "$adb" -s "$target" uninstall "$package" > /dev/null || true  # fine if it was not installed
    fi
    echo "Installing on $target"
    invoke_adb install -r "$apk"
fi
[ "$install_data" -eq 1 ] && copy_game_data
if [ -n "$driver" ]; then
    [ -f "$driver" ] || { echo "No driver package at $driver" >&2; exit 1; }
    initialize_app_folder
    invoke_adb shell "mkdir -p '$remote_files/gpu_drivers'"
    invoke_adb push "$(readlink -f "$driver")" "$remote_files/gpu_drivers/"
    echo 'Driver package copied; the app installs it at its next start (pause menu: GPU driver).'
fi
if [ "$smoke" -eq 1 ]; then
    # The app writes its log to files/jdarc.log; a library that fails to load never gets there.
    log="$remote_files/jdarc.log"
    # Right after an install, Android is still handling the package replacement and may restart a fresh launch
    # without its extras (the arguments); let it settle first.
    [ "$install" -eq 1 ] && sleep 5
    "$adb" -s "$target" shell rm -f "$log" > /dev/null
    "$adb" -s "$target" shell am force-stop "$package" > /dev/null
    "$adb" -s "$target" shell am start -n "$package/.GameActivity" -e args "'--no-audio --vblanks 120'" > /dev/null
    text=""
    for _ in $(seq 1 30); do
        sleep 1
        text="$("$adb" -s "$target" shell cat "$log" 2>/dev/null | tr -d '\r' || true)"
        case "$text" in *"stopped after"*) break ;; esac
    done
    "$adb" -s "$target" shell am force-stop "$package" > /dev/null
    case "$text" in
        *"stopped after"*) echo "Smoke test passed: $(echo "$text" | grep 'stopped after' | head -n 1)" ;;
        *)
            echo 'Smoke test failed: the app did not run 120 vblanks.' >&2
            "$adb" -s "$target" logcat -d -t 300 2>/dev/null | grep -E 'dlopen failed|FATAL|AndroidRuntime' | head -n 5 >&2 || true
            echo "$text" >&2
            exit 1
            ;;
    esac
fi
