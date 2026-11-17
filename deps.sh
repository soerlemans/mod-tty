#!/usr/bin/env bash

set -e

cd "$(dirname "$0")"
cd deps/
pwd

# Build and get dependencies.
mkdir -p build/
cmake -S . -B build/ -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j4
