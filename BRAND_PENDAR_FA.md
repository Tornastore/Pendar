# هویت برند پندار (PENDAR)

- نام نمایشی برنامه: `PENDAR | پندار`
- لوگوی رسمی: `branding/pendar_logo.png`
- نماد مستقل برای favicon و آیکون کوچک: `branding/pendar_emblem.png`
- آیکون Godot/PWA: `icon.png`؛ آیکون‌های Android در `icons/`
- عنوان تب مرورگر و favicon پس از خروجی گرفتن در workflow با `tools/brand_web_export.py` تنظیم می‌شوند.

## نکته‌های سازگاری

شناسه‌ی Android (`com.mindbastion.game`) عمداً ثابت مانده تا APK جدید بتواند نسخه‌ی نصب‌شده‌ی قبلی را به‌روزرسانی کند؛ تغییر شناسه باعث می‌شود Android برنامه را جداگانه بشناسد. فایل امتیاز محلی از `user://mind_bastion_scores.cfg` به `user://pendar_scores.cfg` مهاجرت می‌کند و آمار قبلی را نگه می‌دارد. این دو رشته فقط شناسه‌های سازگاری داخلی‌اند و به کاربر نمایش داده نمی‌شوند.

اگر می‌خواهید نام Repository گیت‌هاب نیز از `mind-bastion` به `pendar` تغییر کند، آن را جداگانه در GitHub Settings تغییر دهید؛ با این کار مسیر GitHub Pages هم تغییر می‌کند و URL نهایی باید بررسی شود.
