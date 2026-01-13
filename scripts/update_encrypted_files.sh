#!/usr/bin/env bash
set -euo pipefail

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $SHELL_DIR)
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh



info "Set git config"
git config filter.crypt.clean  'openssl enc -aes-256-cbc -salt -pbkdf2 -pass env:PASS'
git config filter.crypt.smudge 'openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass env:PASS'
git config filter.crypt.required true


list_crypt_files() {
  while IFS= read -r -d '' path && IFS= read -r -d '' attr && IFS= read -r -d '' val; do
    if [[ "$attr" == "filter" && "$val" == "crypt" ]]; then
      printf '%s\0' "$path"
    fi
  done < <(
    git -C "${PROJECT_DIR}" ls-files -z | git -C "${PROJECT_DIR}" check-attr --stdin -z filter
  )
}


info "Encrypted files:"
list_crypt_files | tr '\0' '\n'

warn "Update workspace by removing then checkouting encrypted files"
while IFS= read -r -d '' f; do
  rm -f -- "${PROJECT_DIR}/$f"
  git -C "${PROJECT_DIR}" checkout -- "$f"
done < <(list_crypt_files)
ok "Finished"

