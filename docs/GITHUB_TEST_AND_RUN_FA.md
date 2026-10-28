# راهنمای تست و اجرای پندار روی GitHub

این راهنما برای مخزن `Tornastore/Pendar` نوشته شده است. آزمون‌های GitHub Actions کد و خروجی قابل‌ساخت را بررسی می‌کنند؛ خود محیط Actions رابط بازی را مثل یک بازیکن باز نمی‌کند. برای اجرای واقعی بازی وب، خروجی باید روی GitHub Pages منتشر شود.

## ۱. فایل‌های لازم را به مخزن بفرستید

1. فایل ZIP پروژه را روی رایانه استخراج کنید.
2. محتویات پوشه‌ی `Pendar` را در ریشه‌ی مخزن محلی خودتان قرار دهید؛ مراقب باشید پوشه‌ی تودرتوی `Pendar/Pendar` ساخته نشود.
3. فایل جدید `.github/workflows/test.yml` و راهنمای `docs/GITHUB_TEST_AND_RUN_FA.md` را هم در مخزن نگه دارید.
4. از Git Bash در ریشه‌ی پروژه اجرا کنید:

```bash
git status --short
git add .github/workflows/test.yml docs/GITHUB_TEST_AND_RUN_FA.md README.md
git commit -m "Add GitHub CI tests and run guide"
git push origin main
```

اگر تغییرات دیگری از نسخه‌ی ZIP را هم می‌فرستید، آن‌ها را نیز پیش از `git commit` بررسی و به `git add` اضافه کنید. قبل از ارسال، `git status --short` را نگاه کنید تا فایل‌های ناخواسته وارد Commit نشوند.

## ۲. اجرای خودکار آزمون‌ها روی GitHub

فایل `test.yml` سه بخش مستقل اجرا می‌کند:

- **Python:** اجرای `python -m pytest -q` و بررسی معماری با `python tools/verify_structure.py`.
- **سرور آنلاین:** نصب وابستگی Node.js با `npm install` و اجرای `npm test` داخل `online-server/`.
- **Godot:** واردکردن منابع، اجرای همه‌ی اسکریپت‌های آزمون داخل `tests/godot/` و آزمایش شروع بی‌واسطه‌ی پروژه با Godot 4.3.

این workflow با هر Push روی شاخه‌ها، هر Pull Request و همچنین با اجرای دستی فعال می‌شود.

برای اجرای دستی:

1. در GitHub صفحه‌ی مخزن `Tornastore/Pendar` را باز کنید.
2. وارد تب **Actions** شوید.
3. در فهرست سمت چپ **PENDAR CI - Tests** را انتخاب کنید.
4. روی **Run workflow** بزنید، شاخه‌ی مورد نظر را انتخاب کنید و اجرای workflow را شروع کنید.
5. وارد اجرای جدید شوید و هر سه job را بررسی کنید. سبز بودن هر سه یعنی آزمون‌های تعریف‌شده موفق بوده‌اند؛ روی هر job می‌توانید لاگ جزئی را ببینید.

اگر تب Actions غیرفعال بود، بررسی کنید GitHub Actions برای مخزن فعال باشد. برای این آزمون‌ها Secret یا Token اختصاصی لازم نیست.

## ۳. اجرای آزمون‌ها روی رایانه‌ی خودتان

دستورها را از ریشه‌ی پوشه‌ی پروژه اجرا کنید.

### آزمون‌های Python

```bash
python -m pip install --upgrade pytest
python -m pytest -q
python tools/verify_structure.py
```

### آزمون سرور آنلاین Node.js

Node.js نسخه‌ی 22 یا بالاتر لازم است:

```bash
cd online-server
npm install --no-audit --no-fund
npm test
cd ..
```

اگر `ws` پیدا نشد، ابتدا دستور `npm install` را در خود پوشه‌ی `online-server` اجرا کنید؛ وابستگی‌های نصب‌شده داخل ZIP قرار ندارند.

### آزمون‌های Godot

Godot 4.3 را نصب کنید و طبق `fonts/README_FA.md` فونت‌های `Vazirmatn-Regular.ttf` و `Vazirmatn-Bold.ttf` را داخل پوشه‌ی `fonts/` قرار دهید. سپس در Git Bash اجرا کنید:

```bash
godot --headless --editor --path . --import
for f in tests/godot/test_*.gd; do
  echo "Testing $f"
  godot --headless --path . --script "res://${f}" || exit 1
done
godot --headless --verbose --path . --quit-after 2
```

در PowerShell می‌توانید آزمون‌ها را با این دستور اجرا کنید:

```powershell
godot --headless --editor --path . --import
Get-ChildItem tests/godot/test_*.gd | ForEach-Object {
    $testPath = "res://tests/godot/$($_.Name)"
    Write-Host "Testing $testPath"
    godot --headless --path . --script $testPath
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

## ۴. اجرای واقعی بازی از روی GitHub Pages

Workflow انتشار وب در `.github/workflows/deploy-web.yml` تعریف شده است و روی Push به `main` یا اجرای دستی، منابع را وارد Godot می‌کند، آزمون‌های درون Workflow را اجرا می‌کند، خروجی وب را می‌سازد و سپس منتشر می‌کند.

### تنظیم اولیه‌ی Pages

1. به **Settings → Pages** در مخزن بروید.
2. در قسمت **Build and deployment**، گزینه‌ی **Source** را روی **GitHub Actions** بگذارید.
3. یک تغییر را به `main` Push کنید یا از **Actions → Deploy PENDAR to GitHub Pages → Run workflow** استفاده کنید.
4. در پایان اجرا، job انتشار باید سبز شود. آدرس سایت منتشرشده را از **Settings → Pages** باز کنید.

پس از Push، اول **PENDAR CI - Tests** را بررسی کنید. سبز شدن CI به‌تنهایی به معنی انتشار سایت نیست؛ اجرای **Deploy PENDAR to GitHub Pages** هم باید موفق شود.

### فقط ساخت خروجی وب، بدون انتشار

1. از **Actions**، workflow با نام **Build PENDAR Web App (artifact only)** را باز کنید.
2. روی **Run workflow** بزنید.
3. پس از موفقیت، در بخش **Artifacts** فایل `Pendar-Web` را دانلود کنید و از حالت فشرده خارج کنید.
4. برای تست محلی خروجی از پوشه‌ی خروجی اجرا کنید:

```bash
python -m http.server 8000
```

سپس `http://localhost:8000` را در مرورگر باز کنید. فایل `index.html` را مستقیم با `file://` باز نکنید.

### ساخت APK اندروید

از **Actions → Build PENDAR Android APK → Run workflow** استفاده کنید. اگر ساخت موفق باشد، APK به‌عنوان Artifact در همان اجرای workflow قابل دریافت است. APK خروجی را فقط روی دستگاهی نصب کنید که به آن اعتماد دارید.

## ۵. آنلاین، وای‌فای و محدودیت‌های تست

- اتصال مستقیم IP/وای‌فای از ENet/UDP برای خروجی‌های بومی مانند Android و Desktop است؛ GitHub Pages یا مرورگر نمی‌تواند اتصال UDP/ENet مستقیم را اجرا کند.
- بازی آنلاین نسخه‌ی وب به سرور WebSocket امن نیاز دارد. تنظیمات استقرار آن در `ONLINE_SERVER_FA.txt` و `online-server/README_FA.md` آمده است.
- پیش از فعال شدن matchmaking واقعی، برنامه‌ی سرور را مستقر کنید و `network/matchmaking_url` در `project.godot` را از مقدار نمونه به آدرس واقعی `wss://.../ws` تغییر دهید. برای Deploy سرور Liara، متغیر مخزن `LIARA_MATCHMAKER_APP` و Secret به نام `LIARA_API_TOKEN` مطابق راهنمای سرور تنظیم می‌شوند.
- آزمون‌های headless منطق و خطاهای بارگذاری را بررسی می‌کنند؛ جای آزمون دستی لمس، چیدمان واقعی موبایل، چند مرورگر و اتصال دو دستگاه در شبکه‌ی واقعی را نمی‌گیرند.
