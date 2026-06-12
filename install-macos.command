#!/bin/bash
# NexU 1.22 — инсталатор за macOS (Apple Silicon и Intel)
#
# Поставете този файл (заедно с останалите .command файлове) в папката на
# официалния NexU пакет от портала (там, където е nexu.jar) и го стартирайте:
#   cd <папката с nexu.jar> && bash install-macos.command
#
# Какво прави:
#   1. Изтегля Java 8 runtime с JavaFX (BellSoft Liberica JRE 8 "Full", x86_64)
#      в ./java-macos. Изисква се x86_64: вграденият в nexu.jar JNA (2018 г.)
#      няма arm64 библиотека за macOS, затова на Apple Silicon NexU работи
#      през Rosetta 2.
#   2. Адаптира JRE-то за съвременен macOS (JavaNativeFoundation пач).
#   3. Създава конфигурация за macOS (без блокиращи диалози, без мъртвите
#      сървъри на Nowina, с включен advanced mode за настройка на картата).
#   4. Сглобява самостоятелно приложение NexU.app (със собствен JRE и nexu.jar).
#   5. По желание: автоматично стартиране при вход (LaunchAgent).
#   6. Стартира NexU и проверява, че отговаря на http://localhost:9795.
#
# Опции:
#   --autostart    включва автостарт без питане
#   --no-autostart пропуска автостарта без питане
#   --no-launch    не стартира NexU в края
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$BUNDLE_DIR/NexU.app"
JRE_DIR="$BUNDLE_DIR/java-macos"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/lu.nowina.nexu.plist"

JRE_URL="https://github.com/bell-sw/Liberica/releases/download/8u492+9/bellsoft-jre8u492+9-macos-amd64-full.tar.gz"
JRE_SHA1="4d8cf0b799f6cf51125be25ea4add42408ac7a32"

# SHA-256 на официалния nexu.jar 1.22, разпространяван от egov.bg.
# При различен jar инсталацията продължава с предупреждение (други портали
# разпространяват свои билдове на NexU).
NEXU_JAR_SHA256="2594c43e8fc9417a61981751d8816bb50bd0b88c69b2ce01e5ae5b12a3af7d5a"

AUTOSTART="ask"
LAUNCH_AT_END=1
for arg in "$@"; do
  case "$arg" in
    --autostart) AUTOSTART="yes" ;;
    --no-autostart) AUTOSTART="no" ;;
    --no-launch) LAUNCH_AT_END=0 ;;
    *) echo "Непозната опция: $arg"; exit 1 ;;
  esac
done

echo "==> NexU 1.22 — инсталация за macOS"

if [ ! -f "$BUNDLE_DIR/nexu.jar" ]; then
  echo "ГРЕШКА: nexu.jar не е намерен в $BUNDLE_DIR"
  echo "Поставете файловете от това репо в папката на официалния NexU пакет"
  echo "(изтегля се от портала за е-услуги) и стартирайте отново."
  exit 1
fi

ACTUAL_JAR_SHA="$(shasum -a 256 "$BUNDLE_DIR/nexu.jar" | awk '{print $1}')"
if [ "$ACTUAL_JAR_SHA" != "$NEXU_JAR_SHA256" ]; then
  echo "ВНИМАНИЕ: nexu.jar се различава от официалния пакет на egov.bg (NexU 1.22)."
  echo "  очакван SHA-256: $NEXU_JAR_SHA256"
  echo "  намерен SHA-256: $ACTUAL_JAR_SHA"
  echo "Продължавам — но скриптът е тестван само с официалния билд 1.22."
fi

if [ "$(uname -m)" = "arm64" ] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "ГРЕШКА: Необходима е Rosetta 2 (NexU 1.22 изисква x86_64 Java)."
  echo "Инсталирайте я с:  softwareupdate --install-rosetta --agree-to-license"
  echo "и стартирайте инсталатора отново."
  exit 1
fi

# otool и install_name_tool идват с Command Line Tools — без тях JNF пачът
# (по-долу) не може да се приложи и NexU би крашвал тихо при стартиране.
if ! xcode-select -p >/dev/null 2>&1; then
  echo "ГРЕШКА: Необходими са Apple Command Line Tools (за otool/install_name_tool)."
  echo "Инсталирайте ги с:  xcode-select --install"
  echo "и стартирайте инсталатора отново."
  exit 1
fi

TMP="$(mktemp -d /tmp/nexu-install.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Изтегляне на Java 8 + JavaFX (~90 MB, BellSoft Liberica) ..."
curl -fL --progress-bar -o "$TMP/jre.tar.gz" "$JRE_URL"

echo "==> Проверка на контролната сума ..."
ACTUAL_SHA="$(shasum -a 1 "$TMP/jre.tar.gz" | awk '{print $1}')"
if [ "$ACTUAL_SHA" != "$JRE_SHA1" ]; then
  echo "ГРЕШКА: SHA1 не съвпада (очаквано $JRE_SHA1, получено $ACTUAL_SHA)."
  exit 1
fi

echo "==> Разархивиране ..."
mkdir -p "$TMP/extract"
tar -xzf "$TMP/jre.tar.gz" -C "$TMP/extract"
JAVA_BIN="$(find "$TMP/extract" -type f -name java -path "*/bin/java" -print -quit)"
if [ -z "$JAVA_BIN" ]; then
  echo "ГРЕШКА: bin/java не е намерен в архива."
  exit 1
fi
SRC_HOME="$(dirname "$(dirname "$JAVA_BIN")")"
if [ ! -f "$SRC_HOME/lib/ext/jfxrt.jar" ]; then
  echo "ГРЕШКА: JavaFX (lib/ext/jfxrt.jar) липсва в изтегления JRE."
  exit 1
fi

rm -rf "$JRE_DIR"
mv "$SRC_HOME" "$JRE_DIR"
echo "==> JRE инсталиран в: $JRE_DIR"
"$JRE_DIR/bin/java" -version 2>&1 | head -2

echo "==> Адаптиране на JRE за съвременен macOS (JavaNativeFoundation) ..."
# От macOS 11 (Big Sur) системните библиотеки, вкл. JavaNativeFoundation,
# съществуват само в dyld shared cache (не на диска), а Liberica JRE 8 търси
# JNF през @rpath в собствената си lib/ папка. Пренасочваме към абсолютния
# системен път, който dyld резолва през кеша.
JNF_ABS="/System/Library/Frameworks/JavaVM.framework/Frameworks/JavaNativeFoundation.framework/Versions/A/JavaNativeFoundation"
find "$JRE_DIR/lib" -name "*.dylib" | while read -r f; do
  if otool -L "$f" 2>/dev/null | grep -q "@rpath/JavaNativeFoundation"; then
    install_name_tool -change "@rpath/JavaNativeFoundation" "$JNF_ABS" "$f"
    codesign --force -s - "$f" 2>/dev/null || true
  fi
done
if otool -L "$JRE_DIR/lib/libosx.dylib" 2>/dev/null | grep -q "@rpath/JavaNativeFoundation"; then
  echo "ГРЕШКА: JavaNativeFoundation пачът не се приложи (otool/install_name_tool?)."
  echo "Уверете се, че Command Line Tools са инсталирани: xcode-select --install"
  exit 1
fi

echo "==> Конфигурация за macOS ..."
mkdir -p "$BUNDLE_DIR/macos-config"
CFG="$BUNDLE_DIR/macos-config/nexu-config.properties"
if ! unzip -p "$BUNDLE_DIR/nexu.jar" nexu-config.properties > "$CFG" 2>/dev/null; then
  rm -f "$CFG"
  echo "ГРЕШКА: този билд на nexu.jar няма nexu-config.properties — несъвместим е"
  echo "с този инсталатор. Ползвайте официалния пакет NexU 1.22 от egov.bg."
  exit 1
fi
cat >> "$CFG" <<'PROPS'

# --- macOS адаптация ---
# Pop-up диалозите СА нужни: настройката на нова смарткарта (PKCS#11) се
# показва само при advanced_mode_available && enable_pop_ups. Блокирането при
# старт идваше от JavaFX preloader-а, който е премахнат от стартера.
enable_pop_ups=true
advanced_mode_available=true
# Сървърът lab.nowina.solutions вече не съществува — без мрежови опити към него
enable_database_web_loader=false
send_anonymous_info_to_proxy=false
PROPS

# Ако NexU вече работи (преинсталация), спираме го — иначе старият процес
# остава на порт 9795 със старата конфигурация и новата никога не се активира.
if curl -s -m 2 http://127.0.0.1:9795/nexu-info >/dev/null 2>&1; then
  echo "==> Спиране на работещия NexU (ще бъде стартиран отново в края) ..."
  pkill -f "lu.nowina.nexu.NexuLauncher|nexu.jar" 2>/dev/null || true
  for _ in $(seq 1 10); do
    curl -s -m 1 http://127.0.0.1:9795/nexu-info >/dev/null 2>&1 || break
    sleep 1
  done
fi

echo "==> Сглобяване на NexU.app ..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/config"

cp "$BUNDLE_DIR/nexu.jar" "$APP_DIR/Contents/Resources/nexu.jar"
cp "$CFG" "$APP_DIR/Contents/Resources/config/nexu-config.properties"
cp -R "$JRE_DIR" "$APP_DIR/Contents/Resources/jre"

# Бележка: стартираме БЕЗ -Djavafx.preloader — NexUPreLoader показва блокиращ
# модален диалог при всяко предупреждение (напр. неуспешния опит за инсталиране
# на сертификат във Firefox) и спира зареждането, докато не се натисне OK.
cat > "$APP_DIR/Contents/MacOS/NexU" <<'LAUNCHER'
#!/bin/bash
CONTENTS="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$HOME/Library/Logs/NexU"
mkdir -p "$LOG_DIR"
exec "$CONTENTS/Resources/jre/bin/java" \
  -Dglass.accessible.force=false \
  -Dapple.awt.UIElement=true \
  -Dsun.security.smartcardio.library=/System/Library/Frameworks/PCSC.framework/PCSC \
  -cp "$CONTENTS/Resources/config:$CONTENTS/Resources/nexu.jar" \
  lu.nowina.nexu.NexuLauncher \
  >> "$LOG_DIR/nexu-console.log" 2>&1
LAUNCHER
chmod +x "$APP_DIR/Contents/MacOS/NexU"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>NexU</string>
	<key>CFBundleDisplayName</key>
	<string>NexU</string>
	<key>CFBundleIdentifier</key>
	<string>lu.nowina.nexu</string>
	<key>CFBundleVersion</key>
	<string>1.22</string>
	<key>CFBundleShortVersionString</key>
	<string>1.22</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleExecutable</key>
	<string>NexU</string>
	<key>CFBundleIconFile</key>
	<string>nexu.icns</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSAppNapIsDisabled</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© Nowina Solutions — EUPL v1.1</string>
</dict>
</plist>
PLIST

if unzip -p "$BUNDLE_DIR/nexu.jar" tray-icon.png > "$TMP/tray-icon.png" 2>/dev/null && [ -s "$TMP/tray-icon.png" ]; then
  ICONSET="$TMP/nexu.iconset"
  mkdir -p "$ICONSET"
  for SZ in 16 32 128 256 512; do
    sips -z $SZ $SZ "$TMP/tray-icon.png" --out "$ICONSET/icon_${SZ}x${SZ}.png" >/dev/null 2>&1 || true
  done
  iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/nexu.icns" 2>/dev/null || true
fi

xattr -dr com.apple.quarantine "$APP_DIR" "$JRE_DIR" 2>/dev/null || true
codesign --force --deep -s - "$APP_DIR" 2>/dev/null \
  && echo "==> NexU.app подписан (ad-hoc)" \
  || echo "ВНИМАНИЕ: ad-hoc подписването не успя — приложението пак би трябвало да работи."

if [ "$AUTOSTART" = "ask" ] && [ -t 0 ]; then
  read -r -p "Да се стартира ли NexU автоматично при влизане в системата? [y/N] " REPLY || REPLY=""
  case "$REPLY" in [yY]*) AUTOSTART="yes" ;; *) AUTOSTART="no" ;; esac
fi

if [ "$AUTOSTART" = "yes" ]; then
  # Пътят се вгражда в plist-а: ако преместите NexU.app, пуснете инсталатора
  # отново с --autostart, за да се обнови. XML-escape за специални знаци в пътя.
  APP_DIR_XML="$(printf '%s' "$APP_DIR" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>lu.nowina.nexu</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP_DIR_XML/Contents/MacOS/NexU</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/lu.nowina.nexu" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null \
    || launchctl load -w "$LAUNCH_AGENT" 2>/dev/null || true
  echo "==> Автостартът е включен ($LAUNCH_AGENT)"
  echo "    (ако преместите NexU.app, пуснете инсталатора отново с --autostart)"
fi

echo ""
echo "==> Инсталацията завърши успешно."
echo "    Приложение : $APP_DIR  (може да го преместите в /Applications)"
echo "    Стартиране : двоен клик на NexU.app или NexU-Startup.command"
echo "    Проверка   : http://localhost:9795/nexu-info"
echo ""
echo "СЛЕДВАЩА СТЪПКА: пуснете fix-https-cert-macos.command, за да работи"
echo "https://localhost:9895 (порталите проверяват NexU през него)."

if [ "$LAUNCH_AT_END" = "1" ]; then
  if ! curl -s -m 2 http://127.0.0.1:9795/nexu-info >/dev/null 2>&1; then
    echo "==> Стартиране на NexU ..."
    open "$APP_DIR"
  else
    echo "==> NexU вече е стартиран (вероятно от автостарта)."
  fi
  for _ in $(seq 1 30); do
    if curl -s -m 2 http://127.0.0.1:9795/nexu-info >/dev/null 2>&1; then
      echo "==> NexU работи: http://localhost:9795/nexu-info"
      echo "    Иконата на NexU е в лентата с менюта (горе вдясно)."
      exit 0
    fi
    sleep 1
  done
  echo "ВНИМАНИЕ: NexU не отговори на порт 9795 до 30 сек."
  echo "Проверете логовете: ~/Library/Logs/NexU/nexu-console.log и ~/.NexU/nexu.log"
fi
