#!/bin/bash
# Every helper test, in Node and in Qt's JS engine (they differ: Qt silently never matches a regex lookbehind).
cd "$(dirname "$0")" || exit 1
node test-otp.mjs || exit 1
QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="qml=true;js=true;qt.*=false" \
  timeout 20 /usr/lib/qt6/bin/qml qt.qml 2>&1 | sed 's/^qml: //'
exit "${PIPESTATUS[0]}"
