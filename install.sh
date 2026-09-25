#!/bin/sh
set -eu
exec python3 "${0%/*}/lib/manage.py" install
