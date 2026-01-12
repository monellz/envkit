#!/bin/bash
set -x

git config filter.crypt.clean  'openssl enc -aes-256-cbc -salt -pbkdf2 -pass env:PASS'
git config filter.crypt.smudge 'openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass env:PASS'
git config filter.crypt.required true
