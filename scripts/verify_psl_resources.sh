#!/bin/sh
set -eu

input=${1:?Usage: $0 <app-or-xcarchive>}

if [ -d "$input/Products/Applications" ]; then
    apps=$(find -L "$input/Products/Applications" -maxdepth 1 -type d -name '*.app' -print)
else
    apps=$input
fi

[ -n "$apps" ] || {
    echo "No app found under $input" >&2
    exit 1
}

status=0
for app in $apps; do
    frameworks=$(find -L "$app" -type d -name 'wBlockCoreService.framework' -print)
    if [ -z "$frameworks" ]; then
        echo "Missing wBlockCoreService.framework in $app" >&2
        status=1
        continue
    fi

    for framework in $frameworks; do
        resource_dir="$framework/Resources/swift-psl_PublicSuffixList.bundle/Contents/Resources"
        for resource in common.bin negated.bin asterisk.bin; do
            path="$resource_dir/$resource"
            if [ ! -r "$path" ] || [ ! -s "$path" ]; then
                echo "Missing or empty PSL resource: $path" >&2
                status=1
            fi
        done
    done
done

if [ "$status" -eq 0 ]; then
    echo "PASS: PSL resources present"
fi
exit "$status"