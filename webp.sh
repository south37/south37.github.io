#!/bin/sh

set -eux

find -E static -regex ".*\.(jpg|jpeg|gif|png)" \
  -exec sh -c 'cwebp -m 6 $1 -o ${1%.*}.webp' _ {} \;
