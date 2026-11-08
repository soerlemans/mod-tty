#!/usr/bin/env bash

set -e

cd "$(dirname "$0")"
pwd

./gen_libs.sh
odin build src -out:modtty
./modtty
