# Классификация автотестов и выбор исполнителя

Best practice от преподавателей. Применяется при проектировании CI-пайплайна,
добавлении тестовых job'ов и выборе способа запуска браузера.

## Три уровня тестов

| Тип | Что это | Стек / репозиторий | Исполнитель |
|---|---|---|---|
| `frontend-unit-tests` | Unit-тесты фронтенда | JS/TS, репозиторий фронтенда | Раннер напрямую; браузер и драйвер не нужны |
| `ui-tests` | Selenium/Playwright-тесты с mock (WireMock) | Язык e2e-тестов, отдельный репозиторий | Драйвер из раннера |
| `e2e-tests` | Тесты против развёрнутого стенда | Язык e2e-тестов, отдельный репозиторий | Selenium-ферма: Selenoid / Selenium Grid |

## Правила выбора исполнителя

### ui-tests — драйвер из раннера

- Тесты работают с mock (WireMock), реального URL приложения нет — поэтому
  из Selenoid их не запустить: удалённому браузеру нечего открывать.
- Запускаются **до сборки фронтенда**: mock подменяет фронт, артефакт сборки
  не нужен.
- Браузер ставится на раннер (образ CI), драйвер подбирается локально —
  Selenium Manager или аналог.

### e2e-tests — Selenium-ферма

- Тесты тяжелее и их больше — нужна многопоточность, которую даёт ферма
  (Selenoid, Selenium Grid).
- Запуск против развёрнутого окружения (stage/prod), поэтому есть реальный
  URL для удалённого браузера.
- Допустим запуск с драйвером раннера только если тестов очень мало — это
  не best practice, а компромисс для маленького набора.

## Эталонный порядок job'ов в пайплайне

Пример: [run 38936910957](https://github.com/autotests-ai/autotests-ai-multistack-app/actions/runs/38936910957)
репозитория `autotests-ai/autotests-ai-multistack-app` (~13 минут, push в main).

```
trigger → infra-tests, backend-unit-tests, frontend-unit-tests, sonar-tests,
          integration-tests, ui-tests          ← ui-tests до сборки фронта
        → build-backend, sonar-backend, sonar-frontend, build-frontend
        → deploy-backend-stage, deploy-frontend-stage
        → api-tests-stage, e2e-tests-stage     ← e2e против stage
        → deploy-backend-load, deploy-backend, deploy-frontend
        → load-tests, api-tests, e2e-tests     ← e2e против prod
        → manual-tests → publish-allure-report → deploy-github-pages
```

Ключевая закономерность: `ui-tests` стоят до `build-frontend`,
`e2e-tests*` — после соответствующего `deploy-*`.

## Как это ложится на этот репозиторий

Оба паттерна уже продемонстрированы одним и тем же набором тестов:

- GitHub Actions (`ui-tests` job в `.github/workflows/ci.yml`) — паттерн
  «драйвер из раннера»: Chrome из образа `ubuntu-24.04`, драйвер подбирает
  Selenium Manager, `UI_REMOTE` не задан.
- Jenkins (`Jenkinsfile`) — паттерн «ферма»: те же тесты идут на удалённый
  Selenoid через `UI_REMOTE` + `SELENOID_USER`/`SELENOID_PASSWORD`.
- Точка переключения — `selenide.remote` / `UI_REMOTE` в
  `src/test/java/tests/TestBase.java`: пустое значение — локальный драйвер,
  заданное — remote webdriver с `selenoid:options`.

Ограничение текущего проекта относительно эталона: тесты ходят на настоящий
github.com без mock, поэтому по таксономии они ближе к маленькому e2e-набору
(допустим на драйвере раннера), чем к ui-tests с WireMock.
