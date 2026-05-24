# Сборка VPN Client

## Требования

| Инструмент | Версия |
|---|---|
| Flutter SDK | ≥ 3.19 |
| Dart | ≥ 3.0 |
| Android Studio | Hedgehog + |
| Xcode | 15+ (только macOS, для iOS) |
| Visual Studio | 2022 с Desktop C++ (для Windows) |

---

## Windows

### 1. Скачать sing-box.exe
```powershell
powershell -ExecutionPolicy Bypass -File scripts\download_singbox.ps1
```
Или скачать вручную с [GitHub Releases](https://github.com/SagerNet/sing-box/releases):
файл `sing-box_*_windows_amd64.zip` → распаковать `sing-box.exe` → положить в `assets/bin/sing-box.exe`.

### 2. Установить WinTun
Скачать инсталлятор с https://www.wintun.net/ и установить.

### 3. Сгенерировать платформенный scaffold
```powershell
flutter create . --org com.example --platforms windows
```

### 4. Собрать
```powershell
flutter build windows --release
```

### 5. Запустить (нужны права администратора для TUN)
```powershell
# Запустить от администратора:
build\windows\x64\runner\Release\vpn_client.exe
```

---

## Android

### 1. Скачать libbox.aar
```bash
bash scripts/download_libs.sh
# Или вручную:
# https://github.com/SagerNet/sing-box/releases → libbox-*-android-arm64.aar
# → android/app/libs/libbox.aar
```

### 2. Включить libbox в SingBoxVpnService.kt
Раскомментировать импорты и блок `startTunnel()` с `Libbox.newService(...)`.

### 3. Сгенерировать платформенный scaffold
```bash
flutter create . --org com.example --platforms android
```

### 4. Обновить android/app/src/main/AndroidManifest.xml
Убедиться, что наш файл не был перезаписан (проверить наличие `SingBoxVpnService`).

### 5. Собрать
```bash
flutter build apk --release
# или для Play Store:
flutter build appbundle --release
```

---

## iOS

### 1. Скачать LibBox.xcframework
```bash
bash scripts/download_libs.sh
```

### 2. Сгенерировать scaffold и открыть в Xcode
```bash
flutter create . --org com.example --platforms ios
open ios/Runner.xcworkspace
```

### 3. Добавить PacketTunnel Extension target
В Xcode: **File → New → Target → Network Extension → Packet Tunnel Provider**
- Product Name: `PacketTunnel`
- Bundle Identifier: `com.example.vpn-client.tunnel`
- Language: Swift

### 4. Настроить Extension target
1. Удалить сгенерированный `PacketTunnelProvider.swift`, скопировать наш `ios/PacketTunnel/PacketTunnelProvider.swift`
2. В Build Settings → Bundle Identifier: `com.example.vpn-client.tunnel`
3. Signing & Capabilities → добавить **Network Extensions** (packet-tunnel-provider)
4. Signing & Capabilities → добавить **App Groups** → `group.com.example.vpn-client`
5. Добавить то же App Group и Network Extensions в Runner target
6. Перетащить `LibBox.xcframework` в проект → добавить в оба target (Runner + PacketTunnel)

### 5. Включить libbox в PacketTunnelProvider.swift
Раскомментировать `import LibBox` и блок `LibboxNewBoxService(...)`.

### 6. Собрать
```bash
flutter build ios --release
```

---

## Структура нативного кода

```
android/app/src/main/kotlin/com/example/vpn_client/
  MainActivity.kt          — регистрация плагина
  VpnPlugin.kt             — MethodChannel + EventChannel
  SingBoxVpnService.kt     — Android VpnService (TUN + libbox)

ios/Runner/
  AppDelegate.swift        — регистрация плагина
  VpnPlugin.swift          — MethodChannel + NEVPNStatusDidChange → EventChannel

ios/PacketTunnel/
  PacketTunnelProvider.swift — NEPacketTunnelProvider (LibBox)
  Info.plist               — bundle ID = com.example.vpn-client.tunnel

lib/services/vpn_service.dart
  _MobileVpnService        — Android + iOS через MethodChannel
  _WindowsVpnService       — Windows через subprocess sing-box.exe
```

## MethodChannel protocol

```
Channel:  com.example.vpn_client/vpn
Methods:
  connect  { config: String }  → void (throws on error)
  disconnect                   → void

EventChannel: com.example.vpn_client/vpn_events
  Events (String): connected | connecting | disconnecting | disconnected | error: <msg>
```
