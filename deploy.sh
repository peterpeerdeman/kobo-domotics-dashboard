#!/bin/sh
# push dash.sh and dash.env to the Kobo over scp
# host, port, user and target folder live in deploy.env (not checked in) - see deploy.env.example

cd "$(dirname "$0")" || exit 1

[ -f deploy.env ] || { echo "missing deploy.env - copy deploy.env.example and fill it in" >&2; exit 1; }
. ./deploy.env
[ -f dash.env ] || { echo "missing dash.env - copy dash.env.example and fill it in" >&2; exit 1; }

: "${KOBO_HOST:?set KOBO_HOST in deploy.env}"
: "${KOBO_DIR:?set KOBO_DIR in deploy.env}"

scp -P "${KOBO_PORT:-22}" dash.sh dash.env "${KOBO_USER:-root}@$KOBO_HOST:$KOBO_DIR/" || exit 1

echo "deployed to $KOBO_HOST:$KOBO_DIR - restart the dashboard to pick it up"
