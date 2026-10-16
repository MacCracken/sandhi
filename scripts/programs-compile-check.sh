#!/bin/bash
# Compile-only sweep over programs/*.cyr.
#
# CI runs smoke and the seven live gates; every other program (the probes, the
# dynlib experiments, the 7-arg repro) is built by hand when someone needs it,
# so it rots silently. At 1.10.0 nine of them had not compiled since
# src/obs/prof.cyr landed at 1.2.5 (CHANGELOG [1.10.0]).
#
# Fails on a program that does not build, or that builds with an "undefined
# function" warning: an include list that no longer covers what the program
# reaches, the drift this exists to catch. Other warnings are printed and do
# not fail, so an unrelated toolchain warning does not block every change.
#
# Usage: scripts/programs-compile-check.sh   (binaries go in build/programs/,
# which is gitignored). CHANGELOG [1.11.2]

set -uo pipefail
cd "$(dirname "$0")/.."

mkdir -p build/programs
fail=0
n=0
for f in programs/*.cyr; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .cyr)
    n=$((n + 1))
    out=$(cyrius build "$f" "build/programs/$name" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "$out"
        echo "programs: FAIL: $f does not build (exit $rc)"
        fail=1
        continue
    fi
    if echo "$out" | grep -qi "warning.*undefined"; then
        echo "$out" | grep -i "warning"
        echo "programs: FAIL: $f builds with an undefined-function warning (include-list drift)"
        fail=1
        continue
    fi
    if echo "$out" | grep -qi "warning"; then
        echo "$out" | grep -i "warning"
        echo "programs: note: $f builds with the warnings above"
    fi
done
if [ $n -eq 0 ]; then
    echo "programs: FAIL: no programs/*.cyr found"
    exit 1
fi
if [ $fail -ne 0 ]; then
    exit 1
fi
echo "programs: all $n programs/*.cyr build with no undefined-function warning"
