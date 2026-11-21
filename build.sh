#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"
pwd

BIN_OUT=modtty
DEBUG=0
OPTIMIZATION_LEVEL=speed

while getopts ":do:h-:" opt; do
    case "$opt" in
        d)
            DEBUG=1
            ;;

        o)
            OPTIMIZATION_LEVEL="$OPTARG"
            ;;
        -)
            case "$OPTARG" in
                debug)
                    DEBUG=1
                    ;;
                help)
                    echo "Usage: $0 [-d|--debug]"
                    exit 0
                    ;;
                *)
                    echo "Unknown option: --$OPTARG" >&2
                    exit 1
                    ;;
            esac
            ;;
        h)
            echo "Usage: $0 [-o] <none,minimal,size,speed,aggressive> [-d|--debug]"
            exit 0
            ;;
        \?)
            echo "Unknown option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

# TODO: Add option to use system deps.
./deps.sh

if [[ "$DEBUG" -eq 1 ]]; then
		echo "Building $BIN_OUT in DEBUG."
		set -x
    odin build src -debug -out:"$BIN_OUT"
else
		echo "Building $BIN_OUT in RELEASE."
		set -x
    odin build src -o:"$OPTIMIZATION_LEVEL" -out:"$BIN_OUT"
fi

