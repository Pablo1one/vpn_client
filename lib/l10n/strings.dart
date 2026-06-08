import 'package:flutter/widgets.dart';
import '../providers/language_provider.dart';
import 'package:provider/provider.dart';

class L10n {
  final String appName;
  final String vpnTab;
  final String profilesTab;
  final String settingsTab;
  final String connected;
  final String connecting;
  final String disconnected;
  final String disconnecting;
  final String error;
  final String noProfile;
  final String connection;
  final String killSwitch;
  final String killSwitchDesc;
  final String advanced;
  final String muxTitle;
  final String muxDesc;
  final String fragmentTitle;
  final String fragmentDesc;
  final String warpTitle;
  final String warpDesc;
  final String dnsTitle;
  final String dnsHint;
  final String allowInsecureTitle;
  final String allowInsecureDesc;
  final String tfoTitle;
  final String tfoDesc;
  final String warpCascadeTitle;
  final String warpCascadeDesc;
  final String adblockTitle;
  final String adblockDesc;
  final String subRefreshTitle;
  final String subRefreshDesc;
  final String subRefreshOff;
  final String autostartTitle;
  final String autostartDesc;
  final String splitTunnelTitle;
  final String splitTunnelDesc;
  final String splitTunnelHint;
  final String splitTunnelChip;
  final String coresTitle;
  final String routing;
  final String routingFull;
  final String routingRussia;
  final String routingCustom;
  final String bypassDomains;
  final String bypassDomainsHint;
  final String bypassDomainsDesc;
  final String perApp;
  final String perAppDesc;
  final String excludedApps;
  final String noExcludedApps;
  final String language;
  final String importProfile;
  final String importHint;
  final String saveProfile;
  final String keyAlreadyExists;
  final String duplicatesSkipped;
  final String pasteBtn;
  final String fetchingUrl;
  final String _foundProfiles;
  final String importAll;
  final String noProfiles;
  final String deleteProfile;
  final String cancel;
  final String delete;
  final String unrecognizedFormat;
  final String searchApps;
  final String openFile;
  final String scanQr;
  final String updates;
  final String version;
  final String checkForUpdates;
  final String checkingForUpdates;
  final String upToDate;
  final String updateAvailable;
  final String updateCheckFailed;
  final String download;
  final String install;
  final String connCheck;
  final String logs;
  final String logsTitle;
  final String clearLogs;
  final String copyLogs;
  final String logsCopied;
  final String noLogs;
  final String refreshSubscription;
  final String deleteSubscription;
  final String standaloneKeys;
  final String subscriptionLabel;
  final String themeSection;
  final String themeJackson;
  final String themeMcQueen;
  final String cdnTab;
  final String cdnTitle;
  final String cdnDesc;
  final String cdnConnect;
  final String cdnDisconnect;
  final String cdnReset;
  final String cdnRegistering;
  final String cdnManual;
  final String cdnManualDesc;
  final String cdnSaveConfig;

  const L10n._({
    required this.appName,
    required this.vpnTab,
    required this.profilesTab,
    required this.settingsTab,
    required this.connected,
    required this.connecting,
    required this.disconnected,
    required this.disconnecting,
    required this.error,
    required this.noProfile,
    required this.connection,
    required this.killSwitch,
    required this.killSwitchDesc,
    required this.advanced,
    required this.muxTitle,
    required this.muxDesc,
    required this.fragmentTitle,
    required this.fragmentDesc,
    required this.warpTitle,
    required this.warpDesc,
    required this.dnsTitle,
    required this.dnsHint,
    required this.allowInsecureTitle,
    required this.allowInsecureDesc,
    required this.tfoTitle,
    required this.tfoDesc,
    required this.warpCascadeTitle,
    required this.warpCascadeDesc,
    required this.adblockTitle,
    required this.adblockDesc,
    required this.subRefreshTitle,
    required this.subRefreshDesc,
    required this.subRefreshOff,
    required this.autostartTitle,
    required this.autostartDesc,
    required this.splitTunnelTitle,
    required this.splitTunnelDesc,
    required this.splitTunnelHint,
    required this.splitTunnelChip,
    required this.coresTitle,
    required this.routing,
    required this.routingFull,
    required this.routingRussia,
    required this.routingCustom,
    required this.bypassDomains,
    required this.bypassDomainsHint,
    required this.bypassDomainsDesc,
    required this.perApp,
    required this.perAppDesc,
    required this.excludedApps,
    required this.noExcludedApps,
    required this.language,
    required this.importProfile,
    required this.importHint,
    required this.saveProfile,
    required this.keyAlreadyExists,
    required this.duplicatesSkipped,
    required this.pasteBtn,
    required this.fetchingUrl,
    required String foundProfiles,
    required this.importAll,
    required this.noProfiles,
    required this.deleteProfile,
    required this.cancel,
    required this.delete,
    required this.unrecognizedFormat,
    required this.searchApps,
    required this.openFile,
    required this.scanQr,
    required this.updates,
    required this.version,
    required this.checkForUpdates,
    required this.checkingForUpdates,
    required this.upToDate,
    required this.updateAvailable,
    required this.updateCheckFailed,
    required this.download,
    required this.install,
    required this.connCheck,
    required this.logs,
    required this.logsTitle,
    required this.clearLogs,
    required this.copyLogs,
    required this.logsCopied,
    required this.noLogs,
    required this.refreshSubscription,
    required this.deleteSubscription,
    required this.standaloneKeys,
    required this.subscriptionLabel,
    required this.themeSection,
    required this.themeJackson,
    required this.themeMcQueen,
    required this.cdnTab,
    required this.cdnTitle,
    required this.cdnDesc,
    required this.cdnConnect,
    required this.cdnDisconnect,
    required this.cdnReset,
    required this.cdnRegistering,
    required this.cdnManual,
    required this.cdnManualDesc,
    required this.cdnSaveConfig,
  }) : _foundProfiles = foundProfiles;

  String foundProfiles(int n) => _foundProfiles.replaceAll('{n}', '$n');

  static L10n of(BuildContext context) {
    final code = context.read<LanguageProvider>().locale.languageCode;
    return code == 'ru' ? ru : en;
  }

  static const en = L10n._(
    appName: 'McQueen Speed Booster',
    vpnTab: 'VPN',
    profilesTab: 'Keys',
    settingsTab: 'Settings',
    connected: 'Connected',
    connecting: 'Connecting…',
    disconnected: 'Disconnected',
    disconnecting: 'Disconnecting…',
    error: 'Error',
    noProfile: 'No profile selected',
    connection: 'Connection',
    killSwitch: 'Kill Switch',
    killSwitchDesc: 'Block all traffic if VPN drops',
    advanced: 'Advanced',
    muxTitle: 'Multiplexing (MUX)',
    muxDesc: 'Reuse one connection. Requires server support',
    fragmentTitle: 'TLS fragmentation',
    fragmentDesc: 'Split TLS handshake to bypass DPI',
    warpTitle: 'Cloudflare WARP',
    warpDesc: 'Connect via WARP (CDN tab)',
    dnsTitle: 'Custom DNS',
    dnsHint: 'e.g. 1.1.1.1 (default 8.8.8.8)',
    allowInsecureTitle: 'Allow insecure',
    allowInsecureDesc: 'Accept untrusted TLS certificates',
    tfoTitle: 'TCP Fast Open',
    tfoDesc: 'Speeds up connection setup. Not all servers support it',
    warpCascadeTitle: 'Exit via Cloudflare WARP',
    warpCascadeDesc: 'Route exit through Cloudflare on top of the server (changes exit geo)',
    adblockTitle: 'Block ads',
    adblockDesc: 'Reject known ad and tracker domains',
    subRefreshTitle: 'Auto-update subscriptions',
    subRefreshDesc: 'How often to refresh subscription keys',
    subRefreshOff: 'Off',
    autostartTitle: 'Launch at Windows startup',
    autostartDesc: 'Start with Windows and auto-connect the last profile',
    splitTunnelTitle: 'Split tunnel (apps bypass VPN)',
    splitTunnelDesc: 'These apps go direct, outside the VPN',
    splitTunnelHint: 'One process per line, e.g.\nDiscord.exe\nchrome.exe',
    splitTunnelChip: 'Apps bypass VPN',
    coresTitle: 'Cores & versions',
    routing: 'Routing',
    routingFull: 'Full VPN',
    routingRussia: 'Russia bypass',
    routingCustom: 'Custom domains',
    bypassDomains: 'Bypass domains',
    bypassDomainsHint: 'one domain per line',
    bypassDomainsDesc: 'These domains route outside VPN',
    perApp: 'Per-app routing',
    perAppDesc: 'Selected apps bypass the VPN',
    excludedApps: 'Excluded apps',
    noExcludedApps: 'None — all apps through VPN',
    language: 'Language',
    importProfile: 'Add',
    importHint: 'Paste a link or subscription URL…',
    saveProfile: 'Save',
    keyAlreadyExists: 'Key already added',
    duplicatesSkipped: 'Duplicates skipped',
    pasteBtn: 'Paste',
    fetchingUrl: 'Fetching…',
    foundProfiles: 'Found {n} profiles',
    importAll: 'Import all',
    noProfiles: 'No keys yet',
    deleteProfile: 'Delete?',
    cancel: 'Cancel',
    delete: 'Delete',
    unrecognizedFormat:
        'Unrecognized format.\nSupported: vless://, tuic://, hysteria2://, vpn:// (Amnezia), WireGuard .conf, subscription url',
    searchApps: 'Search apps…',
    openFile: 'Open .conf file',
    scanQr: 'Scan QR',
    updates: 'Updates',
    version: 'Version',
    checkForUpdates: 'Check for updates',
    checkingForUpdates: 'Checking…',
    upToDate: 'Up to date',
    updateAvailable: 'Update available',
    updateCheckFailed: 'Check failed',
    download: 'Download',
    install: 'Install',
    connCheck: 'Check connection',
    logs: 'Logs',
    logsTitle: 'Logs',
    clearLogs: 'Clear',
    copyLogs: 'Copy',
    logsCopied: 'Copied',
    noLogs: 'No logs yet',
    refreshSubscription: 'Refresh',
    deleteSubscription: 'Delete subscription',
    standaloneKeys: 'Standalone keys',
    subscriptionLabel: 'Subscription',
    themeSection: 'Theme',
    themeJackson: 'Jackson Storm',
    themeMcQueen: 'Lightning McQueen',
    cdnTab: 'CDN',
    cdnTitle: 'Cloudflare WARP',
    cdnDesc: 'Free VPN by Cloudflare. No keys needed — connects automatically.',
    cdnConnect: 'Connect',
    cdnDisconnect: 'Disconnect',
    cdnReset: 'Reset account',
    cdnRegistering: 'Registering…',
    cdnManual: 'Paste config manually',
    cdnManualDesc: 'If auto-registration fails, generate a config via wgcf or similar and paste it here.',
    cdnSaveConfig: 'Save config',
  );

  static const ru = L10n._(
    appName: 'McQueen Ускоритель интернета',
    vpnTab: 'VPN',
    profilesTab: 'Ключи',
    settingsTab: 'Настройки',
    connected: 'Подключено',
    connecting: 'Подключение…',
    disconnected: 'Отключено',
    disconnecting: 'Отключение…',
    error: 'Ошибка',
    noProfile: 'Профиль не выбран',
    connection: 'Подключение',
    advanced: 'Дополнительно',
    muxTitle: 'Мультиплексирование (MUX)',
    muxDesc: 'Переиспользование соединения. Требует поддержки на сервере',
    fragmentTitle: 'TLS-фрагментация',
    fragmentDesc: 'Дробит TLS-хендшейк для обхода DPI',
    warpTitle: 'Cloudflare WARP',
    warpDesc: 'Подключиться через WARP (вкладка CDN)',
    dnsTitle: 'Свой DNS',
    dnsHint: 'напр. 1.1.1.1 (по умолчанию 8.8.8.8)',
    allowInsecureTitle: 'Разрешить недоверенные',
    allowInsecureDesc: 'Принимать недоверенные TLS-сертификаты',
    tfoTitle: 'TCP Fast Open',
    tfoDesc: 'Ускоряет установку соединения. Поддерживают не все серверы',
    warpCascadeTitle: 'Выход через Cloudflare WARP',
    warpCascadeDesc: 'Финальный выход через Cloudflare поверх сервера (меняет гео выхода)',
    adblockTitle: 'Блокировать рекламу',
    adblockDesc: 'Резать известные рекламные и трекерные домены',
    subRefreshTitle: 'Авто-обновление подписок',
    subRefreshDesc: 'Как часто обновлять ключи подписок',
    subRefreshOff: 'Выкл',
    autostartTitle: 'Запуск с Windows',
    autostartDesc: 'Запускать со стартом Windows и автоподключать последний профиль',
    splitTunnelTitle: 'Split-tunnel (приложения мимо VPN)',
    splitTunnelDesc: 'Указанные приложения идут напрямую, минуя VPN',
    splitTunnelHint: 'По одному процессу в строке, напр.\nDiscord.exe\nchrome.exe',
    splitTunnelChip: 'Приложения мимо VPN',
    coresTitle: 'Ядра и версии',
    killSwitch: 'Kill Switch',
    killSwitchDesc: 'Блокировать трафик при разрыве VPN',
    routing: 'Маршрутизация',
    routingFull: 'Весь трафик через VPN',
    routingRussia: 'Россия напрямую',
    routingCustom: 'Свои домены',
    bypassDomains: 'Домены напрямую',
    bypassDomainsHint: 'по одному домену на строку',
    bypassDomainsDesc: 'Эти домены не идут через VPN',
    perApp: 'По приложениям',
    perAppDesc: 'Выбранные приложения идут напрямую',
    excludedApps: 'Исключённые приложения',
    noExcludedApps: 'Нет — все приложения через VPN',
    language: 'Язык',
    importProfile: 'Добавить',
    importHint: 'Вставьте ссылку или URL подписки…',
    saveProfile: 'Сохранить',
    keyAlreadyExists: 'Ключ уже добавлен',
    duplicatesSkipped: 'Дубликаты пропущены',
    pasteBtn: 'Вставить',
    fetchingUrl: 'Загрузка…',
    foundProfiles: 'Найдено ключей: {n}',
    importAll: 'Добавить все',
    noProfiles: 'Ключей пока нет',
    deleteProfile: 'Удалить?',
    cancel: 'Отмена',
    delete: 'Удалить',
    unrecognizedFormat:
        'Неизвестный формат.\nПоддерживается: vless://, tuic://, hysteria2://, vpn:// (Amnezia), WireGuard .conf, url подписки',
    searchApps: 'Поиск приложений…',
    openFile: 'Открыть .conf файл',
    scanQr: 'Сканировать QR',
    updates: 'Обновления',
    version: 'Версия',
    checkForUpdates: 'Проверить обновления',
    checkingForUpdates: 'Проверка…',
    upToDate: 'Установлена последняя версия',
    updateAvailable: 'Доступно обновление',
    updateCheckFailed: 'Не удалось проверить',
    download: 'Скачать',
    install: 'Установить',
    connCheck: 'Проверить соединение',
    logs: 'Логи',
    logsTitle: 'Логи',
    clearLogs: 'Очистить',
    copyLogs: 'Скопировать',
    logsCopied: 'Скопировано',
    noLogs: 'Логов пока нет',
    refreshSubscription: 'Обновить',
    deleteSubscription: 'Удалить подписку',
    standaloneKeys: 'Отдельные ключи',
    subscriptionLabel: 'Подписка',
    themeSection: 'Тема',
    themeJackson: 'Jackson Storm',
    themeMcQueen: 'Lightning McQueen',
    cdnTab: 'CDN',
    cdnTitle: 'Cloudflare WARP',
    cdnDesc: 'Бесплатный VPN от Cloudflare. Ключи не нужны — подключается автоматически.',
    cdnConnect: 'Подключить',
    cdnDisconnect: 'Отключить',
    cdnReset: 'Сбросить аккаунт',
    cdnRegistering: 'Регистрация…',
    cdnManual: 'Вставить конфиг вручную',
    cdnManualDesc: 'Если авторегистрация недоступна — сгенерируйте конфиг через wgcf или аналог и вставьте сюда.',
    cdnSaveConfig: 'Сохранить конфиг',
  );
}
