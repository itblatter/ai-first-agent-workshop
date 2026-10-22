---
description: "Выбор исполнителя для тестовых job'ов по типам тестов (best practice)"
trigger: glob
globs: ".github/workflows/**,Jenkinsfile,ci/**,src/test/**,build.gradle,knowledge/**"
---

При добавлении или изменении тестовых job'ов в CI выбирать исполнителя по типу
тестов (полная таксономия — `knowledge/test-taxonomy/test-taxonomy.md`):

- `frontend-unit-tests` — JS/TS из репозитория фронтенда; драйвер не нужен.
- `ui-tests` (mock/WireMock, нет реального URL) — драйвер из раннера; в Selenoid
  не запускаются; в пайплайне — до сборки фронтенда.
- `e2e-tests` — Selenium-ферма (Selenoid/Grid) ради многопоточности; драйвер
  раннера допустим только для очень малого набора; в пайплайне — после deploy.
