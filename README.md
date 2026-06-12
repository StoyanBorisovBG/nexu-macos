# NexU за macOS — подписване с КЕП в българските е-услуги

**Неофициална адаптация на NexU 1.22 за съвременен macOS (включително Apple Silicon).**

Порталите за електронни услуги (egov.bg, НАП, НОИ и др.) изискват локалния
компонент **NexU** за подписване с физически КЕП (смарткарта). Официално
порталът предлага NexU само за Windows и за „MacOS 11" — стар билд, който не
работи на съвременните Mac компютри. Това репо съдържа скриптове, които правят
официалния NexU 1.22 пакет работещ на съвременен macOS.

**Тествано в реални условия**: вход и квалифициран подпис в egov.bg / eAuth с
B-Trust (БОРИКА) карта на **macOS 26 / Apple Silicon (M-чип)**. Проектирано е
да работи и на Intel и на по-стари версии (macOS 11+) — подходът там е
технически обоснован, но непроверен; обратна връзка през Issues е добре дошла.

> ⚠️ Това е общностен проект, не е свързан с Nowina Solutions, БОРИКА,
> „Информационно обслужване" или държавната администрация. Ползвате го на своя
> отговорност. Репото **не съдържа** самия NexU — него го изтегляте от
> официалния портал.

---

## Бърз старт

**Изисквания:** macOS 11+ (тествано на 26), смарткарта с КЕП + четец,
инсталиран драйвер за картата (вижте
[таблицата](#драйвери-за-български-доставчици)), Apple **Command Line Tools**
(`xcode-select --install` — нужни са за адаптацията на Java), ~450 MB място.

1. **Изтеглете официалния NexU пакет** от портала за е-услуги (страницата за
   вход с КЕП има връзка „Изтегляне на локален компонент NexU") и го
   разархивирайте.

2. **Копирайте трите `.command` файла от това репо** в разархивираната папка
   (там, където е `nexu.jar`).

3. **На Apple Silicon:** ако нямате Rosetta 2, инсталирайте я:
   ```bash
   softwareupdate --install-rosetta --agree-to-license
   ```

4. Стартирайте инсталатора **от Terminal** (изтеглените от интернет скриптове
   са под карантина и двойният клик е блокиран на новите macOS — а „десен
   бутон → Open" вече не предлага байпас за неподписани скриптове):
   ```bash
   cd <папката с nexu.jar>
   bash install-macos.command
   ```
   Скриптът проверява SHA-256 на `nexu.jar` срещу официалния билд от egov.bg,
   изтегля Java 8 + JavaFX (~90 MB, BellSoft Liberica — свободен лиценз),
   адаптира го за macOS, сглобява самостоятелно приложение **NexU.app** и го
   стартира в края.

5. Стартирайте **`bash fix-https-cert-macos.command`** — генерира съвместим
   HTTPS сертификат и го доверява в Keychain (macOS ще поиска паролата ви;
   това е нормално). **Без тази стъпка порталите не виждат NexU.** Скриптът
   сам рестартира NexU, за да зареди новия сертификат.

6. Проверка: отворете <http://localhost:9795/nexu-info> — трябва да върне
   `{ "version": "1.22"}`. Иконата на NexU е в лентата с менюта (горе вдясно).

`NexU.app` е самостоятелно приложение — може да го преместите в `/Applications`.

---

## Chrome: разрешение „Local Network Access" (важно!)

Chrome 138+ изисква **изрично разрешение всеки сайт да достъпва localhost** —
а точно така порталът говори с NexU. Без разрешението порталът показва
„*Необходимо е използването на локален компонент NexU*", **въпреки че NexU
работи**.

Когато портал поиска подпис за пръв път, Chrome показва балонче до адресната
лента: „*… иска да се свърже с устройства в локалната ви мрежа*" → натиснете
**Разрешаване / Allow**. Порталът обаче често се отказва за секунди и показва
грешката, преди да сте отговорили — затова след разрешаването **презаредете
страницата**.

Ако балончето не се появява: иконката вляво от адреса → **Site settings** →
**Local network access** → **Allow** → презаредете. Разрешението се дава за
всеки домейн поотделно (например `qes-login.eauth.egov.bg`, `egov.bg`,
`portal.nra.bg`, `eforms-web.egov.bg`).

---

## Първо подписване: настройка на картата

При първото подписване NexU пита как да се свърже с картата (еднократно):

1. **„Signature Mean Selection"** → изберете **картата** (Smartcard in
   terminal 0, с ATR номер) — не „New keystore" → **Next**.
2. **„Smartcard configuration"** → **Next**.
3. **„API selection"** → **PKCS#11** → **Next**.
4. **„PKCS#11 library"** → **Select** → в диалога натиснете **⌘+Shift+G** и
   поставете пътя до драйвера от [таблицата по-долу](#драйвери-за-български-доставчици)
   (например `/usr/local/lib/libIDPrimePKCS11.dylib`) → **Open** → **Next**.
5. Въведете **PIN-а на картата**.
   > ⚠️ **3 грешни PIN-а блокират картата!** Внимавайте за Caps Lock и
   > клавиатурна подредба. Оставащите опити се виждат в SafeNet Authentication
   > Client Tools / BISS.
6. Изберете сертификата си и потвърдете NexU да **запомни настройките**.

Отсега нататък подписването е само: бутон на портала → PIN → готово.

**Бележка:** ако прозорецът на NexU не се вижда — той понякога се отваря **зад
браузъра** (NexU няма икона в Dock-а). Преместете/минимизирайте прозореца на
браузъра или ползвайте Mission Control.

**Бележка за BISS:** ако B-Trust BISS работи едновременно с NexU, той може да
държи картата „заета". При грешка при PIN/четене — затворете BISS (⌘Q) и
опитайте пак.

---

## Драйвери за български доставчици

NexU говори с картата през PKCS#11 библиотеката на доставчика ѝ. Инсталирайте
драйвера за вашата карта, преди да подписвате:

| Доставчик | Карта | Драйвер | Път до PKCS#11 библиотеката |
|---|---|---|---|
| Б-Тръст (БОРИКА) | IDPrime 940B/840 | SafeNet Authentication Client (Thales) | `/usr/local/lib/libIDPrimePKCS11.dylib` (или `/Library/Frameworks/eToken.framework/Versions/A/libIDPrimePKCS11.dylib`) |
| StampIT | ID Prime 940x | [SafeNet AC 10.9](https://www.stampit.org/en/page/795) | същият като горе |
| StampIT | eIDAS (IDEMIA) | [AWP Identity Manager](https://www.stampit.org/en/page/795) | `/Library/AWP/lib/libOcsCryptoki.dylib` |
| Евротръст | IDPrime 940C | SafeNet AC (иска се от поддръжката им) | същият като Б-Тръст |
| InfoNotary | IDPrime / bit4id | [repository.infonotary.com](https://repository.infonotary.com/ra/install/) | `/Library/bit4id/pkcs11/libbit4xpki.dylib` или IDPrime |
| (стари карти) | Charismathics | няма поддръжка на съвременен macOS | — |

Потвърдени с тази инсталация: **Б-Тръст IDPrime** (универсален драйвер).
Механизмът обхваща и останалите: x86_64 Java под Rosetta зарежда x86_64 слайса
на драйвера, затова и универсалните, и Intel-only библиотеките (като StampIT
eIDAS/AWP) са съвместими — но не всички са тествани на живо. На Apple Silicon
инсталирайте Rosetta 2 преди самия драйвер, ако той е Intel-only.

---

## Стартиране и автостарт

| Начин | Описание |
|---|---|
| `NexU.app` | основният начин — двоен клик, живее в лентата с менюта |
| `NexU-Startup.command` | алтернатива от терминала — лог в `nexu.log.txt` |
| Автостарт | `bash install-macos.command --autostart` или отговор „y" при инсталация |

Автостартът сочи към NexU.app там, където е бил при инсталацията — ако после
преместите приложението (напр. в /Applications), пуснете инсталатора отново с
`--autostart`, за да се обнови пътят.

Спиране: иконата на NexU в лентата с менюта → **Exit** (или `pkill -f nexu.jar`).

Изключване на автостарта:
```bash
launchctl unload -w ~/Library/LaunchAgents/lu.nowina.nexu.plist
rm ~/Library/LaunchAgents/lu.nowina.nexu.plist
```

---

## Отстраняване на проблеми

| Симптом | Причина и решение |
|---|---|
| macOS блокира `.command` файл („from an unidentified developer") | изтеглените от интернет файлове са под карантина → стартирайте през Terminal: `bash install-macos.command`; алтернативи: System Settings → Privacy & Security → **Open Anyway**, или `xattr -d com.apple.quarantine *.command` |
| Порталът: „необходим е компонент NexU" | 1) NexU не върви → проверете <http://localhost:9795/nexu-info>; 2) Chrome няма Local Network Access разрешение за сайта → [вижте по-горе](#chrome-разрешение-local-network-access-важно); 3) сертификатът на 9895 не е доверен → пуснете `fix-https-cert-macos.command` |
| „Услугата за подписване е недостъпна" | NexU е спрян или рестартиран по време на заявката → уверете се, че работи, и презаредете страницата |
| `https://localhost:9895` — грешка за сертификат | пуснете `fix-https-cert-macos.command` (оригиналният сертификат на NexU е с 10-годишна валидност, а Apple допуска ≤825 дни — затова браузърите го отхвърлят дори след доверяване) |
| `UnsatisfiedLinkError: …jna…tmp` при старт | NexU е пуснат с arm64 Java → ползвайте `NexU.app`/`NexU-Startup.command`, които ползват инсталирания x86_64 JRE |
| `UnsatisfiedLinkError: @rpath/JavaNativeFoundation` | JRE-то не е пачнато → пуснете `install-macos.command` отново |
| NexU прозорецът „изчезва" след избор на картата | стара конфигурация с `enable_pop_ups=false` → преинсталирайте с актуалния `install-macos.command` |
| `CKR_PIN_INCORRECT` | грешен PIN — внимание, 3 грешни опита блокират картата |
| Картата не се открива | проверете четеца/драйвера; извадете и поставете отново; затворете BISS; рестартирайте NexU |
| „NexU already started" | стар процес: `pkill -f nexu.jar` и стартирайте пак |
| Прозорецът на NexU не се вижда | отваря се зад браузъра — разместете прозорците |

Логове: `~/Library/Logs/NexU/nexu-console.log` и `~/.NexU/nexu.log`.

**Подновяване на сертификата:** генерираният HTTPS сертификат е валиден ~27
месеца (Apple лимит). Когато изтече, порталите пак ще спрат да „виждат" NexU —
просто пуснете `fix-https-cert-macos.command` отново.

---

## Как работи (технически)

Оригиналният пакет е Windows-only само заради обвивката (Windows JRE + `.bat`
стартери); самият `nexu.jar` е Java и има вградена поддръжка за macOS. Скриптовете:

- **x86_64 Java 8 + JavaFX под Rosetta 2** (BellSoft Liberica JRE 8 „Full").
  NexU 1.22 изисква точно Java 8 с JavaFX (ползва `sun.security.pkcs11.SunPKCS11`
  с InputStream конфигурация и reflection върху вътрешни PC/SC класове на JDK 8;
  на Java 9+ не работи). x86_64 (а не arm64), защото вграденият JNA от 2018 г.
  има macOS библиотека само за i386/x86_64.
- **JavaNativeFoundation пач**: от macOS 11 (Big Sur) системните библиотеки,
  вкл. JNF, съществуват само в dyld shared cache (проверено на macOS 26), а
  8 dylib-а на JRE-то го търсят през `@rpath`. `install_name_tool` ги
  пренасочва към абсолютния системен път, който dyld резолва през кеша.
  Затова са нужни Command Line Tools (`otool`/`install_name_tool`).
- **Без JavaFX preloader**: `NexUPreLoader` показва блокиращ модален диалог при
  всяко предупреждение (на macOS — при всеки старт, заради неуспешния опит за
  инсталиране на сертификат във Firefox) и спира зареждането до натискане на OK.
- **Конфигурационни промени** (зареждат се с приоритет през `-cp`, без промяна
  на jar-а): `enable_pop_ups=true` + `advanced_mode_available=true` (нужни за
  PKCS#11 диалога при нова карта), `enable_database_web_loader=false` +
  `send_anonymous_info_to_proxy=false` (сървърите на Nowina не съществуват от
  години и опитите към тях бавеха старта с ~45 сек).
- **Съвместим HTTPS сертификат**: NexU си генерира localhost сертификат с
  10-годишна валидност, който Apple/браузърите отхвърлят (изискване ≤825 дни).
  `fix-https-cert-macos.command` генерира собствено CA + сертификат със SAN,
  EKU и 820 дни, подменя ги в `~/.NexU/web-server-keystore.jks` (стандартните
  alias/парола на NexU) и доверява CA-то в login keychain.
- **NexU.app**: самостоятелен бандъл (собствен JRE + jar), `LSUIElement` (без
  икона в Dock), `LSAppNapIsDisabled` (App Nap би „приспивал" локалния сървър),
  `-Dsun.security.smartcardio.library=…PCSC` (откриване на PC/SC на Big Sur+).
- Портове: **9795** (HTTP) и **9895** (HTTPS) на 127.0.0.1 — както на Windows.
  Настройки и логове: `~/.NexU/`.

История на оригиналния проект: NexU е разработен от Nowina Solutions (EUPL,
изоставен — оригиналното репо не съществува). Поддържан наследник е
[EsupPortail/esup-dss-client](https://github.com/EsupPortail/esup-dss-client),
но българските портали работят с протокола на NexU 1.22, затова тук адаптираме
официалния билд.

## Деинсталация

```bash
launchctl unload -w ~/Library/LaunchAgents/lu.nowina.nexu.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/lu.nowina.nexu.plist
pkill -f nexu.jar
rm -rf NexU.app java-macos macos-config        # от папката на пакета
rm -rf ~/Library/Logs/NexU
rm -f ~/.NexU/nexu.log ~/.NexU/store.xml ~/.NexU/web-server-keystore.jks* \
      ~/.NexU/keystore.jks ~/.NexU/NexU-*.crt ~/.NexU/NexU-localCA.der
# сертификатите от Keychain: Keychain Access → търсете "NexU" → изтрийте
```

## Лицензи

- Скриптовете в това репо: **MIT** (вижте [LICENSE](LICENSE)).
- **NexU** е © Nowina Solutions, лиценз **EUPL v1.1** — не се разпространява с
  това репо; изтегляте го от официалния портал.
- **BellSoft Liberica JRE** (изтегля се при инсталация): GPLv2 + Classpath
  Exception.
