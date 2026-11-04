#!/bin/bash
# Double-click (or right-click > Open) to build and install the Flip Calendar screen saver.
cd "$(dirname "$0")"
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple's free developer tools are needed once. A window will open: click Install, wait until it finishes, then double-click Install.command again."
  xcode-select --install
  read -n 1 -s -r -p "Press any key to close…"
  exit 0
fi
bash ./build.sh && echo && echo "Done. In the window that opened, click Install, then choose Flip Calendar in System Settings > Screen Saver."
read -n 1 -s -r -p "Press any key to close…"
