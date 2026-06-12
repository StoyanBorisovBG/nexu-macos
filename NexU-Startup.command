#!/bin/bash
# NexU 1.22 — стартов скрипт за macOS (еквивалент на NexU-Startup.bat)
# Предпочита NexU.app (фонов режим); без него стартира java директно във фонов
# режим, така че Terminal прозорецът може да бъде затворен. Лог: nexu.log.txt.
set -u

BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"

if curl -s -m 2 http://127.0.0.1:9795/nexu-info >/dev/null 2>&1; then
  echo "NexU вече работи (http://localhost:9795). Изход."
  exit 0
fi

if [ -d "$BUNDLE_DIR/NexU.app" ]; then
  echo "Стартиране на NexU.app ..."
  open "$BUNDLE_DIR/NexU.app"
  exit 0
fi

if [ ! -f "$BUNDLE_DIR/nexu.jar" ]; then
  echo "ГРЕШКА: nexu.jar липсва в $BUNDLE_DIR — сложете скрипта в папката на NexU пакета."
  exit 1
fi

JAVA=""
if [ -x "$BUNDLE_DIR/java-macos/bin/java" ]; then
  JAVA="$BUNDLE_DIR/java-macos/bin/java"
fi

if [ -z "$JAVA" ]; then
  echo "ГРЕШКА: Не е намерена Java 8 с JavaFX (x86_64)."
  echo "Стартирайте първо install-macos.command от тази папка."
  echo "(Системна arm64 Java не върши работа — вграденият в nexu.jar JNA"
  echo " няма arm64 библиотека; NexU 1.22 изисква x86_64 Java през Rosetta 2.)"
  exit 1
fi

CP="$BUNDLE_DIR/nexu.jar"
if [ -f "$BUNDLE_DIR/macos-config/nexu-config.properties" ]; then
  CP="$BUNDLE_DIR/macos-config:$CP"
fi

echo "Стартиране на NexU във фонов режим с: $JAVA"
nohup "$JAVA" \
  -Dglass.accessible.force=false \
  -Dapple.awt.UIElement=true \
  -Dsun.security.smartcardio.library=/System/Library/Frameworks/PCSC.framework/PCSC \
  -cp "$CP" \
  lu.nowina.nexu.NexuLauncher \
  >> "$BUNDLE_DIR/nexu.log.txt" 2>&1 &
disown
echo "NexU стартира — прозорецът на Terminal може да бъде затворен."
echo "Проверка: http://localhost:9795/nexu-info"
