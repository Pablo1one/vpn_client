// готовый пресет: российские приложения, которым лучше ходить мимо VPN (банки -
// антифрод по гео, госуслуги/мед, маркетплейсы/доставка, транспорт, яндекс/vk/max
// и их экосистемы). package-имена сверены по google play / rustore.
// на android уходят в exclude_package (вне туннеля), на windows процессов нет -
// пресет имеет смысл в основном на android. список расширяемый.
const ruAppsPreset = <String>[
  // банки
  'ru.sberbankmobile', // сбер
  'ru.gazprombank.android.mobilebank.app', // газпромбанк
  'com.idamob.tinkoff.android', // т-банк (тинькофф)
  'ru.alfabank.mobile.android', // альфа-банк
  'ru.vtb24.mobilebanking.android', // втб онлайн
  'ru.raiffeisennews', // райффайзен
  'ru.mts.money', // мтс банк
  'com.openbank', // открытие (бм-банк)
  'ru.letobank.Prometheus', // почта банк
  'ru.sovcomcard.halva.v1', // совкомбанк (халва)
  'logo.com.mbanking', // псб (промсвязьбанк)
  'ru.yoo.money', // юmoney
  'ru.nspk.mirpay', // mir pay
  // маркетплейсы
  'com.wildberries.ru', // wildberries
  'ru.ozon.app.android', // ozon
  'com.avito.android', // авито
  'ru.megamarket.marketplace', // мегамаркет
  'ru.beru.android', // яндекс маркет
  // доставка еды/продуктов
  'ru.foodfox.client', // яндекс еда
  'ru.sbcs.store', // самокат
  'ru.instamart', // купер (ex-сбермаркет)
  'com.deliveryclub', // деливери (delivery club)
  // транспорт / карты
  'ru.rzd.pass', // ржд пассажирам
  'ru.aeroflot', // аэрофлот
  'ru.dublgis.dgismobile', // 2гис
  'ru.yandex.yandexnavi', // яндекс навигатор
  // яндекс (остальное)
  'ru.yandex.taxi', // яндекс go (такси/доставка)
  'ru.yandex.yandexmaps', // яндекс карты
  'ru.yandex.searchplugin', // яндекс (поиск/алиса)
  'com.yandex.browser', // яндекс браузер
  'ru.yandex.music', // яндекс музыка
  'ru.kinopoisk', // кинопоиск
  'ru.yandex.mail', // яндекс почта
  'ru.yandex.disk', // яндекс диск
  'ru.tankerapp.android', // яндекс заправки
  'ru.zen.android', // дзен
  'ru.yandex.weatherplugin', // яндекс погода
  'ru.yandex.translate', // яндекс переводчик
  // vk / mail.ru / мессенджеры
  'com.vkontakte.android', // вконтакте
  'com.vk.im', // vk messenger
  'ru.oneme.app', // max
  'ru.ok.android', // одноклассники
  'ru.mail.mailapp', // mail.ru (почта/облако)
  'com.uma.musicvk', // vk музыка (boom)
  'com.allgoritm.youla', // юла
  'ru.mail.search.electroscope', // маруся
  'ru.vk.store', // rustore
  // госуслуги / мед / госприложения
  'ru.rostel', // госуслуги
  'ru.gosuslugi.auto', // госуслуги авто (штрафы)
  'ru.sigma.gisgkh', // госуслуги дом
  'ru.gosuslugi.goskey', // госключ
  'ru.gosuslugi.pos', // госуслуги решаем вместе
  'ru.rtlabs.mobile.ebs.gosuslugi.android', // госуслуги биометрия
  'ru.gosuslugi.culture', // госуслуги культура (пушкинская карта)
  'com.gnivts.selfemployed', // мой налог (самозанятые)
  'com.programmisty.emiasapp', // емиас (мед)
  'com.docdoc.docdoc', // сберздоровье
];
