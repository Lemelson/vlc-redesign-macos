# Исправления после двух аудитов VLC Redesign — 2026-10-15

Рабочая ветка: `codex/audit-fixes-2026-10-15`, создана от
`3bbac3cb632016edb20c6fe751425ed10d6f3faa` (`claude/polish`). Изменения локальные,
без коммита, push и установки приложения. Исходные
[ChatGPT-аудит](audits/chatgpt-2026-10-15.md) и
[Claude-аудит](audits/claude-2026-10-15.md) сохранены без изменений.

Десять исполнителей GPT-6.1 Sol / medium работали в отдельных worktree по областям:
профили, настройки, медиатека, плеер, панели, диалоги, macOS, сборка, медиа,
дизайн. После интеграции проведена перекрёстная проверка намерения, контрактов,
безопасности упаковки, надёжности и визуальных изменений. Она нашла семь
дополнительных дефектов; они исправлены до полного интеграционного прогона.
Финальный перечитатель отдельно обнаружил устаревшие ожидания двух Lua runtime
тестов. Ниже исходниковая проверка отделена от приёмки установленного приложения.

## Главный результат и границы

- Исправлены откат настроек при запуске, удаление чужого вхождения плейлиста,
  команды за модальным диалогом, невидимый перехватчик полной библиотеки и гонка
  завершения библиотечного worker. Добавлены регрессии на эти сценарии.
- Обычная полоса перемотки больше не обновляет всё SwiftUI-дерево каждый кадр.
  Это проверенное изменение механизма; новый расход CPU ещё не измерен.
- Упаковка подписывает зависимости до генерации plugin cache; установка проходит
  через staging и rollback, запрещает выходящие из бандла ссылки и замену
  работающего приложения. Реальную установку в этой сессии не выполняли.
- Убраны GUI-регистрация и активация XCTest-процесса. Полный прогон выполняет
  **354 из 354 обнаруженных XCTest, без пропусков и ошибок** после финальной коррекции клика.
- **Исходники не равны установленному бинарнику.** `/Applications/VLC Redesign.app`
  не пересобирался, не устанавливался и не запускался в ходе этих исправлений.
  Новые оценки0–100 не выставляются: для них нужна повторная приёмка реального окна.
- `src/`, `lib/`, `include/` и штатный `modules/gui/macosx/` не изменены относительно
  `upstream-base-2026-10-14`. Личный `/Applications/VLC.app` не запускался.

Обозначения в таблицах: **И** — исправление подтверждено исходниками и указанными
локальными контрактами/тестами; **Ч** — частичное исправление или ограничение;
**О** — исходное утверждение не подтвердилось либо требовало уточнения;
**Н** — осталось непроверенным/нереализованным. Даже **И** не означает приёмку
VoiceOver, аппаратуры, выходного файла или настоящего окна.

## Проверки интегрированной ветки

Команды запускаются из корня репозитория; `M=modules/gui/macosx_redesign`.

| Проверка | Результат и предел доказательства |
|---|---|
| `python3 "$M/tools/run-swift-tests.py" "$M" "$M/.build"` | PASS:354 обнаруженных XCTest выполнены,0 пропусков,0 ошибок. Корневой запуск после интеграции обеих волн и click correction. Проверка сопоставляет имена discovery и результаты, а не только код выхода. |
| `gen-tokens.py --check`, `gen-icons.py --check` | PASS; генераторы не перезаписывали файлы. |
| Семь `test-*.py` из `check-macosx-redesign` | PASS:26 тестов — packaging3, build contracts4, finalizer4, installer5, schema drift5, results parser3, runtime isolation2. Использованы одноразовые каталоги/подставные инструменты; это не фактическое подписание и установка. |
| `native-tests.py --engine-build ../build/codex-arm64 --suite contracts` | PASS: схема, media-chain contract, subtitle parser; наследование default rate на реальном core; библиотечные lifetime/sort fixtures; pinch и Now Playing policy. |
| Та же команда с `--suite build-runtime` | PASS: шесть native runtime harness компилируются и линкуются. **Не выполнялись** library/audio/media/fixture runtime сценарии. |
| Та же команда с `--suite extensions` | PASS: реальные Lua discovery/install/remove, отказ execution без dialog provider, exactly-once completion и shutdown. Только Lua/dummy plugins, одноразовый userdata, ignore-config; без app/GUI/аппаратуры/сети. |
| `clang -fsyntax-only` с конфигурацией этого engine build | PASS для15 `.m`, включая bootstrap, vout и PlayerBridge; отдельно от успешной компоновки service harness. |
| Engine/stock-GUI diff | Пустой; optional engine patches не применялись. |
| Strict Figma comparison, выполненный исполнителем | Полное offscreen Hide UI: PASS. Обычный S01: FAIL (mean0.15/255, structure0.138%); пороги не ослаблялись, отличие не объявлено исправленным. |

Сессия доказательств: `/private/tmp/vlc-audit-fixes-20261015-o6xwcm2e/`.
Основные логи: `integrated-swift-final-plus-click.log`, `integrated-contracts-final.log`,
`integrated-native-links-plus-harness.log`, `integrated-native-syntax-final.log`,
`integrated-script-checks-final.log`, `integrated-runtime-isolation-tests.log`,
`integrated-extensions-runtime-final.log`. Там же baseline SHA-256 исходных аудитов,
патчи обеих волн, manifests и независимые `review-*.md` / `final-review-*.md`.
Временные файлы может удалить macOS; результат и ограничения сохранены здесь.

Первый интеграционный прогон выявил устаревшие ожидания в четырёх тестах, в том
числе тесты, открывавшие новый диалог поверх незакрытого. Они обновлены под
явную modal isolation, сохранены отдельные проверки запрета замены открытой
формы и identity плейлистов. Полный последующий прогон зелёный.

## Что изменено

### Профили, настройки и сохранённое состояние

`AppStores.swift` больше не применяет снимок профиля при `connect`: сохранённое
самим VLC состояние остаётся главным. Профили ограничены опциями каталога,
мигрируются без потери имён/раскладок; legacy app keys исключены. В
`PresetStore.swift` сохранённый Automatic отличается от незахваченной секции.
Обратная совместимость старых неоднозначных presets определяется при применении
по полноте захваченной секции; массового переписывания старых записей нет.

`MXRServicesBridge.m` и Settings adapters исправляют единицы subtitle delay,
живое состояние playlist order/repeat, cache hotkeys, сохранение Always у resume,
передачу ошибок записи и переменные, наследуемые будущими input. Изменение
default rate не меняет текущий input. Output jobs берут свежие include flags
из config, а не старые значения из своего player.

Доказательства: `ProfileAuditRegressionTests`, `SettingsAuditRegressionTests`
(Core и Backend), `SettingsBackendEventTests`,
`module/bridge/tests/MXRSettingsInheritanceTests.c`.

### Медиатека и native lifetime

`MediaItem`/`LibraryModel`/`MXRLibraryServices.m` различают media ID, вхождение
плейлиста, исходную позицию и revision. Удаление проверяет исходное вхождение;
поиск/сортировка/дубликаты не превращают экранный offset в индекс хранения.
Sort импортированных Videos/Songs выполняется до pagination. Где VLC поддерживает
нативную пагинацию, применяются limit/offset; fallback сортируется и кэшируется.

Add File импортирует в библиотеку. Show All сохраняет выборку Home section;
компактная Home показывает две секции. Музыкальные папки получают музыкальные
сортировки. Истинные даты новых импортов сохраняются; неизвестные даты не
выдумываются из ID.

Expansion worker регистрируется до dispatch; shutdown дожидается принятых workers
перед освобождением preparser. Доказательства: `LibraryAuditRegressionTests`,
`LibraryWireRegressionTests`, `NativeLibraryLifetimeRegression.m`,
`NativeLibraryImportSortRegression.m`. Последний production fixture имеет14
проверок; исполнитель также прогнал его под ASan. Реальная пользовательская ML
не изменялась, разрушительное удаление в ней не выполнялось.

### Плеер, попапы и модальность

`NativeSeekProgress.swift` изолирует частый redraw от SwiftUI state. Мини-плеер
наблюдает точный `scrubTime`, включая движения в пределах одной секунды.
Mini/timeline scrubbing применяет общий coalescing и точный последний seek.
Сырые paused still не показываются при несовместимом subtitle/effect состоянии;
ограничение D031 остаётся.

Исправлены семантика компактного overflow, узкий toast/длинный breadcrumb,
маска waveform, настраиваемый PiP и лишняя граница нижнего бара. Queue выбирает
сразу, захватывает модификаторы при клике, имеет keyboard/AX actions. Контекстные
меню queue/bookmarks используют дизайн-попапы; bookmark rename встроен в строку.

`InterfaceModel`/`AppModel`/`MXRDialogHost` не оставляют невидимую панель поверх
полной библиотеки и не заменяют форму скрытой командой. Нативные file picker
входят в ту же политику. Settings→Shortcuts возвращается в Settings. Hide UI
скрывает metadata и resume toast. Open при autoplay OFF использует scoped
start-paused; явный Play остаётся явным. Settings info использует дизайн-попап.

Доказательства: `ModalIsolationTests`, `ModalCaptureTests`, `OpenAutoplayTests`,
`PlayerProgressRegressionTests`, `MiniPlayerSeekBindingTests`,
`PanelAuditRegressionTests`, `ConeScrollIsolationTests` и обновлённые dialog tests.

### macOS, доступность и архитектура

Menu bar Audio/Video/Subtitles использует общие модели; PiP проходит validation
и отражает состояние. Pinch и interactive DVD/filter pointer events передаются
через native host/последовательную очередь. Search имеет одну регистрацию
⌥⌘F; ⌘F остаётся VLC fullscreen. Now Playing учитывает freeze/resume/скачки
времени, сохраняя dedup линейного проигрывания. PiP имеет placeholder.

Seek/volume представлены доступными Slider, подписи времени — настоящими
действиями Button. OSD справа сверху, с отдельными масштабируемыми токенами и
announcement; исправлена ошибочная строка спеки. Secondary text использует
контрастные семантические токены; focus непрозрачен, Increase Contrast учитывается.
Фактическая навигация VoiceOver/Full Keyboard Access ещё не принята.

Имена services/commands/requests моста стали типизированными константами; только
намеренная фабрика `settingOption(_:)` создаёт динамические setting services.
Dictionary payloads остаются долгом. CoreAudio/camera enumeration перенесено из UI
в typed Sendable backend worker, mocks детерминированы. Mock Quit не завершает
процесс. Core всё ещё содержит AppKit conveniences и UI перечисляет optical volumes.

`ARCHITECTURE.md` теперь описывает существующие файлы, один hosting view и прямые C
API вместо несуществующего shim. Старый `CODEX_STATUS` помечен историческим;
DECISIONS дополнен D037–D041. Исходные аудиты не переписаны.

### Медиа, сборка и проверяемость

Output chain поддерживает display duplicate, streaming keep и свежие include
flags; conversion должен завершать файл. Сохранённые subtitle rules мигрируют
множественные local/remote selections и не зависят от autodetect. Folder scans
ушли с MainActor; shared actor ограничивает конкурентность, cancellation передаётся
owned worker и проверяется в проходах. Один блокирующий filesystem syscall всё
ещё нельзя прервать.

Discovery запускается при browsing; plist имеет Local Network purpose text.
Нет провайдера Lua extension-dialog: activation/trigger честно блокируются,
installation/deactivation сохранены. HDR/resolution больше не обещают live
действие, которое bridge отвергает; resolution относится к будущему adaptive input.

Automake учитывает удалённые inputs, source dist включает ресурсы/иконку/helpers,
check запускает generator/schema/native gates. Новый `native-tests.py` сохраняет
fixtures и provenance, runtime gates выделены явно. `run-swift-tests.py` проверяет
полноту выполнения XCTest. `finalize-app.py` и installer проверяют containment,
cache/sign order и безопасную замену. Ранее игнорируемый installer теперь включён
в module exceptions `.gitignore` и доступен для будущего коммита.

## Сопоставление с ChatGPT-аудитом: все36 IDs

| ID | Статус | Итог |
|---|---|---|
| WIN-01 | И | Hide UI скрывает metadata/toast; model/composition regression. |
| WIN-02 | И | Бюджет ширины folder chip и compact geometry; настоящее окно ещё не снято. |
| CTL-01 | Ч | Guard не показывает заведомо неверный raw still; processed-vout paused frame не реализован. |
| CTL-02 | И | Overflow сохраняет конкретную семантику control. |
| CTL-03 | И | Toast ограничен доступной шириной; narrow geometry contract. |
| PNL-01 | И | Единый setter включает/выключает background по opacity. |
| PNL-02 | И | Automatic отделён от uncaptured; есть миграция и регрессия. |
| PNL-03 | И | Add to Playlist доступен в player submenu. |
| LIB-01, LIB-02 | И | Occurrence/revision/position, отдельная identity повторных строк. |
| LIB-03 | И | Add File вызывает import, не enqueue-only. |
| LIB-04 | И | Home section destinations сохраняют фильтр/порядок. |
| LIB-05 | И | Sort определяется разрешённой music category. |
| LIB-06 | Ч | Title и известные даты сортируются; исторически неизвестные даты нельзя восстановить. |
| SET-01 | И | Seconds↔deciseconds, шаг0.1s. |
| SET-02 | И | Open paused привязан к открываемому input. |
| SET-03 | И | Config и live playlist state связаны. |
| SET-04 | Ч | Job flags/chain исправлены; receiver/local display/два последовательных item не проверены. |
| SET-05 | И | Инвалидация всех key/global-key writes. |
| SET-06 | И | Help согласован с reset confirmation. |
| SET-07 | И | Асинхронная ошибка сохранения отражается пользователю; pending state не выдаётся за success. |
| SET-08, SET-09 | И | Explicit local/remote multiple rules мигрируют и применяются независимо от autodetect. |
| NAT-02 | И | Одна ⌥⌘F регистрация; ⌘F не перехватывается search. |
| NAT-04 | И | Native pointer reports реализованы; реальный DVD не проверен. |
| NAT-05 | И | Контрастные secondary tokens; численные contrast tests. |
| PER-01 | И | Worker registration/join до preparser release; deterministic lifetime fixture. |
| PER-02 | Ч | I/O off-main и cancellation; отдельный syscall всё ещё блокирующий. |
| PER-03 | И | Mini использует ScrubSession, precise final и точную fill binding. |
| ARC-01 | И | Required icon/resources/helpers в source distribution contract. |
| ARC-02 | И | SwiftPM вызывается с проверкой изменившегося набора inputs, включая deletion. |
| TST-01 | И | Schema drift gate и policy входят в check. |
| TST-02 | Ч | Настоящий titled offscreen host заменил surrogate; установленное окно автоматикой не принято. |
| DOC-01 | И | BUILD указывает актуальный installer, старые binary evidence помечены историческими. |
| CMP-01 | О | All-four-tabs формулировка исправлена по Figma/D033; Playback preset не выдуман. |
| SET-10 | И | Rate inheritance и свежие per-job output flags; actual-core rate contract прошёл. |

## Сопоставление с Claude-аудитом: все основные IDs

| IDs | Статус | Итог |
|---|---|---|
| PLAYER-02, PLAYER-V01 | И | Immediate selection, захват modifiers при событии; двойной клик запускает. |
| PLAYER-03, PLAYER-V02, PLAYER-V03 | И | OSD top-right, отдельные scaling tokens, исправлена спека/D027. |
| PLAYER-01 | И | Queue/bookmark custom context menus и inline rename. |
| PLAYER-04 | И | PiP зависит от layout. |
| PLAYER-05 | И | Лишняя тёмная граница убрана. |
| PLAYER-06 | И | Tracking activeInActiveApp. |
| PLAYER-07 | Ч | OSD announcement есть; роли всех custom popup menu items ещё не приняты raw AX/VoiceOver. |
| PLAYER-08 | И | Segmented tab accessibility, keyboard/AX row actions; actual FKA отдельно. |
| PLAYER-09 | И | Cone wheel adjustment с modal guard и очисткой накопления. |
| PLAYER-10 | И | Waveform mask совпадает с head position. |
| PLAYER-11 | И | Disabled double-click action больше не задерживает single click; timing regression и integrated354 PASS. |
| PLAYER-13 | Ч | Model pin regression добавлен, immediate queue selection проверен; actual anchored popup UI ещё не принят. |
| LIBSET-01, LIBSET-07, LIBSET-V01 | И | Startup profile не воспроизводит устаревший config; catalog-only migration. |
| LIBSET-02 | Ч | Native paging/cache исправляют повторные O(N) страницы; начальные fallback и Home N+1 остаются. |
| LIBSET-03 | И | Metadata-only starter streams описаны в D039. |
| LIBSET-04 | Н | Light material/backdrop нуждается в реальном screenshot; не исправлялся догадкой по mock. |
| LIBSET-05 | Н | Settings Figma FAIL из-за D035 остаётся; маска/порог для скрытия отличий не добавлялись. |
| LIBSET-06 | О | Artist chip уже существует при наличии artist; безусловное отсутствие не подтвердилось. |
| LIBSET-10 | О | Прямое чтение соответствующих Figma fills и source не подтвердило предложенную замену цветов; цвета не меняли наугад. |
| LIBSET-09 | Н | Чистый onboarding с новой пользовательской ML не запускался. |
| PERF-01 | Ч | Убран главный full-tree animation trigger; CPU видимых/скрытых баров не измерен, advanced timeline требует отдельного профиля. |
| PERF-02 | И | Sign dependencies→cache→non-deep seal; metadata guard. Реальный stale-cache startup ещё не проверен. |
| A11Y-01 | И | Slider representation/value, настоящие time actions; raw AX принят только после runtime gate. |
| PERF-03 | И | Lazy discovery и Local Network plist key. Реальные multicast/permission не проверены. |
| NAT-01 | И | Общие Audio/Video/Subtitles menu models. |
| PERF-04 | Н | Exit latency не измерен; приписывать его только discovery оснований нет. |
| PERF-05 | И | Clock-aware Now Playing/PiP dedup, freeze/resume/discontinuity regressions. |
| NAT-02, NAT-03 | И | PiP validation/checkmarks и magnification policy с modal guard. |
| NAT-04 | Ч | PiP placeholder/seek redraw gating; новый CPU и реальный PiP не проверены. |
| A11Y-02 | Ч | Increase Contrast/secondary text исправлены; полная Differentiate Without Color приёмка отсутствует. |
| A11Y-03 | И | Queue/bookmark move AX/keyboard; library arrows. Реальный VoiceOver отдельно. |
| A11Y-04 | И | OSD announcements добавлены. |
| A11Y-05 | И | Метка времени выполняет заявленное действие, duration не объявляется ложным editor. |
| A11Y-06 | Ч | Opaque neutral focus вместо30% accent; фактические все фоны/акценты ещё не приняты. |
| CODE-01 / CODE-V01 | И | Offscreen XCTest без GUI lifecycle; completeness runner, полный зелёный прогон. |
| CODE-02 | Ч | Typed service/command/request names и constants contract; dictionary fields/value DTOs остаются. |
| CODE-03 | И | As-built architecture, historical status notice и актуальный BUILD. История решений не удалена. |
| CODE-04 / COMP-12 | Ч | Real titled gallery host + strict whole-window comparison; shipping app screenshot ещё отсутствует. |
| CODE-05 | Ч | Native check/fixtures/provenance воспроизводимы; stale Lua harness исправлены и isolated extensions gate выполнен. Остальные runtime gates отдельно. |
| CODE-06 | Ч | Hardware backend worker/mocks и safe mock Quit; AppKit conveniences/optical filesystem в Core/UI остаются. |
| CODE-08 | Н | Полная декомпозиция огромных native/catalog файлов не выполнена. |
| CODE-09 | Ч | Добавлены осмысленные semantic/OSD tokens; полный перенос всех handwritten metrics не выполнен. |
| CODE-10 | И | Generator checks в локальном check; отдельный CI не создан, D017 local workflow сохранён. |
| CODE-11 | И | Instruction/landing exceptions D005 явно записаны D040. |
| CODE-07 | О | Вечный deadlock не подтверждён; worker lifetime исправлен отдельно, cancel callback semantics сохранены. |
| COMP-01, COMP-02, COMP-03 | И | Visible-popup gating, correct occurrence removal, modal isolation. |
| COMP-04 | О | Не воспроизведено: исходный recorder прошёл offscreen NSWindow.sendEvent(Esc); live app event order ещё не принят. |
| COMP-05 | Ч | Resolution future adaptive input; unsupported HDR объяснён и заблокирован, полноценный HDR transform не реализован. |
| COMP-10 | Ч | Небезопасная activation скрыта/disabled; Lua dialog provider отсутствует. |
| COMP-06 | И | Неработающий Rescan Plugins удалён из каталога. |
| COMP-07 | Н | OpenSubtitles по D014 остаётся без реализации/ключа. |
| COMP-08 | Ч | Неточная подсказка больше не выдаёт ограничение интерфейса за ограничение VLC; external audio-track editing в ML ещё не реализован. |
| COMP-09 | И | Folder chip реального контекста и повторный toggle; узкая геометрия. |
| COMP-11 | Ч | Timeline coalescing исправлен; upstream thumbnail software decoder без engine patch остаётся. |
| COMP-13 | И | Add to Playlist в player menu. |
| COMP-14 | И | Полные section destinations и две compact Home секции. |
| COMP-15 | Ч | Pause pin записан как provisional D041; намерение автора ещё не подтверждено. |
| COMP-16 | И | Нужные subtitle/rotation sliders добавлены. |
| COMP-17 | И | Tri-state restore-playback-pos сохраняет Always. |
| COMP-18 | Ч | Lazy discovery/long folder исправлены; filename extension сохраняет VLC semantics; drop/fullscreen subtitle acceptance не выполнена. |
| COMP-V01 | И | Settings info — дизайн-попап без NSPopover arrow. |
| COMP-V02 | О | Старые несовместимые проценты не переносятся в новый итог; исторические аудиты не редактировались. |

## Семь дефектов, найденных проверяющими после первой волны

1. Packaging мог следовать внешним symlink до проверки: containment проверяется
   до вызова изменяющих инструментов, разрешены внутренние framework links.
2. Installer мог оставить повреждённый destination: staging/finalization до swap,
   backup/rollback, cleanup и отказ при работающем приложении.
3. Now Playing dedup терял freeze/resume при buffering: clock policy отслеживает
   ход времени, discontinuity и дрейф;400 линейных точек не порождают400 updates.
4. Отменённый detached subtitle scan продолжал I/O: owned cancellation + serial
   actor + cooperative checks. Детерминированные barrier tests воспроизводят RED.
5. Cone wheel обходил modal policy: blocked events проходят дальше, остаток дельты
   очищается; targeted isolation tests.
6. Импортированные native строки сортировались после разбиения страницы: теперь
   до pagination; RED12 из14 assertions, GREEN14 из14 под ASan.
7. Mini-player терял same-second scrub invalidation из-за coarse clock: binding
   читает точный scrubTime; RED5 failures, GREEN9 focused tests.

OSD documentation mismatch исправлен дополнительно. Финальные перечитыватели
подтвердили интеграцию packaging и typed/native modal изменений; это bounded
source review, а не независимый полный повторный аудит продукта.

После этого исправлены ещё два узких пункта: click delay при выключенном
double-click action (RED2 теста/3 assertions → GREEN2, затем integrated354) и
устаревшие Lua runtime ожидания. Extension gate теперь проверяет реальный
install/remove и ENOTSUP для activation/trigger; media harness получает собственный
Lua fixture/уникальный marker вместо чужого `/tmp` файла. Два runner isolation
теста сначала упали, затем прошли. Корень независимо повторил extensions runtime
и все шесть link checks. Media output не запускался.

Последняя правка после354 — только текст двух подсказок audio tracks. Она не
меняет поведение и отдельно проверена сборкой `MXRUI`
(`integrated-ui-copy-build-isolated.log`, exit0); полный тестовый прогон
после текстовой правки не повторялся.

## Удалённый мёртвый код

Удалены только декларации с проверенными reference searches: пустой `MXRUI.swift`
(`MXRUIInfo`), `ChaptersModel.hasChapters`, `ChaptersModel.previousChapter`,
`TracksModel.nudgeAudioDelay`, `TrackDefaults.preferredTrack`,
`MockPlayer.configureTracks` — шесть деклараций в пяти файлах. Новые references
плеера к `currentPosition` обнаружены до удаления, этот символ сохранён.
Неиспользуемые Figma tokens/assets не удалялись автоматически: это также
словарь референса и будущих состояний. Старые `build/` и чужие worktree не чистились.

## Что остаётся до приёмки

1. Пересобрать через `tools/install-app.sh`, проверить provenance/signature/cache
   нового app, затем сценарии профилей, modal drafts, searched/sorted/duplicate
   playlist removal на одноразовых данных. Выполнять с app.lock и HID idle.
2. Настоящее окно против Figma: S01, narrow/long names, popup anchoring, все13
   Settings категорий, light material, onboarding, fullscreen/subtitles и PiP.
   Нельзя закрыть этот пункт screenshot галереи.
3. Повторить CPU visible/hidden/PiP, scrub, startup и shutdown, RSS/длительный
   playback. Не переносить прежние26–28% на новую ветку и не обещать11% без замера.
4. Реальные conversion round trips и streaming receiver/local display/keep между
   двумя item. Subtitle attachment с local/remote rules на новом media identity.
5. Raw AX + VoiceOver + Full Keyboard Access + Reduce Motion/Increase Contrast на
   реальном окне. Device discovery проверить на аппаратуре; callbacks/моки это
   не доказывают.
6. Отдельные задачи: processed paused still без engine regression; Lua dialog
   provider; external audio-track editing; OpenSubtitles; начальная стоимость
   больших fallback/Home queries; разбиение больших bridge/catalog файлов.

Это журнал реализованных изменений и доказательств, а не заявление о закрытии
всех106 audit IDs или готовности к релизу. Одинаковые дефекты двух аудиторов
сопоставлены, но не посчитаны дважды как независимые улучшения.

## PERF-01 / NAT-04 CPU measurement (final wave, B-controls, 2026-10-16)
Installed app built from the working tree, 1728×1001 window, 1920×1080 H.264 test media,
`top -s 1` means over 8–15 samples (% of one core): playing with bars visible 7.2–7.5;
Hide UI 5.9; app hidden 6.0; window minimized 5.6; active scrub with preview 28.2; paused 1.6.
Bars visible cost ≤ 1.6 pp over Hide UI (target ≤ 2 pp). The seek layers stop their display link
when the window is occluded, the app is hidden, the bars are hidden or Reduce Motion is on (D047).
