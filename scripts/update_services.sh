#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
PROJECT_DIR=$(dirname -- "$SCRIPTS_DIR")
. "$SCRIPTS_DIR/color.sh"
. "$SCRIPTS_DIR/log.sh"

usage() {
    printf '%s\n' \
        "Usage: $0 [--dry-run] [--yes] [SERVICE ...]" \
        "Pull latest/latest-* images and recreate only running services." \
        "Stopped services receive new images but remain stopped." \
        "Without SERVICE arguments, select all matching non-build services." \
        "Back up service data first; this script does not create backups." \
        "  --dry-run  Show the commands without pulling or recreating." \
        "  --yes      Confirm that backups are ready without prompting."
}

dry_run=0
confirmed=0
requested=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        --yes) confirmed=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) error "Unknown option: $arg"; usage >&2; exit 2 ;;
        *) requested+=("$arg") ;;
    esac
done

for dependency in docker jq; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        error "Required command not found: $dependency"
        exit 1
    fi
done

compose=(docker compose -f "$PROJECT_DIR/services/compose.yml")
# Parse Compose's resolved model without loading service environment secrets.
image_rows=$("${compose[@]}" config --format json --no-env-resolution | jq -r '
    .services | to_entries[]
    | select(.value.image != null and .value.build == null)
    | .value.image as $image
    | select($image | contains("@") | not)
    | ($image | split("/") | last | split(":")
        | if length == 1 then "latest" else last end) as $tag
    | select($tag == "latest" or ($tag | startswith("latest-")))
    | [.key, $image] | @tsv
')

available=()
while IFS=$'\t' read -r service image; do
    [[ -n "$service" ]] || continue
    available+=("$service")
done <<< "$image_rows"

contains() {
    local target=$1
    shift
    local item
    for item in "$@"; do
        [[ "$item" != "$target" ]] || return 0
    done
    return 1
}

selected=()
if ((${#requested[@]})); then
    for service in "${requested[@]}"; do
        if ! contains "$service" "${available[@]}"; then
            error "Not a latest-tagged, non-build Compose service: $service"
            exit 2
        fi
        if ! contains "$service" "${selected[@]}"; then
            selected+=("$service")
        fi
    done
else
    selected=("${available[@]}")
fi

if ((${#selected[@]} == 0)); then
    info "No latest-tagged services found."
    exit 0
fi

running_text=$("${compose[@]}" ps --status running --services)
running=()
while IFS= read -r service; do
    [[ -z "$service" ]] || running+=("$service")
done <<< "$running_text"

recreate=()
for service in "${selected[@]}"; do
    if contains "$service" "${running[@]}"; then
        recreate+=("$service")
        info "$service: pull image and recreate running service"
    else
        info "$service: pull image only; keep stopped"
    fi
done

run() {
    if ((dry_run)); then
        printf '[dry-run]'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

if ((!dry_run && !confirmed && ${#recreate[@]} > 0)); then
    warn "No automatic backup. Updating these services can migrate databases: ${recreate[*]}"
    if ! read -r -p "Are current data backups ready? [y/N] " answer; then
        error "Confirmation required; use --yes only after backing up."
        exit 1
    fi
    case "$answer" in
        y|Y|yes|YES) ;;
        *) info "Cancelled; no images or containers changed."; exit 0 ;;
    esac
fi

# Complete every pull before recreating any service; leave dependencies alone.
run "${compose[@]}" pull "${selected[@]}"
if ((${#recreate[@]})); then
    run "${compose[@]}" up -d --no-deps --no-build --pull never \
        --wait --wait-timeout 120 "${recreate[@]}"
fi

if ((dry_run)); then
    info "Preview only; no images or containers changed."
else
    ok "Images updated; stopped services were not started."
    if ((${#recreate[@]})); then
        "${compose[@]}" ps "${recreate[@]}"
        warn "Check application login and sync; running/healthy is not an end-to-end test."
    fi
fi
