#!/bin/sh
# unit-name-lint.sh - "one main type per unit" for the built-in layer and the
# compiler tree (SH-120).
#
# A `.h.ct` unit is named after its main type. Auxiliary records that the main
# type needs (`ct_str_hdr`, `ct_buf`, `ct_Box_hdr`) and the two container
# companions (`MapEntry`, and `Map` sharing `Vec.h.ct` since PH-29) are allowed;
# anything else is a second main type and fails. String.h.ct is the one unit
# that legitimately carries an auxiliary record with a non-`ct_` name? No --
# `ct_str_hdr` follows the `ct_` convention.
#
# Usage: sh selfhost/unit-name-lint.sh <dir>...
# Exit: 0 all units one main type; 1 a violation.
set -u

bad=0
for dir in "$@"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.h.ct; do
        [ -f "$f" ] || continue
        base=$(basename "$f" .h.ct)
        mains=""
        nmain=0
        has_base=0
        while IFS= read -r line; do
            case "$line" in
                "pub struct "*|"struct "*|"pub union "*|"union "*|"pub enum "*|"enum "*) ;;
                *) continue ;;
            esac
            name=$(printf '%s\n' "$line" | sed -E 's/^(pub )?(struct|union|enum) ([A-Za-z_][A-Za-z0-9_]*).*/\3/')
            case "$name" in
                ct_*|MapEntry) continue ;;            # auxiliary record
            esac
            nmain=$((nmain + 1))
            mains="$mains $name"
            [ "$name" = "$base" ] && has_base=1
        done <"$f"
        # Vec.h.ct carries the container pair Vec + Map by design (PH-29).
        if [ "$base" = "Vec" ] && [ "$nmain" = "2" ] \
           && printf '%s\n' "$mains" | grep -qw Vec \
           && printf '%s\n' "$mains" | grep -qw Map; then
            nmain=1
        fi
        if [ "$has_base" -ne 1 ]; then
            printf 'FAIL unit-name: %s declares no type named %s\n' "$f" "$base" >&2
            bad=1
        elif [ "$nmain" -ne 1 ]; then
            printf 'FAIL unit-name: %s has %d main types (%s)\n' "$f" "$nmain" "$mains" >&2
            bad=1
        fi
    done
done
[ "$bad" -eq 0 ] && echo "unit-name lint: every .h.ct unit has one main type"
exit "$bad"
