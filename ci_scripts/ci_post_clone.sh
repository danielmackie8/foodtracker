#!/bin/sh
# Xcode Cloud runs this after cloning. Every TestFlight upload needs a higher build
# number, so use Xcode Cloud's own build counter.
set -e
if [ -n "$CI_BUILD_NUMBER" ]; then
  sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;/" \
    "$CI_PRIMARY_REPOSITORY_PATH/Sage.xcodeproj/project.pbxproj"
  echo "Build number set to $CI_BUILD_NUMBER"
fi
