#!/usr/bin/env bash
set -euo pipefail

IMAGE=ghcr.io/wacky-homes/server
SRC_TAG="${1:-latest}"
DST_TAG="${2:-stable}"
KEY="${COSIGN_KEY:-skopeo.private}"

PRIVILEGED_PATHS=(Containerfile .github/ system/ installer/ scripts/)

die()  { printf '\033[31merror:\033[0m %s\n'   "$*" >&2; exit 1; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }

command -v gh >/dev/null || die 'gh not found'
command -v skopeo >/dev/null || die 'skopeo not found'
[[ -f $KEY ]] || die "signing key not found: ${KEY}"

revision_of() {
    skopeo inspect --format '{{index .Labels "org.opencontainers.image.revision"}}' \
        "docker://${IMAGE}:$1" 2>/dev/null || true
}

echo '==> fetching git refs'
git fetch --quiet --prune origin

new_digest=$(skopeo inspect --format '{{.Digest}}' "docker://${IMAGE}:${SRC_TAG}") \
    || die "cannot inspect ${IMAGE}:${SRC_TAG}"
new_rev=$(revision_of "$SRC_TAG")
old_rev=$(revision_of "$DST_TAG")

[[ -n $new_rev ]] || die 'image has no org.opencontainers.image.revision label'
git cat-file -e "${new_rev}^{commit}" 2>/dev/null \
    || die "commit ${new_rev} is not in this repository"

printf '\nimage:    %s@%s\n' "$IMAGE" "$new_digest"
printf 'revision: %s\n'      "$new_rev"

git merge-base --is-ancestor "$new_rev" origin/main \
    || warn "revision ${new_rev} is NOT an ancestor of origin/main"

if [[ -z $old_rev ]]; then
    warn "no :${DST_TAG} tag yet — nothing to diff against"
    git --no-pager log --oneline -10 "$new_rev"
elif [[ $old_rev == "$new_rev" ]]; then
    warn "no git diff detected, continuing..."
else
    printf 'deployed: %s\n\n' "$old_rev"

    echo '==> commits'
    git --no-pager log --format='%C(auto)%h %G? %an <%ae> %s' "${old_rev}..${new_rev}"

    unsigned=$(git log --format='%G?' "${old_rev}..${new_rev}" | grep -cv '^G$' || true)
    (( unsigned == 0 )) || warn "${unsigned} commit(s) not signed by a trusted key"

    echo
    echo '==> changed files'
    git --no-pager diff --stat "${old_rev}..${new_rev}"

    for p in "${PRIVILEGED_PATHS[@]}"; do
        if git diff --name-only "${old_rev}..${new_rev}" -- "$p" | grep -q .; then
            warn "privileged path modified: ${p}"
        fi
    done

    echo
    read -rp 'view full diff? [y/N] ' ans
    if [[ $ans == [yY] ]]; then
        git diff "${old_rev}..${new_rev}"
    fi
fi

echo
read -rp "sign and promote to :${DST_TAG}? [y/N] " ans
[[ $ans == [yY] ]] || { echo 'aborted'; exit 1; }

echo '==> authenticating'
if ! gh auth status | grep -q 'write:packages'; then
    warn "gh not authenticated with write:packages scope, prompting for login..."
    gh auth login -s write:packages
fi

gh auth token | skopeo login ghcr.io -u $(git config user.name) --password-stdin

echo '==> signing image'
skopeo copy \
    --sign-by-sigstore-private-key $KEY \
    "docker://${IMAGE}@${new_digest}" \
    "docker://${IMAGE}:${DST_TAG}"

echo '==> verifying signature'
final_digest=$(skopeo inspect --format '{{.Digest}}' "docker://${IMAGE}:${DST_TAG}") \
    || die "cannot inspect ${IMAGE}:${DST_TAG} after copy"

[[ $final_digest == "$new_digest" ]] \
    || warn "destination digest ${final_digest} differs from source ${new_digest}"

sig_tag="sha256-${final_digest#sha256:}.sig"
skopeo inspect "docker://${IMAGE}:${sig_tag}" >/dev/null 2>&1 \
    || die "signature not published as ${sig_tag} — node will reject this image"

printf '\n\033[32mtagged\033[0m %s@%s as :%s\n' "$IMAGE" "$new_digest" "$DST_TAG"
