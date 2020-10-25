#!/bin/bash

[[ $(whoami) != "root" ]] && echo "Please run this script as root" && exit 1


docker run \
    --device /dev/tpm0 \
    --device /dev/tpmrm0 \
    --device-cgroup-rule="b 10:224 rmw" \
    --device-cgroup-rule="b 224:65536 rmw" \
    -e DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v gpg_keys_volume:/home/gpg/keys \
    -it gpg /usr/sbin/init
