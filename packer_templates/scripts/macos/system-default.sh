#!/bin/sh
#
# @file system-default.sh
# @brief Configures macOS guest system defaults for Bento Vagrant boxes
# @description
#   Disables screensavers, prevents system and display sleep, configures passwordless
#   sudo for the vagrant user, enables automatic GUI login, disables screen lock,
#   and suppresses crash reporter dialogs.
#

set -eu

PlistBuddy="/usr/libexec/PlistBuddy"

echo "==> Configuring screensaver and power management settings"
# Disable loginwindow screensaver to save CPU cycles
$PlistBuddy -c 'Add :loginWindowIdleTime integer 0' "/Library/Preferences/com.apple.screensaver.plist" 2>/dev/null || true
defaults -currentHost write com.apple.screensaver idleTime 0

# Prevent the VM from sleeping
systemsetup -setdisplaysleep Off 2>/dev/null || true
systemsetup -setsleep Off 2>/dev/null || true
systemsetup -setcomputersleep Off 2>/dev/null || true

echo "==> Configuring sudo privileges for vagrant user"
if [ ! -d /etc/sudoers.d ]; then
  mkdir -p /etc/sudoers.d
  chmod 0750 /etc/sudoers.d
fi
echo 'vagrant ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/vagrant
chmod 0440 /etc/sudoers.d/vagrant

echo "==> Enabling Remote Login (SSH)"
systemsetup -setremotelogin on 2>/dev/null || true

echo "==> Enabling automatic GUI login for the vagrant user"
sysadminctl -autologin set -userName vagrant -password vagrant 2>/dev/null || true

echo "==> Disabling screen lock"
sysadminctl -screenLock off -password vagrant 2>/dev/null || true

echo "==> Suppressing crash reporter dialogs"
defaults write com.apple.CrashReporter DialogType none 2>/dev/null || true
