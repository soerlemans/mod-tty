#!/usr/bin/env bash

set -e

cd "$(dirname "$0")"
pwd

mkdir -p out/

if ! [[ -f "out/janet.a" ]];
then
	# Compile Janet to out.
	echo "[+] Compiling Janet."
	gcc -c -O2 -fPIC src/lib/janet-1.43.0/janet.c -Isrc/lib/janet-1.43.0/ -o out/janet.o

	# Use Apple's native static library tool on macOS to avoid GNU ar index clashes
    if [[ "$OSTYPE" == "darwin"* ]]; then
        libtool -static -o out/janet.a out/janet.o
    else
        ar rcs out/janet.a out/janet.o
	fi
	rm out/janet.o
	echo "[+] Archive made janet.a."
else
	echo "[+] Janet already compiled."
fi
