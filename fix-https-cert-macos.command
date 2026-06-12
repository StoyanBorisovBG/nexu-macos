#!/bin/bash
# NexU 1.22 — поправка на HTTPS сертификата за съвременни браузъри (macOS)
#
# Проблем: NexU генерира server сертификат с 10-годишна валидност. Apple
# изисква TLS сертификатите да са валидни ≤825 дни — Safari/Chrome го
# отхвърлят дори след доверяване и порталите решават, че NexU не е стартиран.
#
# Решение: генерира локално CA + сертификат за localhost (SAN, EKU serverAuth,
# 820 дни), подменя ги в ~/.NexU/web-server-keystore.jks (alias "localhost",
# парола "password" — стандартните на NexU), доверява CA-то в login keychain
# (macOS ще поиска паролата ви) и рестартира NexU.
#
# При изтичане на сертификата (~2 г.) просто пуснете скрипта отново.
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
NEXU_HOME="$HOME/.NexU"
KS="$NEXU_HOME/web-server-keystore.jks"
# Фиксиран системен openssl (LibreSSL): Homebrew/Conda OpenSSL 3.x в PATH
# произвежда PKCS12 формат, който keytool на Java 8 не чете.
OPENSSL="/usr/bin/openssl"

KEYTOOL=""
for CAND in "$BUNDLE_DIR/java-macos/bin/keytool" \
            "$BUNDLE_DIR/NexU.app/Contents/Resources/jre/bin/keytool" \
            "/Applications/NexU.app/Contents/Resources/jre/bin/keytool"; do
  [ -x "$CAND" ] && KEYTOOL="$CAND" && break
done
[ -z "$KEYTOOL" ] && { echo "ГРЕШКА: keytool не е намерен — пуснете първо install-macos.command"; exit 1; }
[ -f "$KS" ] && cp "$KS" "$KS.bak"

restore_backup() {
  if [ -f "$KS.bak" ]; then
    mv "$KS.bak" "$KS"
    echo "Старият keystore е възстановен от резервното копие."
  fi
}

T="$(mktemp -d /tmp/nexu-cert.XXXXXX)"
trap 'rm -rf "$T"' EXIT

echo "==> Генериране на локално CA и сертификат за localhost ..."
"$OPENSSL" genrsa -out "$T/ca.key" 2048 2>/dev/null
printf '[req]\ndistinguished_name=dn\nx509_extensions=v3ca\nprompt=no\n[dn]\nCN=NexU Local CA\nO=NexU\n[v3ca]\nbasicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n' > "$T/ca.cnf"
"$OPENSSL" req -x509 -new -key "$T/ca.key" -days 3650 -sha256 -out "$T/ca.pem" -config "$T/ca.cnf"

"$OPENSSL" genrsa -out "$T/leaf.key" 2048 2>/dev/null
"$OPENSSL" req -new -key "$T/leaf.key" -out "$T/leaf.csr" -subj "/CN=localhost/O=NexU/OU=webserver"
printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer\n' > "$T/leaf.ext"
"$OPENSSL" x509 -req -in "$T/leaf.csr" -CA "$T/ca.pem" -CAkey "$T/ca.key" -CAcreateserial -days 820 -sha256 -out "$T/leaf.pem" -extfile "$T/leaf.ext" 2>/dev/null

echo "==> Подмяна на $KS ..."
"$OPENSSL" pkcs12 -export -name localhost -inkey "$T/leaf.key" -in "$T/leaf.pem" -certfile "$T/ca.pem" -out "$T/bundle.p12" -passout pass:password
mkdir -p "$NEXU_HOME"
rm -f "$KS"
if ! "$KEYTOOL" -importkeystore -srckeystore "$T/bundle.p12" -srcstoretype PKCS12 -srcstorepass password \
     -destkeystore "$KS" -deststoretype JKS -deststorepass password -destkeypass password \
     -alias localhost 2>"$T/keytool.err"; then
  echo "ГРЕШКА: keytool не успя да създаде keystore:"
  cat "$T/keytool.err"
  restore_backup
  exit 1
fi
if ! "$KEYTOOL" -list -keystore "$KS" -storepass password 2>/dev/null | grep -q localhost; then
  echo "ГРЕШКА: новият keystore е невалиден."
  restore_backup
  exit 1
fi

"$OPENSSL" x509 -in "$T/ca.pem" -outform DER -out "$NEXU_HOME/NexU-localCA.der"

echo "==> Доверяване на CA-то в login keychain (macOS ще поиска парола) ..."
# Чистим стари "NexU Local CA" от предишни пускания, за да не се трупат.
while security delete-certificate -c "NexU Local CA" >/dev/null 2>&1; do :; done
security add-certificate "$NEXU_HOME/NexU-localCA.der" 2>/dev/null || true
if ! security add-trusted-cert -p ssl "$NEXU_HOME/NexU-localCA.der"; then
  echo "ГРЕШКА: доверяването беше отказано — без него https://localhost:9895 няма"
  echo "да работи. Пуснете скрипта отново и потвърдете с паролата си."
  restore_backup
  exit 1
fi
rm -f "$KS.bak"

echo "==> Рестартиране на NexU ..."
pkill -f "nexu.jar|NexuLauncher" 2>/dev/null || true
sleep 2
if [ -d "$BUNDLE_DIR/NexU.app" ]; then
  open "$BUNDLE_DIR/NexU.app"
elif ! open -b lu.nowina.nexu 2>/dev/null; then
  echo "ВНИМАНИЕ: NexU.app не е намерен — стартирайте го ръчно, после проверете"
  echo "https://localhost:9895/nexu-info в браузъра."
  exit 0
fi
UP=0
for _ in $(seq 1 30); do
  if curl -s -m 2 http://127.0.0.1:9795/nexu-info >/dev/null 2>&1; then UP=1; break; fi
  sleep 1
done
if [ "$UP" != "1" ]; then
  echo "ВНИМАНИЕ: NexU не отговори на порт 9795 — проверете логовете:"
  echo "~/Library/Logs/NexU/nexu-console.log и ~/.NexU/nexu.log"
  exit 1
fi

echo "==> Проверка на новия сертификат ..."
if ! echo | "$OPENSSL" s_client -connect 127.0.0.1:9895 2>/dev/null | "$OPENSSL" x509 -outform PEM > "$T/served.pem" 2>/dev/null; then
  echo "ВНИМАНИЕ: https://localhost:9895 не отговаря — проверете логовете на NexU."
  exit 1
fi
if security verify-cert -c "$T/served.pem" -p ssl >/dev/null 2>&1; then
  echo "==> УСПЕХ: https://localhost:9895 вече е доверен. Обновете страницата на портала."
else
  echo "ВНИМАНИЕ: сертификатът още не минава проверката. Изход:"
  security verify-cert -c "$T/served.pem" -p ssl 2>&1 || true
fi
