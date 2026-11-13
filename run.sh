#!/bin/sh
# Launch TURBO EDIT from the project directory so WELCOME.TXT is found.
cd "$(dirname "$0")" || exit 1
exec ./build/bin/egaedit "$@"
