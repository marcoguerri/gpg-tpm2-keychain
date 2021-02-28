#!/bin/bash
set -xue
glibc="glibc-linux4-2.33-4-x86_64.pkg.tar.zst"

function cleanup {
    rm "/tmp/${glibc}"
}

trap cleanup EXIT

glibc="glibc-linux4-2.33-4-x86_64.pkg.tar.zst"
[[ ! -f "/tmp/${glibc}" ]] && curl -L "https://repo.archlinuxcn.org/x86_64/$glibc" -o "/tmp/$glibc"

echo "a89f4d23ae7cde78b4258deec4fcda975ab53c8cda8b5e0a0735255c0cdc05cc /tmp/${glibc}"  | sha256sum --check --status || exit 1
bsdtar -C / -xvf "/tmp/$glibc"

