#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "erb"
require "fileutils"
require "json"
require "optparse"
require "pathname"

module PortfolioMarketingSite
  FORM_ENDPOINT = "https://formspree.io/f/mykqbyyw"

  LANGUAGE_LABELS = {
    "de" => "Deutsch", "en" => "English", "es" => "Español", "fr" => "Français",
    "it" => "Italiano", "ja" => "日本語", "ko" => "한국어", "nl" => "Nederlands",
    "pl" => "Polski", "pt" => "Português", "ru" => "Русский", "sv" => "Svenska",
    "tr" => "Türkçe", "uk" => "Українська", "zh-Hans" => "简体中文", "zh-Hant" => "繁體中文"
  }.freeze

  REGIONAL_LANGUAGE_LABELS = {
    "en-AU" => "English (Australia)", "en-CA" => "English (Canada)",
    "en-GB" => "English (UK)", "en-US" => "English (US)",
    "es-ES" => "Español (España)", "es-MX" => "Español (México)",
    "fr-CA" => "Français (Canada)", "fr-FR" => "Français (France)",
    "nl-NL" => "Nederlands (Nederland)", "pt-BR" => "Português (Brasil)",
    "pt-PT" => "Português (Portugal)"
  }.freeze

  SUPPORT_FIELD_TEXT = {
    "en" => { "category" => "Category", "os_version" => "OS version", "categories" => %w[Question Bug Accessibility Privacy Other] },
    "fr" => { "category" => "Catégorie", "os_version" => "Version du système", "categories" => ["Question", "Bug", "Accessibilité", "Confidentialité", "Autre"] },
    "de" => { "category" => "Kategorie", "os_version" => "Betriebssystemversion", "categories" => ["Frage", "Fehler", "Barrierefreiheit", "Datenschutz", "Sonstiges"] },
    "es" => { "category" => "Categoría", "os_version" => "Versión del sistema", "categories" => ["Pregunta", "Error", "Accesibilidad", "Privacidad", "Otro"] },
    "it" => { "category" => "Categoria", "os_version" => "Versione del sistema", "categories" => ["Domanda", "Errore", "Accessibilità", "Privacy", "Altro"] },
    "pt" => { "category" => "Categoria", "os_version" => "Versão do sistema", "categories" => ["Pergunta", "Erro", "Acessibilidade", "Privacidade", "Outro"] },
    "ja" => { "category" => "カテゴリ", "os_version" => "OSバージョン", "categories" => ["質問", "不具合", "アクセシビリティ", "プライバシー", "その他"] },
    "ko" => { "category" => "분류", "os_version" => "OS 버전", "categories" => ["질문", "버그", "손쉬운 사용", "개인정보 보호", "기타"] },
    "nl" => { "category" => "Categorie", "os_version" => "Systeemversie", "categories" => ["Vraag", "Fout", "Toegankelijkheid", "Privacy", "Overig"] },
    "pl" => { "category" => "Kategoria", "os_version" => "Wersja systemu", "categories" => ["Pytanie", "Błąd", "Dostępność", "Prywatność", "Inne"] },
    "ru" => { "category" => "Категория", "os_version" => "Версия ОС", "categories" => ["Вопрос", "Ошибка", "Доступность", "Конфиденциальность", "Другое"] },
    "sv" => { "category" => "Kategori", "os_version" => "Systemversion", "categories" => ["Fråga", "Fel", "Tillgänglighet", "Integritet", "Annat"] },
    "tr" => { "category" => "Kategori", "os_version" => "Sistem sürümü", "categories" => ["Soru", "Hata", "Erişilebilirlik", "Gizlilik", "Diğer"] },
    "uk" => { "category" => "Категорія", "os_version" => "Версія ОС", "categories" => ["Запитання", "Помилка", "Доступність", "Приватність", "Інше"] },
    "zh-Hans" => { "category" => "类别", "os_version" => "系统版本", "categories" => ["问题", "错误", "辅助功能", "隐私", "其他"] },
    "zh-Hant" => { "category" => "類別", "os_version" => "系統版本", "categories" => ["問題", "錯誤", "輔助使用", "私隱", "其他"] }
  }.freeze

  DOWNLOAD_LABELS = {
    "en" => "Download on the App Store", "fr" => "Télécharger dans l’App Store",
    "de" => "Im App Store laden", "es" => "Descargar en el App Store",
    "it" => "Scarica sull’App Store", "pt" => "Baixar na App Store",
    "ja" => "App Storeでダウンロード", "ko" => "App Store에서 다운로드",
    "nl" => "Download in de App Store", "pl" => "Pobierz w App Store",
    "ru" => "Загрузить в App Store", "sv" => "Hämta i App Store",
    "tr" => "App Store’dan indirin", "uk" => "Завантажити в App Store",
    "zh-Hans" => "在 App Store 下载", "zh-Hant" => "從 App Store 下載"
  }.freeze

  UI_TEXT = {
    "en" => {
      "skip" => "Skip to content", "navigation" => "Main navigation", "features" => "What it does",
      "more_apps_short" => "More apps", "support" => "Support", "language" => "Language",
      "download" => "Download on the", "coming_soon" => "Coming soon to the", "at_a_glance" => "At a glance",
      "preview" => "Product preview", "made_for" => "Built around the real product",
      "features_heading" => "Useful details, without inflated promises.", "full_description" => "Read the full description",
      "independent_studio" => "More independent apps", "discover" => "Discover the app",
      "separate_apps" => "These are separate apps. They do not exchange data or make decisions for one another.",
      "human_support" => "Human support", "contact_heading" => "A question or something to report?",
      "contact_intro" => "Send a message through the private support form. No developer email address is published.",
      "email" => "Your email", "app_version" => "App version", "message" => "Message", "send" => "Send message",
      "sending" => "Sending…", "success" => "Message sent. Thank you.", "error" => "The message could not be sent. Please try again.",
      "independent_footer" => "An independently made app.", "legal" => "Legal links", "privacy" => "Privacy", "terms" => "Terms"
    },
    "fr" => {
      "skip" => "Aller au contenu", "navigation" => "Navigation principale", "features" => "Fonctions",
      "more_apps_short" => "Autres apps", "support" => "Assistance", "language" => "Langue",
      "download" => "Télécharger dans l’", "coming_soon" => "Bientôt dans l’", "at_a_glance" => "En bref",
      "preview" => "Aperçu du produit", "made_for" => "Conçu à partir du vrai produit",
      "features_heading" => "Des détails utiles, sans promesses exagérées.", "full_description" => "Lire la description complète",
      "independent_studio" => "D’autres apps indépendantes", "discover" => "Découvrir l’app",
      "separate_apps" => "Ces apps sont indépendantes. Elles n’échangent aucune donnée et ne prennent aucune décision l’une pour l’autre.",
      "human_support" => "Assistance humaine", "contact_heading" => "Une question ou quelque chose à signaler ?",
      "contact_intro" => "Écrivez via le formulaire d’assistance privé. Aucune adresse e-mail du développeur n’est publiée.",
      "email" => "Votre e-mail", "app_version" => "Version de l’app", "message" => "Message", "send" => "Envoyer",
      "sending" => "Envoi…", "success" => "Message envoyé. Merci.", "error" => "Le message n’a pas pu être envoyé. Réessayez.",
      "independent_footer" => "Une app créée indépendamment.", "legal" => "Liens juridiques", "privacy" => "Confidentialité", "terms" => "Conditions"
    },
    "de" => {
      "skip" => "Zum Inhalt", "navigation" => "Hauptnavigation", "features" => "Funktionen", "more_apps_short" => "Weitere Apps",
      "support" => "Support", "language" => "Sprache", "download" => "Laden im", "coming_soon" => "Demnächst im",
      "at_a_glance" => "Auf einen Blick", "preview" => "Produktvorschau", "made_for" => "Am echten Produkt ausgerichtet",
      "features_heading" => "Nützliche Details, ohne übertriebene Versprechen.", "full_description" => "Vollständige Beschreibung lesen",
      "independent_studio" => "Weitere unabhängige Apps", "discover" => "App entdecken",
      "separate_apps" => "Dies sind getrennte Apps. Sie tauschen keine Daten aus und treffen keine Entscheidungen füreinander.",
      "human_support" => "Persönlicher Support", "contact_heading" => "Eine Frage oder etwas zu melden?",
      "contact_intro" => "Schreiben Sie über das private Supportformular. Es wird keine Entwickler-E-Mail veröffentlicht.",
      "email" => "Ihre E-Mail", "app_version" => "App-Version", "message" => "Nachricht", "send" => "Nachricht senden",
      "sending" => "Wird gesendet…", "success" => "Nachricht gesendet. Danke.", "error" => "Die Nachricht konnte nicht gesendet werden. Bitte erneut versuchen.",
      "independent_footer" => "Eine unabhängig entwickelte App.", "legal" => "Rechtliche Links", "privacy" => "Datenschutz", "terms" => "Bedingungen"
    },
    "es" => {
      "skip" => "Ir al contenido", "navigation" => "Navegación principal", "features" => "Funciones", "more_apps_short" => "Más apps",
      "support" => "Soporte", "language" => "Idioma", "download" => "Descargar en el", "coming_soon" => "Próximamente en el",
      "at_a_glance" => "De un vistazo", "preview" => "Vista previa del producto", "made_for" => "Basado en el producto real",
      "features_heading" => "Detalles útiles, sin promesas exageradas.", "full_description" => "Leer la descripción completa",
      "independent_studio" => "Más apps independientes", "discover" => "Descubrir la app",
      "separate_apps" => "Son apps separadas. No intercambian datos ni toman decisiones entre sí.",
      "human_support" => "Soporte humano", "contact_heading" => "¿Tienes una pregunta o algo que comunicar?",
      "contact_intro" => "Escribe mediante el formulario privado. No se publica el correo del desarrollador.",
      "email" => "Tu correo", "app_version" => "Versión de la app", "message" => "Mensaje", "send" => "Enviar mensaje",
      "sending" => "Enviando…", "success" => "Mensaje enviado. Gracias.", "error" => "No se pudo enviar el mensaje. Inténtalo de nuevo.",
      "independent_footer" => "Una app creada de forma independiente.", "legal" => "Enlaces legales", "privacy" => "Privacidad", "terms" => "Condiciones"
    },
    "it" => {
      "skip" => "Vai al contenuto", "navigation" => "Navigazione principale", "features" => "Funzioni", "more_apps_short" => "Altre app",
      "support" => "Assistenza", "language" => "Lingua", "download" => "Scarica su", "coming_soon" => "Presto su",
      "at_a_glance" => "In breve", "preview" => "Anteprima del prodotto", "made_for" => "Costruita sul prodotto reale",
      "features_heading" => "Dettagli utili, senza promesse esagerate.", "full_description" => "Leggi la descrizione completa",
      "independent_studio" => "Altre app indipendenti", "discover" => "Scopri l’app",
      "separate_apps" => "Sono app separate. Non scambiano dati né prendono decisioni l’una per l’altra.",
      "human_support" => "Assistenza umana", "contact_heading" => "Una domanda o qualcosa da segnalare?",
      "contact_intro" => "Scrivi tramite il modulo privato. L’e-mail dello sviluppatore non viene pubblicata.",
      "email" => "La tua e-mail", "app_version" => "Versione app", "message" => "Messaggio", "send" => "Invia messaggio",
      "sending" => "Invio…", "success" => "Messaggio inviato. Grazie.", "error" => "Impossibile inviare. Riprova.",
      "independent_footer" => "Un’app creata in modo indipendente.", "legal" => "Link legali", "privacy" => "Privacy", "terms" => "Termini"
    },
    "pt" => {
      "skip" => "Ir para o conteúdo", "navigation" => "Navegação principal", "features" => "Recursos", "more_apps_short" => "Mais apps",
      "support" => "Suporte", "language" => "Idioma", "download" => "Baixar na", "coming_soon" => "Em breve na",
      "at_a_glance" => "Em resumo", "preview" => "Prévia do produto", "made_for" => "Feito a partir do produto real",
      "features_heading" => "Detalhes úteis, sem promessas exageradas.", "full_description" => "Ler a descrição completa",
      "independent_studio" => "Mais apps independentes", "discover" => "Conhecer o app",
      "separate_apps" => "São apps separados. Não trocam dados nem tomam decisões uns pelos outros.",
      "human_support" => "Suporte humano", "contact_heading" => "Alguma pergunta ou algo a relatar?",
      "contact_intro" => "Envie uma mensagem pelo formulário privado. O e-mail do desenvolvedor não é publicado.",
      "email" => "Seu e-mail", "app_version" => "Versão do app", "message" => "Mensagem", "send" => "Enviar mensagem",
      "sending" => "Enviando…", "success" => "Mensagem enviada. Obrigado.", "error" => "Não foi possível enviar. Tente novamente.",
      "independent_footer" => "Um app criado de forma independente.", "legal" => "Links legais", "privacy" => "Privacidade", "terms" => "Termos"
    },
    "ja" => {
      "skip" => "本文へ移動", "navigation" => "メインナビゲーション", "features" => "機能", "more_apps_short" => "その他のアプリ",
      "support" => "サポート", "language" => "言語", "download" => "App Storeで", "coming_soon" => "App Storeに近日登場",
      "at_a_glance" => "概要", "preview" => "製品プレビュー", "made_for" => "実際の製品に基づく設計",
      "features_heading" => "誇張せず、役立つ詳細を。", "full_description" => "詳しい説明を読む",
      "independent_studio" => "ほかの個人開発アプリ", "discover" => "アプリを見る",
      "separate_apps" => "これらは別々のアプリです。データを交換せず、互いの判断を行いません。",
      "human_support" => "人によるサポート", "contact_heading" => "ご質問やご報告がありますか？",
      "contact_intro" => "非公開のサポートフォームからお送りください。開発者のメールアドレスは公開されません。",
      "email" => "メールアドレス", "app_version" => "アプリのバージョン", "message" => "メッセージ", "send" => "送信",
      "sending" => "送信中…", "success" => "送信しました。ありがとうございます。", "error" => "送信できませんでした。もう一度お試しください。",
      "independent_footer" => "個人で開発されたアプリです。", "legal" => "法的情報", "privacy" => "プライバシー", "terms" => "利用規約"
    },
    "ko" => {
      "skip" => "콘텐츠로 이동", "navigation" => "주요 탐색", "features" => "기능", "more_apps_short" => "다른 앱",
      "support" => "지원", "language" => "언어", "download" => "App Store에서", "coming_soon" => "App Store 출시 예정",
      "at_a_glance" => "한눈에 보기", "preview" => "제품 미리보기", "made_for" => "실제 제품을 바탕으로 설계",
      "features_heading" => "과장 없이 유용한 세부 정보.", "full_description" => "전체 설명 읽기",
      "independent_studio" => "다른 독립 앱", "discover" => "앱 살펴보기",
      "separate_apps" => "각각 별도의 앱이며 데이터를 교환하거나 서로를 대신해 판단하지 않습니다.",
      "human_support" => "사람이 답하는 지원", "contact_heading" => "질문이나 신고할 내용이 있나요?",
      "contact_intro" => "비공개 지원 양식으로 보내 주세요. 개발자 이메일은 공개되지 않습니다.",
      "email" => "이메일", "app_version" => "앱 버전", "message" => "메시지", "send" => "메시지 보내기",
      "sending" => "보내는 중…", "success" => "보냈습니다. 감사합니다.", "error" => "보내지 못했습니다. 다시 시도해 주세요.",
      "independent_footer" => "독립적으로 만든 앱입니다.", "legal" => "법적 링크", "privacy" => "개인정보 보호", "terms" => "약관"
    },
    "nl" => {
      "skip" => "Naar inhoud", "navigation" => "Hoofdnavigatie", "features" => "Functies", "more_apps_short" => "Meer apps",
      "support" => "Support", "language" => "Taal", "download" => "Download in de", "coming_soon" => "Binnenkort in de",
      "at_a_glance" => "In één oogopslag", "preview" => "Productvoorbeeld", "made_for" => "Gebouwd rond het echte product",
      "features_heading" => "Nuttige details, zonder overdreven beloften.", "full_description" => "Volledige beschrijving lezen",
      "independent_studio" => "Meer onafhankelijke apps", "discover" => "Ontdek de app",
      "separate_apps" => "Dit zijn aparte apps. Ze wisselen geen gegevens uit en beslissen niet voor elkaar.",
      "human_support" => "Persoonlijke support", "contact_heading" => "Een vraag of iets te melden?",
      "contact_intro" => "Stuur een bericht via het privéformulier. Het e-mailadres van de ontwikkelaar is niet openbaar.",
      "email" => "Je e-mail", "app_version" => "Appversie", "message" => "Bericht", "send" => "Bericht verzenden",
      "sending" => "Verzenden…", "success" => "Bericht verzonden. Bedankt.", "error" => "Verzenden mislukt. Probeer opnieuw.",
      "independent_footer" => "Een onafhankelijk gemaakte app.", "legal" => "Juridische links", "privacy" => "Privacy", "terms" => "Voorwaarden"
    },
    "pl" => {
      "skip" => "Przejdź do treści", "navigation" => "Główna nawigacja", "features" => "Funkcje", "more_apps_short" => "Więcej aplikacji",
      "support" => "Pomoc", "language" => "Język", "download" => "Pobierz w", "coming_soon" => "Wkrótce w",
      "at_a_glance" => "W skrócie", "preview" => "Podgląd produktu", "made_for" => "Oparte na prawdziwym produkcie",
      "features_heading" => "Przydatne szczegóły bez przesadnych obietnic.", "full_description" => "Przeczytaj pełny opis",
      "independent_studio" => "Więcej niezależnych aplikacji", "discover" => "Poznaj aplikację",
      "separate_apps" => "To osobne aplikacje. Nie wymieniają danych ani nie podejmują decyzji za siebie nawzajem.",
      "human_support" => "Pomoc od człowieka", "contact_heading" => "Pytanie lub coś do zgłoszenia?",
      "contact_intro" => "Napisz przez prywatny formularz. Adres e-mail twórcy nie jest publikowany.",
      "email" => "Twój e-mail", "app_version" => "Wersja aplikacji", "message" => "Wiadomość", "send" => "Wyślij",
      "sending" => "Wysyłanie…", "success" => "Wysłano. Dziękujemy.", "error" => "Nie udało się wysłać. Spróbuj ponownie.",
      "independent_footer" => "Niezależnie stworzona aplikacja.", "legal" => "Linki prawne", "privacy" => "Prywatność", "terms" => "Warunki"
    },
    "ru" => {
      "skip" => "К содержимому", "navigation" => "Основная навигация", "features" => "Возможности", "more_apps_short" => "Другие приложения",
      "support" => "Поддержка", "language" => "Язык", "download" => "Загрузить в", "coming_soon" => "Скоро в",
      "at_a_glance" => "Кратко", "preview" => "Предпросмотр", "made_for" => "Основано на реальном продукте",
      "features_heading" => "Полезные детали без завышенных обещаний.", "full_description" => "Читать полное описание",
      "independent_studio" => "Другие независимые приложения", "discover" => "Открыть приложение",
      "separate_apps" => "Это отдельные приложения. Они не обмениваются данными и не принимают решения друг за друга.",
      "human_support" => "Поддержка человеком", "contact_heading" => "Есть вопрос или сообщение?",
      "contact_intro" => "Напишите через закрытую форму. Адрес разработчика не публикуется.",
      "email" => "Ваш e-mail", "app_version" => "Версия приложения", "message" => "Сообщение", "send" => "Отправить",
      "sending" => "Отправка…", "success" => "Отправлено. Спасибо.", "error" => "Не удалось отправить. Повторите попытку.",
      "independent_footer" => "Независимо созданное приложение.", "legal" => "Правовая информация", "privacy" => "Конфиденциальность", "terms" => "Условия"
    },
    "sv" => {
      "skip" => "Till innehållet", "navigation" => "Huvudnavigering", "features" => "Funktioner", "more_apps_short" => "Fler appar",
      "support" => "Support", "language" => "Språk", "download" => "Hämta i", "coming_soon" => "Kommer snart till",
      "at_a_glance" => "I korthet", "preview" => "Produktförhandsvisning", "made_for" => "Byggd kring den riktiga produkten",
      "features_heading" => "Användbara detaljer utan överdrivna löften.", "full_description" => "Läs hela beskrivningen",
      "independent_studio" => "Fler oberoende appar", "discover" => "Upptäck appen",
      "separate_apps" => "Det här är separata appar. De utbyter inte data och fattar inte beslut åt varandra.",
      "human_support" => "Mänsklig support", "contact_heading" => "En fråga eller något att rapportera?",
      "contact_intro" => "Skicka via det privata formuläret. Utvecklarens e-postadress publiceras inte.",
      "email" => "Din e-post", "app_version" => "Appversion", "message" => "Meddelande", "send" => "Skicka",
      "sending" => "Skickar…", "success" => "Skickat. Tack.", "error" => "Kunde inte skickas. Försök igen.",
      "independent_footer" => "En oberoende skapad app.", "legal" => "Juridiska länkar", "privacy" => "Integritet", "terms" => "Villkor"
    },
    "tr" => {
      "skip" => "İçeriğe geç", "navigation" => "Ana gezinme", "features" => "Özellikler", "more_apps_short" => "Diğer uygulamalar",
      "support" => "Destek", "language" => "Dil", "download" => "App Store’dan", "coming_soon" => "Yakında App Store’da",
      "at_a_glance" => "Kısaca", "preview" => "Ürün önizlemesi", "made_for" => "Gerçek ürün temel alınarak tasarlandı",
      "features_heading" => "Abartılı vaatler olmadan yararlı ayrıntılar.", "full_description" => "Tam açıklamayı oku",
      "independent_studio" => "Diğer bağımsız uygulamalar", "discover" => "Uygulamayı keşfet",
      "separate_apps" => "Bunlar ayrı uygulamalardır. Veri alışverişi yapmaz ve birbirleri adına karar vermezler.",
      "human_support" => "İnsan desteği", "contact_heading" => "Sorunuz veya bildiriminiz mi var?",
      "contact_intro" => "Özel destek formundan yazın. Geliştirici e-postası yayınlanmaz.",
      "email" => "E-postanız", "app_version" => "Uygulama sürümü", "message" => "Mesaj", "send" => "Mesaj gönder",
      "sending" => "Gönderiliyor…", "success" => "Mesaj gönderildi. Teşekkürler.", "error" => "Gönderilemedi. Tekrar deneyin.",
      "independent_footer" => "Bağımsız geliştirilmiş bir uygulama.", "legal" => "Yasal bağlantılar", "privacy" => "Gizlilik", "terms" => "Koşullar"
    },
    "uk" => {
      "skip" => "До вмісту", "navigation" => "Головна навігація", "features" => "Можливості", "more_apps_short" => "Інші застосунки",
      "support" => "Підтримка", "language" => "Мова", "download" => "Завантажити в", "coming_soon" => "Незабаром в",
      "at_a_glance" => "Коротко", "preview" => "Перегляд продукту", "made_for" => "На основі реального продукту",
      "features_heading" => "Корисні деталі без перебільшених обіцянок.", "full_description" => "Читати повний опис",
      "independent_studio" => "Інші незалежні застосунки", "discover" => "Переглянути застосунок",
      "separate_apps" => "Це окремі застосунки. Вони не обмінюються даними й не ухвалюють рішень один за одного.",
      "human_support" => "Підтримка людиною", "contact_heading" => "Маєте запитання або повідомлення?",
      "contact_intro" => "Напишіть через приватну форму. Адреса розробника не публікується.",
      "email" => "Ваш e-mail", "app_version" => "Версія застосунку", "message" => "Повідомлення", "send" => "Надіслати",
      "sending" => "Надсилання…", "success" => "Надіслано. Дякуємо.", "error" => "Не вдалося надіслати. Спробуйте ще раз.",
      "independent_footer" => "Незалежно створений застосунок.", "legal" => "Правові посилання", "privacy" => "Приватність", "terms" => "Умови"
    },
    "zh-Hans" => {
      "skip" => "跳到内容", "navigation" => "主导航", "features" => "功能", "more_apps_short" => "更多 App",
      "support" => "支持", "language" => "语言", "download" => "下载于", "coming_soon" => "即将登陆",
      "at_a_glance" => "概览", "preview" => "产品预览", "made_for" => "基于真实产品设计",
      "features_heading" => "实用细节，不夸大承诺。", "full_description" => "阅读完整介绍",
      "independent_studio" => "更多独立 App", "discover" => "了解 App",
      "separate_apps" => "这些是彼此独立的 App，不交换数据，也不会替对方做决定。",
      "human_support" => "人工支持", "contact_heading" => "有问题或需要反馈？",
      "contact_intro" => "请通过私密支持表单发送。开发者邮箱不会公开。",
      "email" => "您的邮箱", "app_version" => "App 版本", "message" => "消息", "send" => "发送",
      "sending" => "正在发送…", "success" => "已发送，谢谢。", "error" => "发送失败，请重试。",
      "independent_footer" => "一款独立制作的 App。", "legal" => "法律链接", "privacy" => "隐私", "terms" => "条款"
    },
    "zh-Hant" => {
      "skip" => "跳至內容", "navigation" => "主導覽", "features" => "功能", "more_apps_short" => "更多 App",
      "support" => "支援", "language" => "語言", "download" => "下載自", "coming_soon" => "即將登上",
      "at_a_glance" => "概覽", "preview" => "產品預覽", "made_for" => "依據真實產品設計",
      "features_heading" => "實用細節，不誇大承諾。", "full_description" => "閱讀完整介紹",
      "independent_studio" => "更多獨立 App", "discover" => "了解 App",
      "separate_apps" => "這些是彼此獨立的 App，不交換資料，也不會替對方作決定。",
      "human_support" => "人工支援", "contact_heading" => "有問題或需要回報？",
      "contact_intro" => "請透過私密支援表單傳送。開發者電郵不會公開。",
      "email" => "您的電郵", "app_version" => "App 版本", "message" => "訊息", "send" => "傳送",
      "sending" => "傳送中…", "success" => "已傳送，謝謝。", "error" => "無法傳送，請再試一次。",
      "independent_footer" => "一款獨立製作的 App。", "legal" => "法律連結", "privacy" => "私隱", "terms" => "條款"
    }
  }.freeze

  class Renderer
    attr_reader :repo_root, :config, :locale, :root_page, :source_digest

    def initialize(repo_root:, config:, locale:, root_page:, source_digest:, template:)
      @repo_root = repo_root
      @config = config
      @locale = locale
      @root_page = root_page
      @source_digest = source_digest
      @template = template
      @metadata = load_metadata
    end

    def render
      ERB.new(@template, trim_mode: "-").result(binding).gsub(/[ \t]+(?=\n)/, "")
    end

    def h(value)
      CGI.escapeHTML(value.to_s)
    end

    def json_ld
      JSON.generate(schema_data).gsub("</", "<\\/")
    end

    def base_url
      config.fetch("base_url")
    end

    def app_name
      config.fetch("app_name")
    end

    def app_store_url
      config["app_store_url"]
    end

    def app_store_id
      app_store_url&.match(%r{/id(\d+)(?:\z|[/?#])})&.captures&.first
    end

    def app_store_badge_src
      badges = config.fetch("app_store_badges", {})
      path = badges[locale]
      path && asset_prefix + path
    end

    def app_store_download_label
      DOWNLOAD_LABELS.fetch(language_key, DOWNLOAD_LABELS.fetch("en"))
    end

    def hero_raster
      asset_prefix + config.fetch("design_contract").fetch("hero_raster")
    end

    def hero_raster_url
      base_url + config.fetch("design_contract").fetch("hero_raster")
    end

    def hero_alt
      localized_value(config.fetch("design_contract").fetch("hero_alt"), fallback: app_name)
    end

    def secondary_action
      config["secondary_action"]
    end

    def html_lang
      locale.tr("_", "-")
    end

    def text_direction
      %w[ar he fa ur].include?(language_key) ? "rtl" : "ltr"
    end

    def asset_prefix
      root_page ? "" : "../"
    end

    def canonical_url
      root_page ? base_url : "#{base_url}#{locale}/"
    end

    def marketing_name
      @metadata.fetch("name")
    end

    def subtitle
      @metadata.fetch("subtitle")
    end

    def hero_pitch
      @metadata.fetch("promotional_text").empty? ? description_paragraphs.first.to_s : @metadata.fetch("promotional_text")
    end

    def eyebrow
      localized_value(config.fetch("eyebrow", {}), fallback: ui.fetch("independent_footer"))
    end

    def truth_points
      values = config.fetch("truth_points", {})
      return values if values.is_a?(Array)
      return [] unless values.is_a?(Hash)

      selected = values[locale] || values[language_key]
      selected.is_a?(Array) ? selected : []
    end

    def related_heading
      localized_value(config.fetch("related_heading", {}), fallback: ui.fetch("more_apps_short"))
    end

    def related_apps
      config.fetch("related_apps", [])
    end

    def screenshots
      localized_value(config.fetch("screenshots", {}), fallback: [], allow_array: true).first(3)
    end

    def screenshot_src(screenshot)
      url = screenshot.fetch("url")
      url.start_with?(base_url) ? asset_prefix + url.delete_prefix(base_url) : url
    end

    def description_paragraphs
      @description_paragraphs ||= paragraphs(@metadata.fetch("description"))
    end

    def web_description_paragraphs
      @web_description_paragraphs ||= description_paragraphs.map { |paragraph| feature_prose(paragraph) }
    end

    def features
      configured = localized_value(config.dig("editorial", "features"), fallback: [], allow_array: true)
      return configured.map { |feature| { title: feature.fetch("title", ""), body: feature.fetch("body") } } unless configured.empty?

      @features ||= extract_features(description_paragraphs)
    end

    def ui
      UI_TEXT.fetch(language_key, UI_TEXT.fetch("en"))
    end

    def support_field_text
      SUPPORT_FIELD_TEXT.fetch(language_key, SUPPORT_FIELD_TEXT.fetch("en"))
    end

    def page_title
      subtitle.empty? ? marketing_name : "#{marketing_name} — #{subtitle}"
    end

    def meta_description
      shorten(hero_pitch.empty? ? description_paragraphs.first.to_s : hero_pitch, 158)
    end

    def language_options
      config.fetch("locales").map do |entry|
        code = entry.fetch("code")
        label = entry["label"] || REGIONAL_LANGUAGE_LABELS[code] || LANGUAGE_LABELS.fetch(language_key(code), code)
        selected = root_page ? code == config.fetch("primary_locale") : code == locale
        { url: "#{base_url}#{code}/", label: label, selected: selected }
      end
    end

    def hreflang_links
      config.fetch("locales").map { |entry| { locale: entry.fetch("code"), url: "#{base_url}#{entry.fetch("code")}/" } }
    end

    def privacy_url
      localized_public_file("privacy.html", config.fetch("privacy_path", "privacy.html"))
    end

    def terms_url
      return nil unless config["terms_path"]
      localized_public_file("terms.html", config.fetch("terms_path"))
    end

    def localized_value(value, fallback: "", allow_array: false)
      return value if value.is_a?(String)
      return value if allow_array && value.is_a?(Array)
      return fallback unless value.is_a?(Hash)

      selected = value[locale] || value[language_key] || value["default"] || value["en"]
      return fallback if selected.nil?
      return selected if selected.is_a?(String) || (allow_array && selected.is_a?(Array))

      fallback
    end

    private

    def language_key(value = locale)
      self.class.language_key(value)
    end

    def self.language_key(value)
      normalized = value.to_s.tr("_", "-")
      return "zh-Hans" if normalized.downcase.start_with?("zh-hans")
      return "zh-Hant" if normalized.downcase.start_with?("zh-hant")

      normalized.split("-").first.downcase
    end

    def load_metadata
      locale_entry = config.fetch("locales").find { |entry| entry.fetch("code") == locale }
      locale_entry ||= config.fetch("locales").find { |entry| entry.fetch("code") == config.fetch("primary_locale") }
      source = locale_entry.fetch("source", locale_entry.fetch("code"))
      root = repo_root.join(config.fetch("metadata_root"), source)
      overrides = config.fetch("content_overrides", {}).fetch(locale, {})
      {
        "name" => overrides.fetch("name", read_text(root.join("name.txt"), config.fetch("app_name"))),
        "subtitle" => overrides.fetch("subtitle", read_text(root.join("subtitle.txt"), "")),
        "promotional_text" => overrides.fetch("promotional_text", read_text(root.join("promotional_text.txt"), "")),
        "description" => overrides.fetch("description", read_text(root.join("description.txt"), ""))
      }
    end

    def read_text(path, fallback)
      return fallback unless path.file?
      path.read(encoding: "UTF-8").strip
    end

    def paragraphs(text)
      text.to_s.gsub("\r\n", "\n").split(/\n\s*\n+/).map(&:strip).reject(&:empty?)
    end

    def extract_features(items)
      candidates = []
      cursor = 1
      while cursor < items.length && candidates.length < 5
        paragraph = items[cursor]
        lines = paragraph.lines.map(&:strip).reject(&:empty?)
        if lines.length > 1 && heading?(lines.first)
          candidates << { title: lines.first, body: feature_prose(lines.drop(1)) }
        elsif heading?(paragraph) && items[cursor + 1]
          candidates << { title: paragraph, body: feature_prose(items[cursor + 1]) }
          cursor += 1
        elsif paragraph.length >= 48
          candidates << { title: "", body: feature_prose(paragraph) }
        end
        cursor += 1
      end
      candidates = [{ title: "", body: feature_prose(items.first.to_s) }] if candidates.empty?
      candidates
    end

    def feature_prose(value)
      lines = Array(value).flat_map { |entry| entry.to_s.lines }.map(&:strip).reject(&:empty?)
      lines.map { |line| line.sub(/\A[-•]\s*/, "") }.join(lines.length > 1 ? "; " : " ")
    end

    def heading?(text)
      compact = text.to_s.strip
      return false if compact.empty? || compact.length > 64 || compact.end_with?(".", "!", "?", "。");
      letters = compact.scan(/\p{L}/)
      return true if letters.length >= 3 && compact == compact.upcase
      compact.length <= 28
    end

    def shorten(text, limit)
      compact = text.to_s.gsub(/\s+/, " ").strip
      return compact if compact.length <= limit
      compact[0, limit - 1].sub(/\s+\S*\z/, "").rstrip + "…"
    end

    def localized_public_file(basename, fallback)
      localized_path = repo_root.join(config.fetch("docs_dir", "docs"), locale, basename)
      localized_path.file? ? "#{base_url}#{locale}/#{basename}" : "#{base_url}#{fallback}"
    end

    def schema_data
      data = {
        "@context" => "https://schema.org", "@type" => "SoftwareApplication", "name" => marketing_name,
        "description" => meta_description, "url" => canonical_url, "image" => hero_raster_url,
        "operatingSystem" => config.fetch("operating_system", "iOS"),
        "applicationCategory" => config.fetch("application_category", "UtilitiesApplication"),
        "softwareVersion" => config["public_version"], "author" => { "@type" => "Person", "name" => "bnjdpn" }
      }
      data["downloadUrl"] = app_store_url if app_store_url
      data.compact
    end
  end

  class Generator
    attr_reader :repo_root, :config_path, :config, :docs_root

    def initialize(repo_root:, config_path:)
      @repo_root = Pathname.new(repo_root).expand_path
      @config_path = Pathname.new(config_path).expand_path
      @config = JSON.parse(@config_path.read(encoding: "UTF-8"))
      @docs_root = @repo_root.join(@config.fetch("docs_dir", "docs"))
      validate_config!
    end

    def run(check:)
      outputs = build_outputs
      problems = compare(outputs)
      if check
        if problems.empty?
          puts "Marketing site is current: #{config.fetch("app_name")} (#{outputs.length} managed files)."
          return true
        end
        warn "Marketing site is stale: #{config.fetch("app_name")}"
        problems.each { |problem| warn "- #{problem}" }
        return false
      end

      outputs.each do |relative, content|
        path = repo_root.join(relative)
        path.dirname.mkpath
        mode = content.encoding == Encoding::BINARY ? "wb" : "w"
        File.open(path, mode) { |file| file.write(content) }
      end
      puts "Generated #{outputs.length} marketing site files for #{config.fetch("app_name")}."
      true
    end

    private

    def validate_config!
      %w[app_name slug base_url metadata_root icon_path primary_locale locales art_direction theme_color].each do |key|
        raise KeyError, "Missing #{key} in #{config_path}" unless config.key?(key)
      end
      raise "base_url must end with /" unless config.fetch("base_url").end_with?("/")
      design_contract = config.fetch("design_contract")
      raise "design_contract.template_id must be present" if design_contract.fetch("template_id").to_s.strip.empty?
      raise "design_contract.hero_raster must be a public raster path" unless design_contract.fetch("hero_raster").match?(/\Aassets\/.+\.(?:png|jpe?g|webp)\z/i)
      raise "design_contract.forbid_css_illustration must be true" unless design_contract.fetch("forbid_css_illustration") == true
      editorial = config.fetch("editorial")
      %w[nav_label section_kicker section_heading details_label proof_caption features].each { |key| editorial.fetch(key) }
      codes = config.fetch("locales").map { |entry| entry.fetch("code") }
      raise "Duplicate marketing locales" unless codes.uniq.length == codes.length
      raise "primary_locale must be listed" unless codes.include?(config.fetch("primary_locale"))
      if config["app_store_url"]
        badge_codes = config.fetch("app_store_badges", {}).keys
        missing_badges = codes - badge_codes
        raise "Missing localized App Store badges for #{missing_badges.join(", ")}" unless missing_badges.empty?
      end
      raise "No public developer email or mailto allowed" if JSON.generate(config).match?(/mailto:|[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i)
      config.fetch("locales").each do |entry|
        source = entry.fetch("source", entry.fetch("code"))
        metadata = repo_root.join(config.fetch("metadata_root"), source)
        override = config.fetch("content_overrides", {}).key?(entry.fetch("code"))
        raise "Missing metadata source #{metadata}" unless metadata.directory? || override
      end
      validate_metadata_urls!
      raise "Missing icon #{config.fetch("icon_path")}" unless repo_root.join(config.fetch("icon_path")).file?
      raise "Missing theme marketing/theme.css" unless repo_root.join("marketing/theme.css").file?
    end

    def validate_metadata_urls!
      metadata_root = repo_root.join(config.fetch("metadata_root"))
      return unless metadata_root.directory?

      locale_dirs = metadata_root.children.select do |child|
        child.directory? && child.basename.to_s != "review_information" &&
          %w[name.txt subtitle.txt promotional_text.txt description.txt].any? { |file| child.join(file).file? }
      end
      expected = {
        "marketing_url.txt" => config.fetch("base_url"),
        "support_url.txt" => "#{config.fetch("base_url")}#contact"
      }
      locale_dirs.each do |locale_dir|
        expected.each do |file, value|
          path = locale_dir.join(file)
          raise "Missing #{path.relative_path_from(repo_root)}" unless path.file?
          actual = path.read(encoding: "UTF-8").strip
          raise "#{path.relative_path_from(repo_root)} must be #{value.inspect}, got #{actual.inspect}" unless actual == value
        end
      end
    end

    def build_outputs
      template_path = repo_root.join("marketing/site.html.erb")
      base_css_path = repo_root.join("marketing/base.css")
      js_path = repo_root.join("marketing/site.js")
      theme_path = repo_root.join("marketing/theme.css")
      template = template_path.read(encoding: "UTF-8")
      digest = source_digest([template_path, base_css_path, js_path, theme_path])
      outputs = {}
      primary = config.fetch("primary_locale")
      outputs[managed("index.html")] = Renderer.new(repo_root: repo_root, config: config, locale: primary, root_page: true, source_digest: digest, template: template).render
      config.fetch("locales").each do |entry|
        locale = entry.fetch("code")
        outputs[managed(File.join(locale, "index.html"))] = Renderer.new(repo_root: repo_root, config: config, locale: locale, root_page: false, source_digest: digest, template: template).render
      end
      config.fetch("redirect_locales", []).each do |locale|
        outputs[managed(File.join(locale, "index.html"))] = redirect_page(locale)
      end
      outputs[managed("assets/base.css")] = base_css_path.read(encoding: "UTF-8")
      outputs[managed("assets/theme.css")] = theme_path.read(encoding: "UTF-8")
      outputs[managed("assets/site.js")] = js_path.read(encoding: "UTF-8")
      outputs[managed("assets/app-icon.png")] = repo_root.join(config.fetch("icon_path")).binread.force_encoding(Encoding::BINARY)
      config.fetch("local_assets", []).each do |asset|
        source = repo_root.join(asset.fetch("source"))
        raise "Missing local marketing asset #{source}" unless source.file?
        outputs[managed(asset.fetch("path"))] = source.binread.force_encoding(Encoding::BINARY)
      end
      outputs[managed("site.webmanifest")] = JSON.pretty_generate(web_manifest) + "\n"
      outputs[managed("sitemap.xml")] = sitemap
      outputs[managed("robots.txt")] = "User-agent: *\nAllow: /\nSitemap: #{config.fetch("base_url")}sitemap.xml\n"
      outputs[managed(".nojekyll")] = ""
      outputs
    end

    def source_digest(common_paths)
      digest = Digest::SHA256.new
      paths = [config_path, repo_root.join(config.fetch("icon_path")), *common_paths]
      paths.concat(config.fetch("local_assets", []).map { |asset| repo_root.join(asset.fetch("source")) })
      config.fetch("locales").each do |entry|
        source = entry.fetch("source", entry.fetch("code"))
        %w[name.txt subtitle.txt promotional_text.txt description.txt].each do |file|
          path = repo_root.join(config.fetch("metadata_root"), source, file)
          paths << path if path.file?
        end
      end
      paths.uniq.sort_by(&:to_s).each { |path| digest << path.relative_path_from(repo_root).to_s << "\0" << path.binread << "\0" }
      digest.hexdigest
    end

    def managed(relative)
      File.join(config.fetch("docs_dir", "docs"), relative)
    end

    def compare(outputs)
      outputs.each_with_object([]) do |(relative, expected), differences|
        path = repo_root.join(relative)
        if !path.file?
          differences << "missing #{relative}"
        elsif path.binread != expected.b
          differences << "stale #{relative}"
        end
      end
    end

    def redirect_page(locale)
      target = config.fetch("base_url")
      "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"robots\" content=\"noindex\"><meta http-equiv=\"refresh\" content=\"0; url=#{CGI.escapeHTML(target)}\"><link rel=\"canonical\" href=\"#{CGI.escapeHTML(target)}\"><title>#{CGI.escapeHTML(config.fetch("app_name"))}</title></head><body><p><a href=\"#{CGI.escapeHTML(target)}\">Continue to #{CGI.escapeHTML(config.fetch("app_name"))}</a></p><!-- unsupported product locale: #{CGI.escapeHTML(locale)} --></body></html>\n"
    end

    def web_manifest
      {
        "name" => config.fetch("app_name"), "short_name" => config.fetch("app_name"), "start_url" => "./",
        "display" => "standalone", "background_color" => config.fetch("background_color", config.fetch("theme_color")),
        "theme_color" => config.fetch("theme_color"),
        "icons" => [{ "src" => "assets/app-icon.png", "sizes" => "1024x1024", "type" => "image/png" }]
      }
    end

    def sitemap
      urls = [config.fetch("base_url")] + config.fetch("locales").map { |entry| "#{config.fetch("base_url")}#{entry.fetch("code")}/" }
      body = urls.map { |url| "  <url><loc>#{CGI.escapeHTML(url)}</loc></url>" }.join("\n")
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n#{body}\n</urlset>\n"
    end
  end
end

require_relative "marketing_seo"
PortfolioMarketingSeo.install!

if $PROGRAM_NAME == __FILE__
  options = { check: false, stage: nil }
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby scripts/marketing_site.rb [--check] [--config PATH]"
    parser.on("--check", "Fail when committed output is stale") { options[:check] = true }
    parser.on("--stage DIR", "Stage the exact Pages artifact; target must be _site") { |value| options[:stage] = value }
    parser.on("--config PATH", "Config path relative to repo root") { |value| options[:config] = value }
  end.parse!

  repo_root = Pathname.new(__dir__).join("..").expand_path
  config_path = repo_root.join(options[:config] || "marketing/site.json")
  generator = PortfolioMarketingSite::Generator.new(repo_root: repo_root, config_path: config_path)
  success = generator.run(check: options.fetch(:check))
  generator.stage!(options[:stage]) if success && options[:stage]
  exit(success ? 0 : 1)
end
