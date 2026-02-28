#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:-MyApp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -d android || -d ios ]]; then
  echo "android/ or ios/ already exists. Remove them first if you want to re-run setup."
  exit 1
fi

echo "Generating native projects for app name: $APP_NAME"
npx @react-native-community/cli@latest init "$APP_NAME" --skip-install --pm npm

if [[ ! -d "$APP_NAME/android" || ! -d "$APP_NAME/ios" ]]; then
  echo "Expected $APP_NAME/android and $APP_NAME/ios from init. Aborting."
  exit 1
fi

mv "$APP_NAME/android" .
mv "$APP_NAME/ios" .
rm -rf "$APP_NAME"

# Keep app.json in sync with native app name (used by AppRegistry.registerComponent)
node -e "
const fs = require('fs');
const path = require('path');
const name = '$APP_NAME';
const p = path.join(__dirname, 'app.json');
const j = JSON.parse(fs.readFileSync(p, 'utf8'));
j.name = name;
j.displayName = j.displayName || name;
fs.writeFileSync(p, JSON.stringify(j, null, 2) + '\n');
"

echo "Done. android/ and ios/ are ready. Run: pnpm install"
echo "Then: pnpm start (Metro) and pnpm android or pnpm ios"
