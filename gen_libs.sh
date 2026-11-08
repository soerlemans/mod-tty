#!/usr/bin/env bash


cd "$(dirname "$0")"
pwd

mkdir -p out/

if ! [[ -f "out/janet.a" ]];
then
	# Compile Janet to out.
	echo "[+] Compiling Janet."
	gcc -c src/lib/janet-1.43.0/janet.c -Isrc/lib/janet-1.43.0/janet.h -O2 -o out/janet.o
	ar rcs out/janet.a out/janet.o
else
	echo "[+] Janet already compiled."
fi
