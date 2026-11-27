# MDT پلیس (ps-mdt)

MDT رایگان Project Sloth – لایسنس **غیرتجاری (CC BY-NC-SA)**: اگر از سرور درآمد داشته باشید، اجازه‌ی استفاده ندارید.

## نصب (یک بار)

چهار بسته‌ی **آماده (Release)** لازم است. از صفحه‌ی Releases هر کدام، در بخش **Assets** آخرین نسخه، فایل **zip** را دانلود کنید که اسمش **Source code نیست**:

| بسته | صفحه | کار |
|---|---|---|
| ps-mdt | github.com/Project-Sloth/ps-mdt/releases | خود MDT |
| ps_lib | github.com/Project-Sloth/ps_lib/releases | کتابخانه‌ی لازم |
| ps-dispatch | github.com/Project-Sloth/ps-dispatch/releases | اعزام و گزارش‌های ۱۱۰ |
| PolyZone | github.com/mkafrin/PolyZone/releases | فایل **PolyZone.zip** |

1. پوشه‌ی `server-data\resources\[police]` را بسازید (با کروشه).
2. هر zip را داخل آن Extract کنید. اسم پوشه‌ها باید **دقیقاً** این‌ها باشد:
   `ps-mdt`، `ps_lib`، `ps-dispatch`، `PolyZone`
   (اگر پوشه اسم نسخه داشت، مثلاً `ps-mdt-3.1.4`، تغییر اسم بدهید)
3. داخل هر پوشه باید **مستقیم** فایل `fxmanifest.lua` باشد (نه داخل یک پوشه‌ی دیگر).
4. چک کنید: `ps-mdt\web\dist\index.html` وجود دارد (یعنی نسخه‌ی آماده است).
5. `update.bat` ← سپس `tools\install-offline.bat` (برای ساخت جدول‌های دیتابیس MDT؛ رمز MariaDB را می‌خواهد) ← `start.bat`

## استفاده
- فقط شغل‌های پلیس (`police`، `bcso`، `sasp`) دسترسی دارند
- باز کردن: کلید **F11** یا دستور `/mdt`
- `/impound` توقیف ماشین، `/complaint` شکایت از افسر
