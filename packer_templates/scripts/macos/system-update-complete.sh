#!/bin/sh
#
# @file system-update-complete.sh
# @brief Waits for any pending background system software updates to conclude
# @description
#   Inspects software update logs and waits for pending post-install actions or restarts.
#

set -eu

log_file="${HOME}/Library/Logs/packer_softwareupdate.log"
if [ -f "${log_file}" ] && grep -q "Action.*restart" "${log_file}"; then
  echo "==> Waiting for post-update setup assistant completion..."
  tail -f /var/log/install.log 2>/dev/null | sed '/.*Setup Assistant.*ISAP.*Done.*/ q' | grep ISAP || true
  sleep 180
fi

echo "==> Software update checks completed"
