#!/bin/sh
#
# @file disable_auto_update.sh
# @brief Disables macOS automated software updates and background downloads
# @description
#   Suppresses background software update checks, critical config downloads,
#   automatic app store updates, and automated restarts on macOS guests.
#

set -eu

echo "==> Disabling automatic software updates"
osascript -e 'tell application "System Settings" to quit' 2>/dev/null || true
osascript -e 'tell application "System Preferences" to quit' 2>/dev/null || true

softwareupdate --schedule off 2>/dev/null || true
defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticCheckEnabled -bool false
defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticDownload -bool false
defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist ConfigDataInstall -bool false
defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist CriticalUpdateInstall -bool false
defaults write /Library/Preferences/com.apple.commerce.plist AutoUpdateRestartRequired -bool false
defaults write /Library/Preferences/com.apple.commerce.plist AutoUpdate -bool false
