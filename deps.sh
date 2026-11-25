#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"
cd deps/
pwd

if [[ -f "build/libjanet.a" && -f "build/_deps/vterm-src/.libs/libvterm.a" ]];
then
		echo "[+] Janet present"
		echo "[+] libvterm present."
		echo "[!] All deps are present, skipping rebuild."
		exit 0
fi

# Build and get dependencies.
mkdir -p build/
cmake -S . -B build/ -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j4
