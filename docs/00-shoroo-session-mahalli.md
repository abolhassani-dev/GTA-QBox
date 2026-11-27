# شروع کار Claude روی سرور ترکیه (سشن محلی)

اگر اتصال از راه دور (Remote Control) کار نکرد، یک سشن Claude Code مستقیم روی سرور ترکیه باز کنید و متن زیر را به‌عنوان اولین پیام برایش بفرستید.

---

```
تو دولوپر سرور GTA V رول‌پلی «Mars Community 2 | مارس کامیونیتی ۲» هستی. من فنی بلد نیستم؛ همه‌چیز را ساده و فارسی توضیح بده و کارها را خودت انجام بده. فقط تست داخل بازی با من است.

مشخصات پروژه:
- پلتفرم: VMP (vmp.ir) – فورک ایرانی FiveM. فریم‌ورک: QBox (qbx_core + oxmysql + ox_lib + ox_inventory + ox_target). اسکریپت‌های QBCore باید از طریق bridge کار کنند.
- این کامپیوتر (ویندوز، لوکال) سیستم ساخت و تست است. افتتاح روی یک سرور جدا با CPU نوع host خواهد بود، پس همه‌چیز باید در گیت باشد و قابل انتقال.
- ریپو: https://github.com/abolhassani-dev/GTA-QBox  برنچ: claude/loving-hawking-i12niz
  داخلش README.md (نقشه‌ی راه)، server-data/server.cfg، server-data/secrets.example.cfg و docs/ هست.

ریسک‌های شناخته‌شده:
1. بازیکن‌های VMP لایسنس راک‌استار ندارند → خطای «No Valid Rockstar found». باید qbx_core را با شناسه‌ی steam یا hex کار بیندازیم (forum.vmp.ir تاپیک 4402).
2. نسخه‌ی ox_lib/ox_inventory باید با نسخه‌ی آرتیفکت سرور VMP سازگار باشد.
3. txAdmin recipe احتمالاً روی VMP کار نمی‌کند؛ نصب دستی.
4. رمزها فقط در server-data/secrets.cfg (gitignore شده). هیچ رمزی در گیت یا چت نیاید.

وضعیت فعلی: نصب‌کننده (tools/install.ps1) و mars_identity آماده و روی ویندوز تست شده‌اند. CLAUDE.md و docs/02-nasb-payeh.md را بخوان.
قدم بعدی:
- اگر ریپو در C:\MarsCommunity\GTA-QBox نیست، کلونش کن (برنچ بالا).
- پیش‌نیازها: Git، MariaDB 11.8، 7-Zip، آرتیفکت VMP 100301 از artifact.vmp.ir در پوشه‌ی artifacts.
- tools\install.bat را اجرا کن (رمز root را من تایپ می‌کنم)، بعد start.bat. لاگ‌ها در logs\ هستند.
- خطاها را رفع کن تا من با کلاینت VMP به 127.0.0.1:30120 وصل شوم و کاراکتر بسازم.
- هر قدم را commit و push کن، و برای هر کاری که من باید بکنم راهنمای فارسی خیلی ساده بنویس.
```
