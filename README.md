# LightningMcQueen VPN - клиент

Кроссплатформ впн-клиент на флаттере. Винда и ведроид (есть задел под ios/macos).
Движок один - sing-box (наш форк amnezia-box) на все прото: vless (tcp/ws/grpc/xhttp/
reality), tuic, hysteria2, amneziawg 2.0, плюс каскад через cloudflare warp.

Код приватный. Готовые сборки - в паблик-репах релизов (см. ниже), оттуда же клиент
тянет авто-апдейты.

## Фичи

- прото: vless (tcp/ws/grpc/xhttp/reality), tuic, hysteria2, amneziawg 2.0
- каскад через cloudflare warp (кроме grpc/awg)
- маршрутизаця: весь трафик / россия напрямую / custom (домены-исключения)
- per-app split-tunnel (приложения мимо vpn)
- блокировка рекламы (geosite-ads), tls-фрагментация (анти-dpi)
- импорт ключа: вставка / файл .conf / qr-скан (мобильные)
- виджет в шторке (ведроид): скорость, флаг, кнопка отключения
- попап об обновлении при старте + авто-проверка релизов
- шифрование профилей (keystore / dpapi)

## Стек

- **flutter / dart** - весь ui и логика, общие на обе платформы (~90% кода).
- **provider** (ChangeNotifier) - состояние (`VpnProvider`).
- **ведроид:** kotlin-слой (`VpnService` + libbox), gradle (kotlin dsl).
- **винда:** flutter desktop (c++ runner) + готовые движки-процессы.

## Движки

Оба порта теперь на одном движке - наш форк **amnezia-box** (форк sing-box,
v1.13.8-awg2.0), один процесс на все прото (включая awg как endpoint).

- **ведроид:** `android/app/libs/libbox.aar` - сборка форка через **gomobile** + go +
  ndk 27 + jdk 17. Один движок в одном процессе.
- **винда:** `assets/bin/singbox-uni.exe` - тот же форк, собранный под windows/amd64
  (`go build -tags "with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_awg"`,
  без `badlinkname` - иначе линк badtls падает на go 1.26). Плюс `wintun.dll` для tun.
  Рулёжка через clash api (`:9090`), конфиг общий с ведроидом (`ConfigBuilder.build`).

**Раньше на винде было 3 движка** (`xray.exe` для vless, стоковый `sing-box.exe` для
tuic/h2/tun, `amneziawg.exe` для awg) - выпилены ради единого движка и веса. Последний
стабильный релиз на 3 движках - **v1.0.16** (точка отката, если на едином что-то всплывёт).

## Архитектура

Слоёная + mvvm (через provider):

```
lib/screens/    ui (флаттер-виджеты)
lib/providers/  состояние (VpnProvider = вьюмодель)
lib/services/   VpnService (абстракция платформы), SpeedService,
                ProfileRepository, WarpService, UpdateService
lib/utils/      ConfigBuilder (генерит конфиг движка), LinkParser
lib/models/     VpnProfile
android/.../kotlin/  нативный VpnService + мост libbox
```

`abstract class VpnService` + фабрика - `_WindowsVpnService` / `_MobileVpnService`:
ui не знает, как именно поднимается туннель на конкретной платформе.

## Сборка

Общее: flutter sdk (dart >= 3.0), `flutter pub get`.

### Ведроид
Надо: android sdk + ndk 27, jdk 17. Для подписи - `android/key.properties` и keystore
(**в гит не коммитятся**, лежат локально / в бэкапе).
```
flutter build apk --release
```
apk собирается только под arm (arm64-v8a + armeabi-v7a) - `abiFilters` в
`android/app/build.gradle.kts`. x86/x86_64 эмуляторные не кладём (это ~85 мб). путь
ndk/jdk должны быть в PATH (`gobind`, `javac`), иначе сборка libbox падает.

Пересборка libbox (только если менялся движок): go + gomobile (форк sagernet), ndk 27,
jdk 17 - `go run ./cmd/internal/build_libbox -target android` в дереве форка, результат
`libbox.aar` кинуть в `android/app/libs/`. ВАЖНО: в `cmd/internal/build_libbox/main.go`
**убран `with_tailscale`** (мы его не юзаем, он раздувал libbox.so на ~13 мб/abi). aar
74.7 -> 59.8 мб, итоговый apk 262 -> ~123 мб.

### Винда
Надо: visual studio build tools 2022 с компонентами **Desktop C++** и **C++ ATL**
(последний нужен `flutter_secure_storage`), inno setup.
```
flutter build windows --release
"D:\InnoSetup\ISCC.exe" installer.iss   # -> installer_output/LightningMcQueen-Setup.exe
```

## Релизы и авто-апдейт

- Код приватный (этот реп).
- Сборки льются в паблик-репы релизов:
  - винда: `Pablo1one/vpn_client_releases` (asset `*.exe`)
  - ведроид: `Pablo1one/vpn_client_releases_android` (asset `*.apk`)
- `UpdateService` сверяет версию из `pubspec.yaml` с последним релизом нужного репа
  и предлагает обновку.

## Безопасность

- Профили (uuid/ключи/пароли) шифруются в хранилеще ос (android keystore / windows
  dpapi) через `flutter_secure_storage`.
- Release-сборка ведроида - обфускация r8, запрет бэкапа.
- Секреты (keystore, `key.properties`) - в `.gitignore`, в реп не попадают.

## Используемые репозитории

Движок и протоколы:
- sing-box (база движка) - https://github.com/SagerNet/sing-box
- amnezia-box / awg-форк sing-box - https://github.com/amnezia-vpn
- amneziawg-go / amneziawg-windows (awg2.0) - https://github.com/amnezia-vpn/amneziawg-go
- xray-core (старый vless-движок до v1.0.16) - https://github.com/XTLS/Xray-core
- reality / xtls - https://github.com/XTLS/REALITY
- wintun (tun-драйвер на винде) - https://www.wintun.net

Сервер:
- hiddify-manager (панель + инбаунды) - https://github.com/hiddify/hiddify-manager
- telemt (mtproto-прокси для telegram) - на сервере, `other/telegram/telemt`

Наши паблик-репы релизов (откуда тянутся апдейты):
- винда - https://github.com/Pablo1one/vpn_client_releases
- ведроид - https://github.com/Pablo1one/vpn_client_releases_android
