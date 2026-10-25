#!/bin/sh
# Downloads the CarPlay Apps tray's real app icons (App Store artwork, 512 px) into
# Forx/Assets.xcassets as appicon-<id>.imageset. Run on the Mac from ios/: sh tools/fetch-app-icons.sh
# Phone has no App Store page: it keeps its SF Symbol. Personal use only.
set -eu
cd "$(dirname "$0")/.."
assets=Forx/Assets.xcassets
for pair in youtubemusic:1017492454 spotify:324684580 applemusic:1108187390 applemaps:915056765 \
            podcasts:525463029 googlemaps:585027354 waze:323229106; do
  name=${pair%%:*}; id=${pair##*:}
  url=$(curl -fsS "https://itunes.apple.com/lookup?id=$id&country=us" |
        python3 -c 'import json,sys; r=json.load(sys.stdin)["results"]; print(r[0]["artworkUrl512"] if r else "")')
  [ -n "$url" ] || { echo "no artwork for $name"; continue; }
  set_dir="$assets/appicon-$name.imageset"; mkdir -p "$set_dir"
  curl -fsS "$url" -o "$set_dir/appicon-$name.png"
  cat > "$set_dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "appicon-$name.png", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  echo "$name ← $url"
done
