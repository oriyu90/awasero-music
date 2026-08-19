#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
app_dir="$build_dir/合わせろMusic.app"
module_cache="$build_dir/ModuleCache"

mkdir -p "$module_cache"
cd "$project_dir"
CLANG_MODULE_CACHE_PATH="$module_cache" SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift build -c release --disable-sandbox

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/release/AwaseroMusic" "$app_dir/Contents/MacOS/AwaseroMusic"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE.txt"
sign_identity="${AWASERO_SIGN_IDENTITY:--}"
codesign --force --deep --options runtime --sign "$sign_identity" "$app_dir"

echo "$app_dir"
