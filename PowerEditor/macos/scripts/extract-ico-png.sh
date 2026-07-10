#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: $0 input.ico output.png" >&2
	exit 2
fi

input=$1
output=$2
image_size=$(od -An -tu4 -j14 -N4 "$input" | tr -d ' ')
image_offset=$(od -An -tu4 -j18 -N4 "$input" | tr -d ' ')

dd if="$input" of="$output" bs=1 skip="$image_offset" count="$image_size" 2>/dev/null
