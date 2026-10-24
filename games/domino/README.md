# دومینو

- شناسه ماژول: `domino`
- پیاده‌سازی قوانین و مالکیت state این بازی در `rules.gd` قرار دارد.
- رابط کاربری مشترک فعلاً از طریق adapter در برنامه اصلی به state دسترسی دارد؛ قوانین از کد رابط جدا شده‌اند.
- برای تغییر قوانین این بازی، در درجه اول همین ماژول را ویرایش کنید.

- هوش کامپیوتر دارای ۶ سطح سختی است: از انتخاب سادهٔ مهره تا حفظ انعطاف دست، کنترل سرهای زنجیر و ارزیابی حرکت ادامه در سطح استادتمام. انتخاب سطح در صفحهٔ حالت بازی انجام می‌شود.
- سطح انتخاب‌شده هنگام بازی با کامپیوتر در نشان «هوش CPU» دیده می‌شود تا مشخص باشد پروفایل فعال است.

## Presentation and authoritative action guards

- `presentation.gd` owns hand-fan rectangles, pointer hit-testing, button construction and table rendering. `rules.gd` preserves the existing dispatch methods as compatibility wrappers.
- `rules.gd` remains authoritative for turn order, legal tile placement, drawing, passing, scores and game completion.
- Tile play rejects invalid player indices, out-of-range hand indices, wrong-turn requests, completed games, mismatched endpoints and unknown end labels before indexing or mutating the hand.
- Drawing is allowed only on the active turn when no hand tile can be played; passing is allowed only when the boneyard is empty and the player has no legal play. These checks also protect RPC entry points from invalid actions.
- `tests/godot/test_domino_rules.gd` covers the standard double-six setup, endpoint orientation, invalid play rejection, draw/pass guards and blocked-game resolution.
