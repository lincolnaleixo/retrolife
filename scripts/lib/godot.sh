# Shared Godot executable discovery for RetroLife development scripts.

retrolife_godot_cache_file() {
    local repo_root="$1"
    printf '%s/.godot/retrolife-godot-bin\n' "$repo_root"
}

retrolife_resolve_godot() {
    local repo_root="$1"
    local cache_file
    cache_file="$(retrolife_godot_cache_file "$repo_root")"

    if [[ -n "${GODOT_BIN:-}" ]]; then
        if [[ ! -x "$GODOT_BIN" ]]; then
            echo "GODOT_BIN is not an executable file: $GODOT_BIN" >&2
            return 1
        fi
        printf '%s\n' "$GODOT_BIN"
        return 0
    fi

    local -a candidates=()
    if [[ -f "$cache_file" ]]; then
        local cached=""
        IFS= read -r cached < "$cache_file" || true
        if [[ -n "$cached" ]]; then
            candidates+=("$cached")
        fi
    fi

    if command -v godot >/dev/null 2>&1; then
        candidates+=("$(command -v godot)")
    fi
    if command -v godot4 >/dev/null 2>&1; then
        candidates+=("$(command -v godot4)")
    fi

    candidates+=("/Applications/Godot.app/Contents/MacOS/Godot")

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

retrolife_require_godot_version() {
    local godot_bin="$1"
    local minimum_major="${2:-4}"
    local minimum_minor="${3:-7}"
    local version

    version="$("$godot_bin" --version 2>&1 | head -n 1)"
    if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+) ]]; then
        echo "Could not parse Godot version from $godot_bin: $version" >&2
        return 1
    fi

    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    if (( major < minimum_major \
        || (major == minimum_major && minor < minimum_minor) )); then
        echo "Godot ${minimum_major}.${minimum_minor} or newer is required; found $version" >&2
        return 1
    fi

    printf '%s\n' "$version"
}

retrolife_cache_godot() {
    local repo_root="$1"
    local godot_bin="$2"
    local cache_file
    cache_file="$(retrolife_godot_cache_file "$repo_root")"

    mkdir -p "$(dirname "$cache_file")"
    printf '%s\n' "$godot_bin" > "$cache_file"
}

retrolife_print_godot_not_found() {
    cat >&2 <<'EOF_MESSAGE'
Godot was not found.

Install Godot 4.7 or newer, put `godot` or `godot4` in PATH, or set GODOT_BIN
to the executable path. On a standard macOS installation this is usually:

  /Applications/Godot.app/Contents/MacOS/Godot
EOF_MESSAGE
}
