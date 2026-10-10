# kmp-agents

Пять независимых git-репозиториев. `KMP_template_shared` — KMP-модуль, остальные четыре — нативные потребители.
Каталог `~/kmp-agents` сам тоже репозиторий (харнесс: `scripts/`, `.claude/agents/`, `logs/`).

| Каталог | Что это | Сборка |
|---|---|---|
| `KMP_template_shared` | KMP-модуль `:shared`: Kotlin 2.2.0, таргеты android/ios/jvm/js. Единственный источник контракта. | Gradle |
| `KMP_template_android` | Android-приложение (Compose) | Gradle |
| `KMP_template_desktop` | JavaFX-приложение, Java 17 | Maven |
| `KMP_template_ios` | SwiftUI-приложение | Xcode |
| `KMP_template_web` | Vite-страница | npm |

## Контракт и expect/actual
Публичный API живёт в `KMP_template_shared/shared/src/commonMain` (сейчас `SystemInfo().getInfo()`).
Платформенные части подключаются через `expect fun getPlatform()` и `actual` в `androidMain`, `iosMain`, `jvmMain`, `jsMain`.
Потребители вызывают shared в одной точке каждый (`MainActivity.kt`, `Main.java`, `ContentView.swift`, `app.js`).

## Как shared доходит до платформ
- android, desktop: через `~/.m2` (mavenLocal): `shared-android:1.0`, `shared-jvm:1.0`.
- ios: готовый `shared.xcframework` в `KMP_template_ios/Packages/KMPTemplate`, подключён как локальный SPM-пакет. CocoaPods нет.
- web: каталог `shared/build/dist/js/productionLibrary` подключён симлинком в `node_modules`; JS-зависимости дистрибутива должны быть объявлены в `package.json` web.

Всё это раскладывает `scripts/propagate.sh`. Агенты его не запускают.

## Роли и порядок работы
1. `orchestrator` — разбирает задачу, ведёт процесс, запускает скрипты, проверяет отчёты и коммитит. Код не правит.
2. `shared-agent` — правит только `KMP_template_shared`.
3. `ios-agent` — правит только `KMP_template_ios`.
Порядок: orchestrator → shared-agent → `propagate.sh` → ios-agent → `build-all.sh` → проверка отчётов по `git diff` и `build-all` → коммиты.
Агент, которому нужна правка вне его каталога, не обходит запрет, а пишет её в `NOT_DONE` своего отчёта.

## Только оркестратор
`scripts/propagate.sh`, `scripts/build-all.sh`, `scripts/check-propagation.sh`, любой `publish*`, любые `git commit`, изменения в `~/kmp-agents/scripts` и `.claude`.
Платформенные агенты проверяют работу только сборкой своего проекта и возвращают отчёт в формате из своего описания.
