#!/usr/bin/env bash
set -euo pipefail

FORCE=0
if [[ ${1:-} == '-f' || ${1:-} == '--force' ]]; then
    FORCE=1
    shift
fi

SEARCH_DIR="${1:-namespaces}"
SRC_NAME='secret.yaml'
ENC_NAME='secret.enc.yaml'

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[32m%-9s\033[0m %s\n' "$1" "$2"; }

command -v sops >/dev/null || die 'sops not found'

root=$(git rev-parse --show-toplevel 2>/dev/null) || die 'not inside a git repository'
cd "$root"

[[ -f .sops.yaml ]] || die 'no .sops.yaml at repository root'
[[ -d $SEARCH_DIR ]] || die "no such directory: ${SEARCH_DIR}"

mapfile -t sources < <(find "$SEARCH_DIR" -type f -name "$SRC_NAME" | sort)

if (( ${#sources[@]} == 0 )); then
    echo "no ${SRC_NAME} found under ${SEARCH_DIR}/"
    exit 0
fi

encrypted=0
unchanged=0

for src in "${sources[@]}"; do
    dst="${src%/${SRC_NAME}}/${ENC_NAME}"

    # This repository is public. Refuse to proceed if a plaintext secret could
    # ever be staged by accident.
    if ! git check-ignore -q "$src"; then
        die "${src} is not ignored by git — add it to .gitignore before continuing"
    fi

    # Every encryption generates a fresh data key, so re-running would rewrite
    # every file and churn the diff. Compare mtimes rather than content: sops
    # can encrypt using only the age public key from .sops.yaml, but comparing
    # plaintext would need the private key, which lives on the server.
    if (( ! FORCE )) && [[ -f $dst && ! $src -nt $dst ]]; then
        info unchanged "$dst"
        unchanged=$(( unchanged + 1 ))
        continue
    fi

    backup=''
    if [[ -f $dst ]]; then
        backup=$(mktemp)
        cp -p "$dst" "$backup"
    fi

    # sops matches creation_rules against the *file path*, and .sops.yaml only
    # has a rule for '.*\.enc\.ya?ml$'. Encrypting secret.yaml directly fails
    # with "no creation rules", so copy to the final name and encrypt in place.
    cp "$src" "$dst"

    if ! sops --encrypt --in-place "$dst"; then
        if [[ -n $backup ]]; then
            mv "$backup" "$dst"
        else
            rm -f "$dst"
        fi
        die "sops failed to encrypt ${src}"
    fi

    # Guard against ever leaving readable plaintext at the committed path.
    if ! grep -q '^sops:' "$dst"; then
        rm -f "$dst"
        if [[ -n $backup ]]; then
            mv "$backup" "$dst"
        fi
        die "${dst} has no sops metadata — refusing to keep it"
    fi

    if [[ -n $backup ]]; then
        rm -f "$backup"
    fi

    info encrypted "$dst"
    encrypted=$(( encrypted + 1 ))
done

printf '\n%d encrypted, %d unchanged\n' "$encrypted" "$unchanged"
