#!/bin/sh
# AlterTube release helper: tag the superproject and push.
# The "Release (signed)" workflow builds signed APKs and publishes them.
# Usage: sh release.sh v5.3.2-altertube
if [ -z "$1" ]; then
  echo "Usage: sh release.sh <tag>"
  exit 1
fi
git tag "$1"
git push origin "$1"
