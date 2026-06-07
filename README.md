# LightningMcQueen VPN - клиент

Кроссплатформ впн-клиент на флаттере. Винда и ведроид (есть задел под ios/macos).
Движок один - sing-box (наш форк amnezia-box) на все прото: vless (tcp/ws/grpc/xhttp/
reality), tuic, hysteria2, amneziawg 2.0, плюс каскад через cloudflare warp.

Код приватный. Готовые сборки - в паблик-репах релизов (см. ниже), оттуда же клиент
тянет авто-апдейты.

## Стек

- **flutter / dart** - весь ui и логика, общие на обе платформы (~90% кода).
- **provider** (ChangeNotifier) - состояние (`VpnProvider`).
- **ведроид:** kotlin-слой (`VpnService` + libbox), gradle (kotlin dsl).
- **винда:** flutter desktop (c++ runner) + готовые движки-процессы.

## Движки

- **ведроид:** `android/app/libs/libbox.aar` - своя сборка форка **amnezia-box**
  (форк sing-box, v1.13.8-awg2.0) через **gomobile** + go + ndk 27 + jdk 17. Один
  движок в одном процессе на все прото.
- **винда:** бинари в `assets/bin/` - `sing-box.exe`, `xray.exe`, `amneziawg.exe`,
  `awg.exe`, `wintun.dll`. Гоняются как процессы, рулёжка через clash api (`:9090`).

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
Пересборка libbox (только если менялся движок): go + gomobile (форк sagernet), ndk 27 -
`go run ./cmd/internal/build_libbox -target android` в дереве форка, результат
`libbox.aar` кинуть в `android/app/libs/`.

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
