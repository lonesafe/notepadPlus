#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: $0 input.ico output.icns" >&2
	exit 2
fi

input=$1
output=$2
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
iconset="$work_dir/AppIcon.iconset"
base="$work_dir/base.png"
mkdir -p "$iconset"

sips -s format png "$input" --out "$base" >/dev/null

make_icon() {
	size=$1
	name=$2
	sips -z "$size" "$size" "$base" --out "$iconset/$name" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

mkdir -p "$(dirname "$output")"
iconutil -c icns "$iconset" -o "$output"
