#!/usr/bin/env bash

set -e

cd "$(dirname "$0")"
pwd

./deps.sh
odin build src -debug -out:modtty
