# UI tests: GitHub search

Учебный проект UI-автотестов на Java: Selenide + JUnit 5 + Gradle, тесты ищут репозитории на github.com. Page Object, Allure Report 2, CI на GitHub Actions и Jenkins с уведомлениями в Telegram.

## Требования

- JDK 17+ (проверено на Temurin 21); Gradle не нужен — есть Wrapper 9.2.0.
- Chrome для локального запуска; ChromeDriver подбирает Selenium Manager.
- Windows PowerShell 5.1+ для `setup-allure.ps1`, bash для `setup-agent-tools.sh`.

## Локальный запуск

```powershell
.\gradlew.bat test --console=plain
```

Переопределение конфигурации (приоритет: JVM-параметр → переменная окружения → default):

| JVM-параметр | Env | Default |
|---|---|---|
| `selenide.baseUrl` | `UI_BASE_URL` | `https://github.com` |
| `selenide.browser` | `UI_BROWSER` | `chrome` |
| `selenide.browserSize` | `UI_BROWSER_SIZE` | `1920x1080` |
| `selenide.headless` | `UI_HEADLESS` | `false` |
| `selenide.remote` | `UI_REMOTE` | — (локальный браузер) |
| `selenide.browserVersion` | `UI_BROWSER_VERSION` | — |

```powershell
.\gradlew.bat test "-Dselenide.headless=true" "-Dselenide.browserSize=1366x768"
```

Удалённый браузер (Selenoid) — URL с кредами только в переменной окружения:

```bash
export UI_REMOTE="https://user:pass@selenoid.qa.guru/wd/hub"
./gradlew test "-Dselenide.browserVersion=155.0"
```

## Allure Report 2

Генератор — закреплённый CLI 2.46.1, устанавливается в `.tools/` (вне Git):

```powershell
.\scripts\setup-allure.ps1
.\.tools\allure-2.46.1\bin\allure.bat generate build\allure-results --clean -o build\allure-report
.\.tools\allure-2.46.1\bin\allure.bat open build\allure-report
```

Сырые результаты — `build/allure-results`, готовый отчёт — `build/allure-report`, JUnit — `build/test-results/test`. Всё это в `.gitignore`.

## CI

### GitHub Actions — `.github/workflows/ci.yml`

Ручной `workflow_dispatch` (Actions → UI Tests → Run workflow), входы: `browser` (chrome), `browserSize` (`WIDTHxHEIGHT`). Job `ui-tests` на `windows-2022`: headless-тесты, загрузка `allure-results`, `gradle-test-reports`, `allure-report` (7 дней). Job `telegram` — одно уведомление по итогу; ошибки доставки не меняют статус `ui-tests`.

Секреты репозитория: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`.

### Jenkins — `Jenkinsfile`

Job `ai-first-itblatter-hw1` на https://jenkins.qa.guru/ — «Pipeline script from SCM», `*/main`. Агент `java-jdk21-jenkins-agent-1`; pwsh и Allure CLI разворачиваются портативно в workspace (`scripts/setup-agent-tools.sh`). Тесты выполняются на удалённом Selenoid.

Параметры job: `UI_BASE_URL`, `UI_BROWSER`, `UI_BROWSER_VERSION`, `UI_BROWSER_SIZE`, `SEND_TELEGRAM` и password-параметры `SELENOID_USER`, `SELENOID_PASSWORD`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`. Введённые секреты один раз сохраняются в `.ci-secrets.env` (chmod 600) в workspace агента и переиспользуются следующими сборками при пустых параметрах; файл в `.gitignore`, не архивируется.

Post-обработка: JUnit (`build/test-results/test/TEST-*.xml`), архивация сырых результатов и `build/allure-report` от CLI 2.46.1, страница отчёта плагина (`/job/.../<N>/allure/`), одно Telegram-уведомление. Падение тестов → `FAILURE`; ошибки JUnit/Allure/Telegram изолированы и не перетирают исходный результат.

## Типовые проблемы

- **`UI_BROWSER_SIZE must match WIDTHxHEIGHT`** — задайте размер вида `1920x1080`.
- **`parameter not set` / `SELENOID_USER and SELENOID_PASSWORD parameters are required`** — в Jenkins секреты не заполнены и `.ci-secrets.env` ещё не записан: заполните password-параметры один раз.
- **`Telegram notification: failed`** — с агента Jenkins сетевой доступ до `api.telegram.org` нестабилен; отправитель сам зондирует известные IP и подключается к живому. Недоставка — warning, статус сборки не меняется.
- **`No Allure test results were produced`** — тесты не успели записать результаты (падение до старта JVM); смотрите лог Gradle.

## Структура

```
src/test/java/tests/    TestBase + SearchTests (3 сценария)
src/test/java/pages/    Page Object: SearchPage, RepositoryPage
scripts/                setup-allure.ps1, setup-agent-tools.sh,
                        ci-telegram.ps1, jenkins-telegram.ps1, test-ci-telegram.ps1
.github/workflows/ci.yml  GitHub Actions
Jenkinsfile               Jenkins pipeline
docs/ui-test-project.md   план фаз, решения и проверки
```

Проверка скрипта уведомлений без сети: `.\scripts\test-ci-telegram.ps1` (248 assertions, PowerShell 5.1+).

Секреты не коммитятся; `.env`, `.ci-secrets.env`, `build/`, `.tools/` — в `.gitignore`.
