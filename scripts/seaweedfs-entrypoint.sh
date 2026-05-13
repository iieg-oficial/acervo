#!/bin/sh
set -e

CONFIG=/etc/seaweedfs/identities.json

if [ ! -s "$CONFIG" ]; then
    echo "[acervo-seaweedfs] ERROR: $CONFIG missing or empty." >&2
    echo "[acervo-seaweedfs] Run 'make init-seaweedfs' before 'make up'." >&2
    echo "[acervo-seaweedfs] Without this file the S3 endpoint falls open." >&2
    exit 1
fi

exec weed server "$@"
