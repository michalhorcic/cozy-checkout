#!/bin/sh
# Runs migrations, then starts the Phoenix release server.
set -eu
cd -P -- "$(dirname -- "$0")"
./migrate
exec ./server
