# تخته‌نرد

- شناسه ماژول: `backgammon`؛ بازی از وضعیت آزمایشی خارج شده است.
- شروع با دکمهٔ «ریختن تاس آغازین»؛ پس از انیمیشن چرخش، بازیکن دارای تاس بزرگ‌تر شروع می‌کند و هر دو مقدار را در نوبت اول مصرف می‌کند. نتیجه پیش از فشردن دکمه نمایش داده نمی‌شود.
- قوانین پیاده‌سازی‌شده شامل ۱۵ مهره برای هر بازیکن، حرکت اجباری از بار، زدن تک‌مهره و انتقال آن به بار، خانه‌های بسته، استفاده‌ی بیشینه از تاس‌ها، قانون تاس بزرگ‌تر در حالتی که فقط یک تاس قابل استفاده است، و خارج‌کردن مهره پس از ورود همه‌ی مهره‌ها به خانه‌ی خودی است.
- بازی با CPU از شش درجه‌ی سختی پشتیبانی می‌کند. درجه انتخابی در `bg_difficulty` ذخیره و مستقیماً به `BackgammonAI.choose_turn()` داده می‌شود.
- سطح ۱ انتخاب تصادفی از میان شاخه‌های قانونی با رعایت بیشینه‌ی تعداد تاس قابل استفاده دارد؛ سطح ۲ از امتیازدهی حریصانه با کمی تنوع استفاده می‌کند؛ سطح‌های ۳ تا ۶ پیشروی مهره‌ها، زدن مهره‌ی حریف، تک‌مهره‌های در معرض خطر، ساخت خانه‌های بسته، pip race و در سطوح قوی‌تر ساختن prime را بیشتر لحاظ می‌کنند.
- هوش مصنوعی باید همیشه بیشترین تعداد تاس قانونی را مصرف کند و قانون تاس بزرگ‌تر را رعایت کند؛ کیفیت موقعیت فقط بعد از رعایت این الزام‌ها ملاک انتخاب است.
- منطق قوانین در `rules.gd` و جست‌وجو/ارزیابی هوش در `ai.gd` نگهداری می‌شوند.


## Separation and regression coverage

- `rules.gd` remains the authoritative owner of checker state, dice consumption, legal-turn sequencing, bar entry, hits and bearing off.
- `presentation.gd` owns board rendering and pointer-to-point mapping. Seat 0 moves toward the bottom-right home board (point 24 appears top-right and point 1 bottom-right); top (`y=178..332`) and bottom (`y=508..662`) taps match the visible numbered points, and only the central bar channel maps to `-1`.
- Roll faces rotate and change during a timed roll animation for the human and CPU. Checker moves use an animated checker plus a persistent source-to-target trace; the latest move is also labelled with actor, source, destination and die.
- Legal single-die destinations are marked green and annotated with the available die. Purple overlays preview only valid two-step routes using the sum of both dice; the user must still perform each legal step separately. Doubles are explicitly labelled as four moves rather than one combined move.
- AI position evaluation discounts on-board hit threats while the relevant player still has checkers forced to enter from the bar, and rewards made points that block an opponent's bar entry. The rules engine still controls the legal move set and mandatory dice-use rule.
- `tests/godot/test_backgammon_rules.gd` covers initial checker counts, forced bar entry, blocked points, hits, bearing off, doubles, mandatory dice usage, screen hit-testing, end-turn guarding and AI state safety. It runs as part of both web build and deploy workflows.
