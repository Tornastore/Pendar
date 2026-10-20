اصلاح خطای ساخت وب MindBastion — فونت فارسی

علت خطا:
مرحلهٔ «Download embedded Persian fonts» از curl استفاده می‌کرد، اما تصویر Docker مربوط به barichello/godot-ci ابزار wget دارد و curl در آن موجود نیست. به همین دلیل مرحله با exit code 127 متوقف شد.

نحوهٔ اعمال:
1. این ZIP را باز کن.
2. پوشهٔ .github را در ریشهٔ مخزن خودت کپی کن و فایل‌های هم‌نام را جایگزین کن:
   .github/workflows/build-web.yml
   .github/workflows/deploy-web.yml
3. در Git Bash، از ریشهٔ مخزن اجرا کن:

   git add .github/workflows/build-web.yml .github/workflows/deploy-web.yml
   git commit -m "Fix font download command in web workflows"
   git push origin main

4. از GitHub Actions اجرای Build Web App را بررسی کن. بعد از سبز شدن آن، workflow انتشار را جداگانه اجرا کن.

این بسته فقط دو فایل workflow را اصلاح می‌کند؛ کد بازی و سایر فایل‌های پروژه را تغییر نمی‌دهد.
