#!/bin/bash
# Thin wrapper kept for muscle memory; the implementation lives in
# update_locales.py. See that file (or --help) for options.
exec python3 "$(dirname "$0")/update_locales.py" "$@"
