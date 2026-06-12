#!/bin/bash
# NexU — инсталатор за macOS (Apple Silicon и Intel)
#
# Самодостатъчен: ако nexu.jar липсва до скрипта, изтегля официалния NexU
# пакет от release сървъра на Nowina (същия, към който линкват порталите)
# с проверка на SHA-256. Може и да поставите скриптовете в папката на вече
# изтеглен официален пакет — тогава се ползва вашият nexu.jar.
#
# Стартиране (изтеглените от интернет скриптове са под карантина — затова
# през Terminal):
#   bash install-macos.command
#
# Какво прави:
#   1. Ако няма nexu.jar — изтегля официалния пакет (SHA-256 проверка).
#   2. Изтегля Java 8 runtime с JavaFX (BellSoft Liberica JRE 8 "Full", x86_64)
#      в ./java-macos. Изисква се x86_64: вграденият в nexu.jar JNA (2018 г.)
#      няма arm64 библиотека за macOS, затова на Apple Silicon NexU работи
#      през Rosetta 2.
#   3. Адаптира JRE-то за съвременен macOS (JavaNativeFoundation пач).
#   4. Създава конфигурация за macOS (без блокиращи диалози, без висящите
#      мрежови услуги на Nowina, с включен advanced mode за настройка на картата).
#   5. Сглобява самостоятелно приложение NexU.app (със собствен JRE и nexu.jar).
#   6. По желание: автоматично стартиране при вход (LaunchAgent).
#   7. Стартира NexU и проверява, че отговаря на http://localhost:9795.
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

# Официален NexU пакет (release сървърът на Nowina, линкван от порталите).
NEXU_BUNDLE_URL="https://lab.nowina.solutions/nexu-releases/nexu-bundle-1.24.zip"
NEXU_BUNDLE_ZIP_SHA256="785c178ed83ba7852337d90a84c47dab2e135c2112d5f5b1148430fa017550d8"

# Познати официални nexu.jar билдове (SHA-256). При друг jar инсталацията
# продължава с предупреждение (някои портали разпространяват свои билдове).
JAR_SHA_122="2594c43e8fc9417a61981751d8816bb50bd0b88c69b2ce01e5ae5b12a3af7d5a"
JAR_SHA_124="48ae478c7d309dfacecc049c3d0c53473d92ecb7b0c0a886c50ab32f79761256"

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

echo "==> NexU — инсталация за macOS"

if [ "$(uname -m)" = "arm64" ] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "ГРЕШКА: Необходима е Rosetta 2 (NexU изисква x86_64 Java)."
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

if [ ! -f "$BUNDLE_DIR/nexu.jar" ]; then
  echo "==> nexu.jar не е намерен — изтегляне на официалния NexU пакет (~85 MB) ..."
  echo "    Източник: $NEXU_BUNDLE_URL"
  curl -fL --progress-bar -o "$TMP/nexu-bundle.zip" "$NEXU_BUNDLE_URL"
  ZIP_SHA="$(shasum -a 256 "$TMP/nexu-bundle.zip" | awk '{print $1}')"
  if [ "$ZIP_SHA" != "$NEXU_BUNDLE_ZIP_SHA256" ]; then
    echo "ГРЕШКА: SHA-256 на изтегления пакет не съвпада с очаквания:"
    echo "  очакван: $NEXU_BUNDLE_ZIP_SHA256"
    echo "  получен: $ZIP_SHA"
    echo "От съображения за сигурност инсталацията спира (компонентът подписва с КЕП)."
    exit 1
  fi
  mkdir -p "$TMP/bundle"
  unzip -q "$TMP/nexu-bundle.zip" -d "$TMP/bundle"
  JAR_SRC="$(find "$TMP/bundle" -name nexu.jar -print -quit)"
  if [ -z "$JAR_SRC" ]; then
    echo "ГРЕШКА: nexu.jar не е намерен в изтегления пакет."
    exit 1
  fi
  cp "$JAR_SRC" "$BUNDLE_DIR/nexu.jar"
  echo "==> nexu.jar (официален билд) е поставен в $BUNDLE_DIR"
fi

ACTUAL_JAR_SHA="$(shasum -a 256 "$BUNDLE_DIR/nexu.jar" | awk '{print $1}')"
case "$ACTUAL_JAR_SHA" in
  "$JAR_SHA_122"|"$JAR_SHA_124") : ;;
  *)
    echo "ВНИМАНИЕ: nexu.jar не съвпада с познатите официални билдове (1.22, 1.24)."
    echo "  намерен SHA-256: $ACTUAL_JAR_SHA"
    echo "Продължавам — но скриптът е тестван само с официалните билдове."
    ;;
esac

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
  echo "с този инсталатор. Ползвайте официален пакет NexU 1.22/1.24."
  exit 1
fi
cat >> "$CFG" <<'PROPS'

# --- macOS адаптация ---
# Pop-up диалозите СА нужни: настройката на нова смарткарта (PKCS#11) се
# показва само при advanced_mode_available && enable_pop_ups. Блокирането при
# старт идваше от JavaFX preloader-а, който е премахнат от стартера.
enable_pop_ups=true
advanced_mode_available=true
# Услугата /nexu на lab.nowina.solutions не отговаря (заявките висят и бавеха
# старта с ~45 сек) — изключваме базата от интернет и телеметрията.
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

NEXU_VER="$(unzip -p "$BUNDLE_DIR/nexu.jar" META-INF/maven/lu.nowina.apps/nexu-standalone/pom.properties 2>/dev/null | grep '^version=' | cut -d= -f2 || true)"
[ -n "$NEXU_VER" ] || NEXU_VER="1.x"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
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
	<string>$NEXU_VER</string>
	<key>CFBundleShortVersionString</key>
	<string>$NEXU_VER</string>
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
