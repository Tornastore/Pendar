# Pendar — معماری ماژولار

## ساختار پوشه‌ها

```text
Pendar/
├── main.gd                       # پوسته برنامه، ناوبری و هماهنگی شبکه
├── main.tscn
├── core/
│   ├── game_module.gd            # قرارداد مشترک موتور بازی
│   ├── game_catalog.gd           # فهرست واحد بازی‌ها
│   └── ui_content.gd             # راهنمای بازی‌ها و پالت UI
├── ui/
│   ├── illustration_renderer.gd  # آیکون‌ها و تصویر کارت انتخاب بازی
│   ├── tabletop_art_renderer.gd  # کارت، تاس، مهره و قطعه شطرنج
│   ├── components/
│   │   └── dialog_component.gd   # layout، دکمه‌ها و ترسیم دیالوگ عمومی
│   └── screens/
│       ├── dashboard_screen.gd   # دکمه‌ها و ترسیم صفحه آمار
│       ├── rankings_screen.gd    # دکمه‌ها و ترسیم صفحه رتبه‌بندی
│       ├── mode_screen.gd        # انتخاب درجه سختی و روش بازی؛ بدون مالکیت state
│       ├── result_screen.gd      # صفحه نهایی و خلاصه نتیجه مسابقه
│       ├── pause_screen.gd       # ارائه رابط توقف بازی
│       └── rules_screen.gd       # محتوای راهنما، صفحه‌بندی و ترسیم
├── games/
│   ├── othello/rules.gd
│   ├── othello/presentation.gd  # ترسیم اتلو و تبدیل مختصات لمس به خانه
│   ├── pentago/rules.gd
│   ├── pentago/presentation.gd # board rendering, cell mapping and quadrant controls
│   ├── quoridor/rules.gd
│   ├── quoridor/presentation.gd # board, wall geometry, input-to-edge mapping and HUD
│   ├── domino/rules.gd
│   ├── domino/presentation.gd  # ترسیم زنجیره دومینو، دست و نگاشت کلیک
│   ├── chess/rules.gd
│   ├── chess/presentation.gd  # ترسیم شطرنج و تبدیل کلیک به خانه
│   ├── pasoor/rules.gd
│   ├── pasoor/presentation.gd  # کارت‌های دست/میز، چیدمان و نگاشت لمس
│   ├── mastermind/rules.gd
│   ├── gobblet/rules.gd
│   ├── gobblet/presentation.gd # صفحه، پشته‌ها و ذخیره مهره‌ها
│   ├── hokm/rules.gd
│   ├── hokm/presentation.gd    # چیدمان دست و کارت‌های روی زمین
│   ├── backgammon/rules.gd
│   ├── abalone/rules.gd
│   └── blockace/rules.gd
├── services/
│   ├── online_client.gd         # انتقال WebSocket و JSON؛ بدون منطق بازی
│   ├── scoring_service.gd       # ثبت نتیجه، امتیاز و ذخیره‌سازی
│   └── ranking_service.gd       # رتبه‌بندی و سطح رتبه
└── tools/verify_structure.py
```

## مرزبندی مسئولیت‌ها

- **موتور بازی‌ها:** state و توابع اصلی قوانین، ورودی، ترسیم و رفتار CPU در پوشه همان بازی قرار دارند. اتلو ۸×۸ و ۱۲×۱۲ از موتور مشترک اتلو با اندازه صفحه متفاوت استفاده می‌کنند.
- **برنامه اصلی:** `main.gd` مسئول هماهنگی صفحه‌ها، ناوبری و رویدادهای مسابقه باقی می‌ماند. راهنماها و paletteهای ثابت در `core/ui_content.gd` نگهداری می‌شوند. توابع قبلی رسم آیکون و تصویر کارت، و رسم مشترک مهره‌ها/کارت‌ها/تاس‌ها، به rendererهای پوشه `ui/` منتقل شده‌اند. متدهای واسط هم‌نام در `main.gd` حفظ شده‌اند تا ماژول‌های بازی بدون تغییر قرارداد بتوانند آن‌ها را صدا بزنند.
- **انتقال آنلاین:** `services/online_client.gd` مالک `WebSocketPeer` است و فقط اتصال، polling، خواندن بسته و JSON، ارسال پیام و بستن سوکت را انجام می‌دهد. صف مسابقه، وضعیت بازی، اعتبارسنجی پیام‌های بازی، RPCها و تغییر صفحه همچنان در `main.gd` می‌مانند؛ در نتیجه سرویس انتقال به قوانین بازی وابسته نیست.
- **RPC و شبکه LAN:** متدهای RPC در Node اصلی باقی می‌مانند تا ثبت و اجرای RPCهای Godot در نقطه ثابت بماند؛ منطق حرکت به موتور بازی مربوطه واگذار می‌شود.
- **فهرست بازی‌ها:** `core/game_catalog.gd` منبع واحد اطلاعات نمایش بازی‌هاست؛ برای تغییر نام یا دسته، از تعریف تکراری در UI استفاده نکنید.
- **امتیازدهی:** `services/scoring_service.gd` مستقل از قوانین بازی است و نتیجه هر بازی را با شناسه خودش ثبت می‌کند. تاریخچه هر بازی جداست و امتیاز کلی بازیکن نیز جداگانه نگهداری می‌شود.
- **رتبه‌بندی:** `services/ranking_service.gd` صرفاً ردیف‌های رتبه‌بندی بازی‌ها را مرتب می‌کند و منطق سطح رتبه کلی را تعیین می‌کند؛ ثبت امتیاز در این سرویس انجام نمی‌شود.
- **رندر مشترک:** `ui/illustration_renderer.gd` و `ui/tabletop_art_renderer.gd` از همان CanvasItem اصلی برای ترسیم استفاده می‌کنند؛ بنابراین ترتیب لایه‌ها و مختصات فعلی حفظ می‌شود. `main.gd` فقط wrapperهای سازگاری را نگه می‌دارد.
- **صفحه‌های رابط کاربری:** `ui/screens/dashboard_screen.gd` و `ui/screens/rankings_screen.gd` ساخت دکمه‌ها و ترسیم صفحه‌های آمار و رتبه‌بندی را در اختیار دارند. `ui/screens/mode_screen.gd` کنترل‌ها و ترسیم انتخاب درجه سختی/روش بازی را فراهم می‌کند؛ تغییر سختی، شروع بازی و ناوبری همچنان callbackهای کنترلر اصلی‌اند. `ui/screens/result_screen.gd` صفحه نهایی و خلاصه نتیجه را رسم می‌کند. `ui/screens/pause_screen.gd` رابط مکث را ارائه می‌کند و `ui/screens/rules_screen.gd` محتوای راهنما، صفحه‌بندی، چیدمان و ترسیم را مدیریت می‌کند. رنگ‌ها و ابعاد پایه از طریق `_ui_screen_theme` صریح تزریق می‌شوند.
- **دیالوگ عمومی:** `ui/components/dialog_component.gd` فقط چیدمان، ساخت دکمه‌ها و ترسیم دیالوگ‌های تأیید را انجام می‌دهد. اجرای callback، بستن پنجره و تغییر `dialog`/`pause_open`/`rules_open` در `main.gd` باقی می‌ماند؛ presenterها state مسابقه یا باز/بسته بودن overlay را مالک نمی‌شوند.
- **نتیجه مسابقه:** `ui/screens/result_screen.gd` ساخت دکمه‌ها، ترسیم صفحه نهایی و پنجره خلاصه نتیجه را ارائه می‌کند. جمع‌بندی داده‌های نتیجه، ثبت امتیاز، تغییر وضعیت مسابقه و callbackهای دکمه‌ها همچنان در `main.gd` و `ScoringService` باقی می‌مانند.

## سازگاری ذخیره‌سازی

امتیازها در `user://pendar_scores.cfg` ذخیره می‌شوند. در اولین اجرا اگر فایل قدیمی `user://mind_bastion_scores.cfg` موجود باشد، خوانده و به مسیر جدید منتقل می‌شود؛ بنابراین تغییر نام برند نباید امتیازهای ذخیره‌شده را پاک کند.

## اضافه کردن بازی جدید

1. یک پوشه جدید در `games/<game_id>/` بسازید و `rules.gd`, `game.json` و `README.md` مخصوص بازی را اضافه کنید.
2. موتور باید از `core/game_module.gd` ارث‌بری کند و state و قوانین خودش را نگه دارد.
3. اسکریپت موتور را به `GAME_MODULE_SCRIPTS` در `main.gd` اضافه کنید.
4. فراداده بازی را به `core/game_catalog.gd` اضافه کنید.
5. فقط در صورت نیاز به RPC، handlerهای شبکه را در `main.gd` نگه دارید و از آن‌ها برای فراخوانی موتور بازی استفاده کنید.
6. نتیجه باید از `ScoringService` ثبت شود؛ امتیازدهی جدید را در فایل قوانین بازی پیاده‌سازی نکنید.

## بررسی ساختار

از ریشه پروژه اجرا کنید:

```bash
python tools/verify_structure.py
```

این بررسی فایل‌های ماژول‌ها، propertyهای واسط، قراردادها و جداسازی سرویس‌ها را کنترل می‌کند. این آزمون ایستا جای اجرای پروژه در Godot 4.3+ و تست عملی حرکت‌ها، ترسیم و شبکه را نمی‌گیرد.


## هوش مصنوعی با سطح سختی مستقل

هوش CPU می‌تواند در پوشهٔ هر بازی مستقل باشد؛ برای کوریدور، سیاست انتخاب حرکت و دیوار در `games/quoridor/ai.gd` از موتور قوانین `rules.gd` جدا شده است. متغیر `quo_difficulty` سطح ۱ تا ۵ را نگه می‌دارد و از صفحهٔ انتخاب حالت بازی قابل تنظیم است. سطح‌ها از حرکت کوتاه‌مسیر ساده تا ارزیابی تاکتیکی مسیر هر دو بازیکن، هزینهٔ منابع و فوریت دفاع متفاوت‌اند. این الگو برای اضافه‌کردن سطح‌بندی به بازی‌های دیگر قابل استفاده است.

## هوش مصنوعی بازی‌ها

- `games/quoridor/ai.gd`: شش سطح دشواری و جست‌وجوی مبتنی بر مسیر و دیوار.
- `games/othello/ai.gd`: شش سطح برای اتلو ۸×۸ و ۱۲×۱۲.
- `games/chess/ai.gd`: ارزش‌گذاری مهره/موقعیت و جست‌وجوی آلفا–بتا با بودجهٔ محدود.
- `games/backgammon/ai.gd`: برنامه‌ریزی توالی تاس نوبت، سنجش پیشروی، بیرون‌بردن، زدن مهره و ریسک تک‌مهره‌ها.

هوش شطرنج و تخته‌نرد از قوانین فعلی پروژه استفاده می‌کند؛ این موتورها هنوز جایگزین پیاده‌سازی کامل قوانین رسمی این دو بازی نیستند.

## صفحه‌های رابط جداشده (مرحله دوم بازآرایی)

- `ui/screens/dashboard_screen.gd` مالک ساخت دکمه‌ها و ترسیم صفحه آمار است؛ امتیازها را از `ScoringService` می‌خواند و state صفحه/اسکرول را از کنترلر اصلی دریافت می‌کند.
- `ui/screens/rankings_screen.gd` مالک ساخت دکمه‌ها و ترسیم صفحه رتبه‌بندی است؛ داده ردیف‌ها و محاسبه سطح لیگ را از `RankingService` می‌گیرد.
- `main.gd` entry pointهای قبلی `_btns_dashboard`, `_draw_dashboard`, `_btns_rankings` و `_draw_rankings` را به‌عنوان wrapper نگه می‌دارد تا dispatch صفحه‌ها تغییر نکند.
- این screen presenterها قوانین بازی، ذخیره‌سازی امتیاز یا وضعیت مسابقه را مالک نمی‌شوند. ابعاد و رنگ‌های مشترک از طریق `_ui_screen_theme` به‌صورت صریح تزریق می‌شود.
- `tools/verify_structure.py` وجود این ماژول‌ها، entry point و delegation را به‌صورت ایستا بررسی می‌کند؛ تأیید رندر واقعی همچنان به اجرای Godot نیاز دارد.

## پنجره‌های رابط جداشده (مرحله سوم بازآرایی)

- `ui/screens/pause_screen.gd` مسئول چیدمان، ساخت دکمه‌ها و ترسیم پنجره توقف است؛ callbackها همچنان به متدهای کنترلر اصلی ارجاع می‌دهند.
- `ui/screens/rules_screen.gd` محتوای راهنمای اتصال و صفحات راهنمای عمومی/اختصاصی، صفحه‌بندی، چیدمان، دکمه‌های قبلی/بعدی و ترسیم را در اختیار دارد. باز/بسته‌شدن راهنما و تغییر صفحه در `main.gd` حفظ شده است.
- `ui/components/dialog_component.gd` رندر عمومی دیالوگ را انجام می‌دهد؛ اجرای عملیات تأیید، callback و cleanup state در `main.gd` باقی مانده است.
- wrapperهای قدیمی برای دیالوگ، مکث و راهنما حفظ شده‌اند تا dispatcher فعلی و callbackهای دکمه‌ها نیاز به تغییر نداشته باشند.
- `tests/test_ui_overlays.py` و `tools/verify_structure.py` جداسازی presentation و حفظ مرز state را به‌صورت ایستا کنترل می‌کنند. برای تأیید کامل، اجرای پروژه در Godot و بازکردن عملی هر overlay همچنان لازم است.

## جداسازی صفحه نتیجه (مرحله چهارم بازآرایی)

- `ui/screens/result_screen.gd` ترسیم صفحه نهایی بازی، پنجره خلاصه نتیجه و چیدمان دکمه‌های پایان مسابقه را بر عهده دارد. ورودی‌های نتیجه را از `_result_info()` می‌خواند.
- محاسبه عنوان/ردیف‌های نتیجه، تشخیص برنده، ثبت نتیجه و تغییر وضعیت مسابقه عمداً در `main.gd` باقی مانده‌اند؛ presenter فقط داده را می‌خواند و فرمان دکمه‌ها را به کنترلر بازمی‌گرداند.
- `_btns_result`, `_draw_result` و `_draw_result_popup` به عنوان wrapper حفظ شده‌اند تا dispatch اصلی و مسیر پنجره نتیجه تغییر نکند.

## صفحه انتخاب حالت بازی (مرحله پنجم بازآرایی)

`ui/screens/mode_screen.gd` ساخت دکمه‌های انتخاب سختی/تعداد بازیکنان و ترسیم کارت معرفی بازی را به عهده دارد. این Presenter فقط وضعیت فعلی را از `main.gd` می‌خواند؛ تغییر سختی، آغاز مسابقه، اتصال LAN/Online و ناوبری از طریق callbackهای قدیمی در کنترلر انجام می‌شود. `main.gd` توابع `_btns_mode` و `_draw_mode` را به عنوان wrapper نگه می‌دارد تا dispatcher اصلی تغییر نکند.


## Online and LAN lobby presentation

The online matchmaking and LAN lobby views are delegated to `ui/screens/online_screen.gd`. This presenter builds the existing buttons and draws the online/lobby screens, while callbacks, connection status, seat assignment, WebSocket transport and application transitions remain in `main.gd` / `services/online_client.gd`. The presenter must not create sockets or mutate matchmaking state.


## صفحه فهرست بازی‌ها (مرحله هفتم بازآرایی)

- `ui/screens/menu_screen.gd` فهرست‌کردن بازی‌های متناسب با فیلتر، محاسبه جای کارت‌ها، ساخت دکمه‌ها، ترسیم صفحه انتخاب بازی و کارت‌های بازی را بر عهده دارد.
- مالکیت `menu_filter`، تغییر فیلتر، انتخاب بازی، فعال/غیرفعال‌سازی موسیقی، خروج از برنامه و ناوبری در `main.gd` باقی مانده است؛ presenter فقط callbackهای قبلی را به دکمه‌ها وصل می‌کند.
- `main.gd` توابع `_menu_games`, `_tile_rect`, `_btns_menu`, `_draw_menu` و `_draw_game_tile` را به عنوان wrapper سازگاری نگه می‌دارد.
- `tests/test_ui_menu_screen.py` و `tools/verify_structure.py` وجود ماژول، delegation و عدم مالکیت state توسط presenter را به‌صورت ایستا کنترل می‌کنند. تأیید نهایی به اجرای واقعی Godot و بررسی اسکرول/فیلتر/انتخاب بازی نیاز دارد.

## جداسازی نمایش و ورودی بازی‌ها (مرحله هشتم، پایلوت اتلو)

- `games/othello/rules.gd` مالک state معتبر صفحه، نوبت، حرکت مجاز، گرفتن مهره‌ها، محاسبه امتیاز و پایان مسابقه است.
- `games/othello/presentation.gd` صرفاً اندازه/مبدأ صفحه، تشخیص نوبت برای نمایش، تبدیل مختصات صفحه به مختصات خانه و ترسیم صفحه را انجام می‌دهد. لمس معتبر همچنان به `rules.gd` از طریق `_othello_place()` تحویل داده می‌شود؛ presenter مستقیماً board یا نوبت را تغییر نمی‌دهد.
- متدهای `_oth_cell`, `_oth_origin`, `_oth_my_turn`, `_othello_tap` و `_draw_othello` در rules module به عنوان wrapper حفظ شده‌اند؛ در نتیجه `main.gd` و مسیر dispatch ورودی/ترسیم فعلی تغییر نکرده‌اند.
- این مرحله یک الگوی پایلوت برای بازی‌های دیگر است، نه مهاجرت یک‌باره همه ۱۴ بازی. پس از اجرای عملی اتلو در حالت‌های ۸×۸ و ۱۲×۱۲ می‌توان همین جداسازی را به بازی بعدی تعمیم داد.
- `tests/test_game_presentations.py` و `tools/verify_structure.py` قرارداد جداسازی را ایستا کنترل می‌کنند. این تست‌ها جای اجرای واقعی Godot و آزمون لمس/ترسیم را نمی‌گیرند.


## جداسازی نمایش و ورودی بازی‌ها (مرحله هشتم، پایلوت شطرنج)

- `games/chess/rules.gd` مالک صفحه شطرنج، انتخاب مهره، حرکت‌های مجاز، جابه‌جایی، تشخیص وضعیت شاه و پایان بازی است. این مرحله قوانین موجود را تغییر نمی‌دهد.
- `games/chess/presentation.gd` ترسیم صفحه و مهره‌ها، برجسته‌سازی خانه‌ها، شمارش مهره‌های گرفته‌شده، تبدیل مختصات صفحه به خانه و جهت‌دهی دید بازیکن را انجام می‌دهد. رسم همچنان از طریق APIهای `app` انجام می‌شود.
- متدهای `_chess_flip`, `_chess_scr`, `_chess_center`, `_chess_tap` و `_draw_chess` در rules module به عنوان wrapper/مرز سازگاری باقی می‌مانند؛ در نتیجه dispatcher اصلی و RPC `_rpc_chess_move` تغییر نکرده‌اند.
- کلیک فقط به مختصات خانه تبدیل می‌شود؛ انتخاب مهره، اعتبارسنجی حرکت، ارسال حرکت آنلاین و اعمال حرکت آفلاین در rules module می‌مانند.
- `tests/test_game_presentations.py` و `tools/verify_structure.py` مرزبندی را ایستا کنترل می‌کنند؛ این بررسی‌ها جای اجرای واقعی Godot از دو جهت صفحه را نمی‌گیرند.


## Chess rules, history and AI hardening

- `games/chess/rules.gd` is the authoritative FIDE-style rules/state module; `games/chess/presentation.gd` remains responsible for rendering and screen-to-square mapping.
- Legal moves are filtered by simulating each candidate and rejecting moves that leave the mover's king attacked. King capture is never a move; checkmate/stalemate are terminal states.
- Castling rights, en-passant availability, promotion choice, half/fullmove counters, position repetition history and notation are included in move snapshots so local Undo can restore the prior position.
- Local Undo rewinds one ply in hot-seat play and a human/CPU pair in CPU mode; it is disabled in network play to avoid client-state divergence.
- `games/chess/ai.gd` uses legal move generation, alpha-beta, iterative deepening, time/node budgets, repetition-aware transposition keys and quiescence search. Promotion variants are searched independently.
- Both Web workflows run `tests/godot/test_chess_rules.gd` under headless Godot, including perft, king safety, castling, en-passant, promotion, Undo and tactical AI checks.


## جداسازی نمایش دومینو و سخت‌گیری کنش‌ها (مرحله نهم)

- `games/domino/presentation.gd` مسئول محاسبه جای مهره‌های دست، تبدیل کلیک به انتخاب مهره، ساخت دکمه‌های ابتدا/انتها/برداشت/پاس و ترسیم دست و زنجیره روی میز است.
- `games/domino/rules.gd` مالک وضعیت قطعی دست‌ها، زنجیره، سرهای زنجیر، نوبت، امتیاز و پایان بازی باقی می‌ماند. wrapperهای `_dom_hand_rects`, `_dom_tap`, `_btns_domino` و `_draw_domino` برای حفظ مسیر dispatch موجود نگه داشته شده‌اند.
- حرکت مهره ورودی بازیکن، اندیس دست، سر انتخابی، نوبت و وضعیت پایان را پیش از تغییر وضعیت اعتبارسنجی می‌کند. برداشت فقط هنگامی مجاز است که بازیکن فعال حرکت قابل اجرا نداشته باشد؛ پاس نیز فقط با خالی بودن انبار و نبود حرکت قانونی پذیرفته می‌شود.
- `tests/godot/test_domino_rules.gd` موارد شروع دست، یکتایی ۲۸ مهره، جهت‌دهی مهره روی دو سر زنجیر، رد کنش‌های نامعتبر، برداشت و پاس، و پایان دست مسدودشده را در Godot headless بررسی می‌کند. هر دو workflow وب این آزمون را اجرا می‌کنند.


## UNO presentation and action-rule hardening (next stage)

- `games/uno/presentation.gd` owns table/card rendering and card/action button layout. Existing main-module entry points `_draw_uno`, `_btns_uno`, `_uno_draw_card_visual` and `_uno_board_tap` remain as compatibility wrappers.
- `games/uno/rules.gd` remains the authoritative owner of hands, piles, turn order, color, challenge target, penalties, scoring and round completion. The presenter may update only UI paging (`uno_hand_page`) and must send card choices to the existing action methods.
- Wild Draw Four can be selected as a bluff so that the challenge mechanic is reachable; its legality is evaluated separately against the player's pre-play hand and recorded in `uno_last_wild4_illegal`. An illegal +4 challenge must penalize the actor; a failed challenge must give the challenger six cards.
- Drawing twice in one turn is rejected by the rules layer. After drawing a playable card, the UI offers only that card (or pass) and moves the hand page to show the drawn card.
- `tests/godot/test_uno_rules.gd` covers deck/deal conservation, Wild Draw Four challenge outcomes, draw-once behavior, and two-player Reverse/Skip semantics. Both Web workflows run it with headless Godot.


## جداسازی نمایش فکر بکر (Mastermind)

- `games/mastermind/rules.gd` مالک کد مخفی، حدس‌ها، بازخورد، فاز بازی، محاسبه CPU، مسابقه‌های CPU/LAN/آنلاین و تغییر وضعیت‌های معتبر است.
- `games/mastermind/presentation.gd` مسئول چیدمان سوراخ‌های کد، دکمه‌های ورودی، رسم ردیف‌های حدس، نشان‌های سیاه/سفید و نوار پیشرفت عمومی مسابقه است.
- توابع `_btns_mastermind`, `_draw_mastermind`, `_draw_mm_online_sidebar`, `_mm_slot_pos` و `_mm_color_pos` در rules به‌عنوان wrapper حفظ شده‌اند تا dispatcher موجود تغییر نکند.
- Presenter کد مخفی را نمی‌خواند و متغیرهای وضعیت بازی را تغییر نمی‌دهد؛ دکمه‌ها فقط callbackهای معتبر rules را فراخوانی می‌کنند.
- `tests/test_mastermind_presentation.py` مرز معماری و حفظ حریم کد مخفی را ایستا بررسی می‌کند؛ برای تأیید رندر و اجرا باید پروژه در Godot اجرا شود.


## جداسازی نمایش بلاک‌آس (مرحله دهم)

- `games/blockace/presentation.gd` ترسیم صفحه ۱۴×۱۴، نمایش ۲۱ قطعه هر بازیکن، کنترل‌های چرخش/وارونگی/قراردهی و تبدیل مختصات صفحه به خانه را انجام می‌دهد.
- `games/blockace/rules.gd` همچنان مرجع قطعی اعتبار قرار دادن قطعه، تماس گوشه‌ای، امتیاز، پایان بازی، CPU و اعمال حرکت آنلاین است؛ presenter فقط خانه انتخاب‌شده را به `_blk_handle_target()` تحویل می‌دهد.
- `_blk_tap`, `_btns_blockace`, `_draw_blk_cell` و `_draw_blockace` به‌عنوان wrapper حفظ شده‌اند تا dispatch موجود در `main.gd` تغییر نکند.
- `tests/test_blockace_presentation.py` و `tools/verify_structure.py` مرز نمایش/قواعد و سازگاری callbackها را ایستا کنترل می‌کنند؛ برای آزمون نهایی تعامل و چیدمان باید پروژه در Godot اجرا شود.

## جداسازی نمایش پنتاگو

- `games/pentago/presentation.gd` محاسبهٔ مختصات صفحه/خانه‌ها، تبدیل لمس به خانه، ساخت دکمه‌های چرخش چهار ربع و ترسیم صفحه را انجام می‌دهد.
- `games/pentago/rules.gd` مرجع قطعی وضعیت صفحه، فاز جای‌گذاری/چرخش، نوبت، بررسی پنج‌تایی، چرخش ربع، تصمیم CPU و ارسال کنش شبکه باقی می‌ماند.
- توابع `_pent_origin`, `_pent_cell_pos`, `_pent_tap`, `_pent_quad_rect`, `_btns_pentago` و `_draw_pentago` به‌عنوان wrapper حفظ شده‌اند؛ مسیر dispatch و RPCهای موجود در `main.gd` تغییر نکرده‌اند.
- ورودی صفحه ابتدا فقط به خانهٔ منطقی تبدیل می‌شود و سپس به `_pent_handle_cell_tap()` تحویل داده می‌شود؛ قواعد امکان حرکت و ارسال شبکه را خود ماژول قواعد تعیین می‌کند.
- `tests/test_pentago_presentation.py` مرزبندی ایستا را بررسی می‌کند و هر دو workflow وب آزمون‌های قواعد پنتاگو را با Godot headless اجرا می‌کنند.


## Remaining board/card game presentation boundaries

- `games/pentago/presentation.gd` owns the Pentago board geometry, tap-to-cell mapping and quadrant controls; placement, rotation, turn changes, win detection and CPU planning remain in `rules.gd`.
- `games/quoridor/presentation.gd` owns board/wall visuals, wall-edge hit mapping, player HUD and mode controls. Wall legality, path reachability, turn transitions, CPU search and RPC application remain in `rules.gd` / `ai.gd`.
- `games/gobblet/presentation.gd` owns the 4×4 board, stack visuals, reserve-piece layout and tap-to-cell mapping. Stack legality, reveal-loss rule, legal moves, CPU search and network actions remain in `rules.gd`.
- `games/pasoor/presentation.gd` owns card/table layout, selected-card highlight and confirmation button construction. Capture enumeration, card scoring, sweep scoring, AI decisions, turn changes and network actions remain in `rules.gd`.
- `games/hokm/presentation.gd` owns hand/card/table rendering and maps pointer hits to a hand index. Follow-suit validation, trick resolution, score, CPU decisions and network play remain in `rules.gd`.
- `games/abalone/presentation.gd` owns hex-cell geometry, pointer-to-cell mapping and board rendering. Selection groups, legal move generation, Sumito/push validation, CPU search and network actions remain in `rules.gd`.
- `games/quarto/presentation.gd` owns board/piece-palette layout, pointer-to-cell mapping, selection buttons and game rendering. Piece choice, legal placement, Quarto detection, terminal state, CPU planning and RPC validation remain in `rules.gd` / `ai.gd`.
- The controller-facing entry points remain compatibility wrappers, so `main.gd` keeps the same dispatch contract. The presenters read game state and dispatch actions to the rules module; they do not directly mutate authoritative game state.
- `tests/test_other_game_presentations.py`, `tests/test_quarto_presentation.py`, `tools/verify_structure.py`, and the headless Quarto regression suite validate the new boundaries. Static tests do not replace a full Godot 4.3 runtime and UI play-through.


## Runtime regression coverage for remaining rule engines

`tests/godot/test_remaining_game_rules.gd` runs under Godot 4.3 in both Web build and deploy workflows. It covers Othello opening/capture and score transitions; Quoridor legal pawn moves, wall geometry, and path preservation; Gobblet size/stack rules and four-in-a-row completion; Hokm follow-suit and trick scoring; Pasoor sum-to-eleven capture selection; Abalone board geometry and legal group movement; and Blockace inventory, required first placement, and piece consumption. The suite uses a small mock host and does not exercise rendering, network sessions, or full browser interaction; those remain separate integration checks.
