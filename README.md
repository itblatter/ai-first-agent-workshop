# UI tests: GitHub search

Учебный проект UI-автотестов на Java: Selenide + JUnit 5 + Gradle, тесты ищут репозитории на github.com. Page Object, Allure Report 2, CI на GitHub Actions и Jenkins с уведомлениями в Telegram.

## Требования

- JDK 17+ (проверено на Temurin 21); Gradle не нужен — есть Wrapper 9.2.0.
- `JAVA_HOME` должен указывать на установленный JDK: он нужен Allure CLI.
- Chrome для локального запуска; ChromeDriver подбирает Selenium Manager.
- Windows PowerShell 5.1+ для локальных Telegram-проверок; CI Actions использует `pwsh`.
- Linux: bash, curl, tar, sha256sum, unzip; Jenkins разворачивает PowerShell 7.6.7 портативно, без установки системных пакетов.

Все команды ниже выполняются из корня репозитория.

## Локальный запуск

```powershell
.\gradlew.bat test --console=plain
```

Linux/macOS: `./gradlew test --console=plain`.

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

Генератор — закреплённый CLI 2.46.1, устанавливается в `.tools/` (вне Git).
В CI установка находится непосредственно в workflow/Jenkinsfile; отдельного setup-скрипта нет.
Для локального использования сначала установить тот же ZIP с проверкой SHA-256.

### Установка на Windows

```powershell
$ErrorActionPreference = 'Stop'
$version = '2.46.1'
$sha256 = 'd25c519bbde940dc953cff8901130ce18b73013dc19a8f8b90b8b4b1c5eb252f'
$tools = Join-Path (Get-Location).Path '.tools'
$archive = Join-Path $tools "allure-commandline-$version.zip"
$allure = Join-Path $tools "allure-$version/bin/allure.bat"
if (-not $env:JAVA_HOME -or -not (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin/java.exe'))) {
    throw 'Set JAVA_HOME to an installed JDK.'
}
New-Item -ItemType Directory -Path $tools -Force | Out-Null
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -UseBasicParsing `
        -Uri "https://repo.maven.apache.org/maven2/io/qameta/allure/allure-commandline/$version/allure-commandline-$version.zip" `
        -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $sha256) {
    throw 'Allure ZIP SHA-256 mismatch; the archive was not extracted.'
}
if (-not (Test-Path -LiteralPath $allure)) {
    Expand-Archive -LiteralPath $archive -DestinationPath $tools
}
$actualVersion = & $allure --version
if ($LASTEXITCODE -ne 0 -or "$actualVersion".Trim() -ne $version) {
    throw "Expected Allure $version, got: $actualVersion"
}
```

### Установка на Linux

```bash
(
    set -eu
    version=2.46.1
    sha256=d25c519bbde940dc953cff8901130ce18b73013dc19a8f8b90b8b4b1c5eb252f
    tools="$PWD/.tools"
    archive="$tools/allure-commandline-$version.zip"
    allure="$tools/allure-$version/bin/allure"
    test -n "${JAVA_HOME:-}" && test -f "$JAVA_HOME/bin/java"
    mkdir -p "$tools"
    if [ ! -f "$archive" ]; then
        curl --disable --fail --location --silent --proto '=https' --proto-redir '=https' \
            --connect-timeout 10 --max-time 300 --output "$archive" \
            "https://repo.maven.apache.org/maven2/io/qameta/allure/allure-commandline/$version/allure-commandline-$version.zip"
    fi
    printf '%s  %s\n' "$sha256" "$archive" | sha256sum --check -
    if [ ! -f "$allure" ]; then
        unzip -q "$archive" -d "$tools"
    fi
    chmod a+x "$allure"
    test "$("$allure" --version)" = "$version"
)
```

На macOS этот установочный блок требует GNU `sha256sum`; его наличие здесь не предполагается.

### Генерация и открытие

```powershell
.\.tools\allure-2.46.1\bin\allure.bat generate build\allure-results --clean -o build\allure-report
.\.tools\allure-2.46.1\bin\allure.bat open build\allure-report
```

```bash
./.tools/allure-2.46.1/bin/allure generate build/allure-results --clean -o build/allure-report
./.tools/allure-2.46.1/bin/allure open build/allure-report
```

Сырые результаты — `build/allure-results`, готовый отчёт — `build/allure-report`, JUnit — `build/test-results/test`. Всё это в `.gitignore`.

`--clean` у генератора очищает только готовый отчёт. Повторный `gradlew test` может быть `UP-TO-DATE`,
а результаты Allure накапливаются. Для нового независимого локального прогона можно использовать
`.\gradlew.bat clean test --console=plain` или `./gradlew clean test --console=plain`,
но **`clean` удалит весь прежний `build/`** — предварительно сохраните нужные отчёты.
Автоматическая очистка и принудительный перезапуск в CI в эту доработку не входят.

## CI

### GitHub Actions — `.github/workflows/ci.yml`

Ручной `workflow_dispatch` (Actions → UI Tests → Run workflow), входы: `browser` (chrome), `browserSize` (`WIDTHxHEIGHT`). Job `ui-tests` на `windows-2022`: headless-тесты, загрузка `allure-results`, `gradle-test-reports`, `allure-report` (7 дней). Job `telegram` — одно уведомление по итогу; ошибки доставки не меняют статус `ui-tests`.

Секреты репозитория: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`.

### Jenkins — `Jenkinsfile`

Job `ai-first-itblatter-hw1` на https://jenkins.qa.guru/ — «Pipeline script from SCM», `*/main`. Агент `java-jdk21-jenkins-agent-1`; pwsh и Allure CLI разворачиваются портативно в workspace inline-блоком `Prepare agent tools` в Jenkinsfile. Тесты выполняются на удалённом Selenoid, `headless=false`.

Параметры job: `UI_BASE_URL`, `UI_BROWSER`, `UI_BROWSER_VERSION`, `UI_BROWSER_SIZE`, `SEND_TELEGRAM` и password-параметры `SELENOID_USER`, `SELENOID_PASSWORD`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`. Параметры определяются в настройках job, не в Jenkinsfile.

Текущий fallback секретов сохранён: полный непустой набор четырёх password-параметров записывается
в `.ci-secrets.env` (chmod 600) в workspace. Иначе, если файл существует, из него заполняются все четыре
env; при проверке наличия секретов env имеет приоритет над параметрами. Поэтому частично переданные
новые значения могут быть вытеснены сохранёнными. Все четыре секрета требуются даже при
`SEND_TELEGRAM=false`. Файл игнорируется Git и не архивируется. Изменение этой схемы — отдельная задача.

Post-обработка: JUnit (`build/test-results/test/TEST-*.xml`), архивация сырых результатов и `build/allure-report` от CLI 2.46.1, страница отчёта плагина (`/job/.../<N>/allure/`), одно Telegram-уведомление. Падение тестов → `FAILURE`; ошибки JUnit/Allure/Telegram изолированы и не перетирают исходный результат.

Канонический отчёт — архив `build/allure-report` от закреплённого CLI; страница плагина использует
инструмент, настроенный на Jenkins, его версия может отличаться. Отсутствие результатов в Jenkins
допускается, ошибки генератора перехватываются; Actions считает отсутствие результатов,
ненулевой код генератора и отсутствие `index.html` ошибками job. Эти различия сохранены.
Архивация сырых результатов Jenkins не обёрнута в catch: её ошибка может прервать последующие post-шаги.

### Источники настроек

| Настройка | Источник и приоритет |
|---|---|
| Defaults браузера | `TestBase`: JVM `selenide.*` → `UI_*` env → default; пустая строка считается заданным значением |
| Передача JVM-настроек | Allowlist шести свойств в `build.gradle`; в CI сохранены явные `-D` аргументы, а не только env |
| Actions inputs | Один mapping `browser`/`browserSize` в `UI_BROWSER`/`UI_BROWSER_SIZE` у job `ui-tests` |
| Allure version / SHA-256 ZIP | `ALLURE_VERSION` / `ALLURE_SHA256` в env тестового job Actions и в environment Jenkinsfile; оба закрепления нужно обновлять согласованно |
| Путь Allure в Actions | Успешная установка записывает абсолютный `ALLURE_COMMAND` через `GITHUB_ENV`; генерация использует его |
| PowerShell Linux version / SHA-256 | `PWSH_VERSION` / `PWSH_SHA256` только в Jenkinsfile; используются и при установке, и при запуске уведомителя |
| Gradle / Actions | Wrapper properties / полные SHA непосредственно в workflow |
| Секреты | Actions secrets; Jenkins password-параметры и существующий fallback-файл; не смешиваются с версиями инструментов |

Повтор двух констант Allure между CI и примерами локальной установки — осознанный компромисс
варианта с минимумом файлов. Общего конфигурационного файла и shell-парсера нет. Подготовка
PowerShell использует игнорируемый `.tool-home/` только внутри установочного процесса.
На Linux загрузка Allure теперь выполняется `curl` с connect timeout 10 секунд и общим
timeout 300 секунд, без ретраев; Windows сохраняет `Invoke-WebRequest` и timeout шага 5 минут.

## Типовые проблемы

- **`UI_BROWSER_SIZE must match WIDTHxHEIGHT`** — задайте размер вида `1920x1080`.
- **`parameter not set` / `SELENOID_USER and SELENOID_PASSWORD parameters are required`** — в Jenkins секреты не заполнены и `.ci-secrets.env` ещё не записан: заполните password-параметры один раз.
- **`Telegram notification: failed`** — с агента Jenkins сетевой доступ до `api.telegram.org` нестабилен; отправитель сам зондирует известные IP и подключается к живому. Недоставка — warning, статус сборки не меняется.
- **`No Allure test results were produced`** — тесты не успели записать результаты (падение до старта JVM); смотрите лог Gradle.

## Структура

```
src/test/java/tests/    TestBase + SearchTests (3 сценария)
src/test/java/pages/    Page Object: SearchPage, RepositoryPage
ci/                     ci-telegram.ps1, jenkins-telegram.ps1, test-ci-telegram.ps1
.github/workflows/ci.yml  GitHub Actions
Jenkinsfile               Jenkins pipeline
docs/plans/ui-test-project.md  план фаз, решения и проверки
docs/retrospective.md          ретроспектива
AGENTS.md                      правила работы агента
```

### Telegram-скрипты и локальная проверка

- `ci/ci-telegram.ps1` — общие функции чтения JUnit XML, формирования сообщения и транспорта.
  Dot-source только определяет функции; сам по себе ничего не отправляет.
- `ci/jenkins-telegram.ps1` — исполняемая Jenkins-обвязка: читает `TELEGRAM_BOT_TOKEN`,
  `TELEGRAM_CHAT_ID`, `UI_PROJECT`, `UI_BRANCH`, `UI_JOB_RESULT`, `UI_TEST_OUTCOME`, `UI_RUN_URL`
  из env, зондирует IP и вызывает общий отправитель. Всегда заканчивается `exit 0`.
  Необязательный `-ResultsDirectory` задаёт каталог XML; default вычисляется от расположения
  файла: `<repo>/build/test-results/test`, независимо от cwd. Явный относительный путь — относительно cwd.
  **Не запускайте эту обвязку для локальной проверки:** она выполняет сетевые обращения.
- `ci/test-ci-telegram.ps1` — проверка без сети с подменённым транспортом и синтетическими секретами.
  Создаёт собственные fixtures в `build/phase6-tests-*/`; предварительный запуск Gradle не нужен.

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\ci\test-ci-telegram.ps1
```

Ожидается 248 assertions (PowerShell 5.1+). При блокировке Execution Policy нужно согласовать
разрешение запуска в своей среде; скрипт сам политику не меняет.
На Linux с установленным PowerShell: `pwsh -NoLogo -NoProfile -NonInteractive -File ci/test-ci-telegram.ps1`.

Старые пути `scripts/` больше не являются точками входа. Внешние локальные команды нужно перевести
на `ci/`; установку Allure — на блоки выше. Исторические записи плана и ретроспективы не переписываются.

Секреты не коммитятся; `.env`, `.ci-secrets.env`, `build/`, `.tools/`, `.tool-home/` — в `.gitignore`.
