#!/usr/bin/env bash
set -euo pipefail

input=${1:?Usage: $0 <app-or-xcarchive>}
apps=()

if [[ -d "$input/Products/Applications" ]]; then
    while IFS= read -r -d '' app; do
        apps+=("$app")
    done < <(find -L "$input/Products/Applications" -maxdepth 1 -type d -name '*.app' -print0)
else
    apps=("$input")
fi

((${#apps[@]} > 0)) || {
    echo "No app found under $input" >&2
    exit 1
}

resource_dir_is_valid() {
    local resource_dir=$1
    [[ -d "$resource_dir" ]] || return 1
    for resource in common.bin negated.bin asterisk.bin; do
        local path="$resource_dir/$resource"
        [[ -r "$path" && -s "$path" ]] || return 1
    done
}

status=0
for app in "${apps[@]}"; do
    framework_count=0
    while IFS= read -r -d '' framework; do
        framework_count=$((framework_count + 1))
        framework_resource_dirs=(
            "$framework/Resources/swift-psl_PublicSuffixList.bundle/Contents/Resources"
            "$framework/swift-psl_PublicSuffixList.bundle/Contents/Resources"
            "$framework/swift-psl_PublicSuffixList.bundle/Contents"
            "$framework/swift-psl_PublicSuffixList.bundle"
        )
        owner_bundle_root=$(dirname "$(dirname "$framework")")
        framework_resource_dirs+=(
            "$owner_bundle_root/swift-psl_PublicSuffixList.bundle/Contents/Resources"
            "$owner_bundle_root/swift-psl_PublicSuffixList.bundle/Contents"
            "$owner_bundle_root/swift-psl_PublicSuffixList.bundle"
        )

        resource_dir=""
        for candidate in "${framework_resource_dirs[@]}"; do
            if resource_dir_is_valid "$candidate"; then
                resource_dir="$candidate"
                break
            fi
        done

        if [[ -z "$resource_dir" ]]; then
            echo "Missing or incomplete PSL resource bundle for $framework" >&2
            status=1
        fi
    done < <(find -L "$app" -type d -name 'wBlockCoreService.framework' -print0)

    if ((framework_count == 0)); then
        echo "Missing wBlockCoreService.framework in $app" >&2
        status=1
    fi
done

if ((status == 0)); then
    echo "PASS: PSL resources present"
fi
exit "$status"