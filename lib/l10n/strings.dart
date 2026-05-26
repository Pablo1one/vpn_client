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
  final String updates;
  final String version;
  final String checkForUpdates;
  final String checkingForUpdates;
  final String upToDate;
  final String updateAvailable;
  final String download;
  final String logs;
  final String logsTitle;
  final String clearLogs;
  final String copyLogs;
  final String logsCopied;
  final String noLogs;
  final String refreshSubscription;
  final String standaloneKeys;
  final String subscriptionLabel;
  final String themeSection;
  final String themeJackson;
  final String themeMcQueen;

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
    required this.updates,
    required this.version,
    required this.checkForUpdates,
    required this.checkingForUpdates,
    required this.upToDate,
    required this.updateAvailable,
    required this.download,
    required this.logs,
    required this.logsTitle,
    required this.clearLogs,
    required this.copyLogs,
    required this.logsCopied,
    required this.noLogs,
    required this.refreshSubscription,
    required this.standaloneKeys,
    required this.subscriptionLabel,
    required this.themeSection,
    required this.themeJackson,
    required this.themeMcQueen,
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
    pasteBtn: 'Paste',
    fetchingUrl: 'Fetching…',
    foundProfiles: 'Found {n} profiles',
    importAll: 'Import all',
    noProfiles: 'No keys yet',
    deleteProfile: 'Delete?',
    cancel: 'Cancel',
    delete: 'Delete',
    unrecognizedFormat:
        'Unrecognized format.\nSupported: vless://, tuic://, hysteria2://, vpn:// (Amnezia), WireGuard .conf, subscription URL',
    searchApps: 'Search apps…',
    openFile: 'Open .conf file',
    updates: 'Updates',
    version: 'Version',
    checkForUpdates: 'Check for updates',
    checkingForUpdates: 'Checking…',
    upToDate: 'Up to date',
    updateAvailable: 'Update available',
    download: 'Download',
    logs: 'Logs',
    logsTitle: 'Logs',
    clearLogs: 'Clear',
    copyLogs: 'Copy',
    logsCopied: 'Copied',
    noLogs: 'No logs yet',
    refreshSubscription: 'Refresh',
    standaloneKeys: 'Standalone keys',
    subscriptionLabel: 'Subscription',
    themeSection: 'Theme',
    themeJackson: 'Jackson Storm',
    themeMcQueen: 'Lightning McQueen',
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
    pasteBtn: 'Вставить',
    fetchingUrl: 'Загрузка…',
    foundProfiles: 'Найдено ключей: {n}',
    importAll: 'Добавить все',
    noProfiles: 'Ключей пока нет',
    deleteProfile: 'Удалить?',
    cancel: 'Отмена',
    delete: 'Удалить',
    unrecognizedFormat:
        'Неизвестный формат.\nПоддерживается: vless://, tuic://, hysteria2://, vpn:// (Amnezia), WireGuard .conf, URL подписки',
    searchApps: 'Поиск приложений…',
    openFile: 'Открыть .conf файл',
    updates: 'Обновления',
    version: 'Версия',
    checkForUpdates: 'Проверить обновления',
    checkingForUpdates: 'Проверка…',
    upToDate: 'Установлена последняя версия',
    updateAvailable: 'Доступно обновление',
    download: 'Скачать',
    logs: 'Логи',
    logsTitle: 'Логи',
    clearLogs: 'Очистить',
    copyLogs: 'Скопировать',
    logsCopied: 'Скопировано',
    noLogs: 'Логов пока нет',
    refreshSubscription: 'Обновить',
    standaloneKeys: 'Отдельные ключи',
    subscriptionLabel: 'Подписка',
    themeSection: 'Тема',
    themeJackson: 'Jackson Storm',
    themeMcQueen: 'Lightning McQueen',
  );
}
