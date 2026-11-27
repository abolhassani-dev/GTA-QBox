# اسکریپت‌های سرور Mars Community 2

همه‌ی اسکریپت‌های زیر **رایگان و متن‌باز** هستند (بیشترشان از تیم رسمی QBox) و با `tools\install.bat` نصب می‌شوند.

## پایه (از قبل)
QBox (qbx_core)، ox_lib، ox_inventory (کیف)، ox_target (Alt)، oxmysql، ox_doorlock (درها)، ox_fuel (سوخت)، Renewed-Banking (بانک)، illenium-appearance (لباس و ظاهر)، qbx_garages (پارکینگ)، qbx_spawn، qbx_hud، qbx_adminmenu، pma-voice (صدا)، qbx_radio (بی‌سیم)، scully_emotemenu (حرکات)، bob74_ipl (فضاهای داخلی)، Renewed-Weathersync (آب‌وهوا)، loadscreen، vehiclehandler، qbx_vehicles، qbx_customs (تیونینگ)، qbx_drugs

## اختصاصی Mars
| اسکریپت | کار |
|---|---|
| `mars_identity` | شناسایی بازیکن در VMP + ادمین با Citizen ID |
| `mars_chat` | چت (T) و دستورهای `/ooc /me /do /f /w` |
| `mars_drugs` | سیستم کامل مواد (راهنما: `03-mars-drugs.md`) |
| `mars_jobs` | پنل ادمین شغل `/jobadmin` + ۶ شغل کاری: پیک پیتزا، پستچی GoPostal، برق‌کار، انگورچین، معدن‌چی، هیزم‌شکن |

## اضافه‌شده در این نسخه

### بازی و امکانات (`[qbx]`)
| اسکریپت | کار |
|---|---|
| `qbx_vehiclekeys` | کلید ماشین؛ قفل/باز کردن ماشین (L)، جستجوی کلید داخل ماشین (H)، دزدیدن ماشین |
| `qbx_vehicleshop` | نمایشگاه ماشین با خرید نقدی و **قسطی** |
| `qbx_cityhall` | شهرداری: کارت شناسایی، گواهینامه، انتخاب شغل‌های آزاد |
| `qbx_idcard` (+MugShotBase64) | کارت شناسایی و گواهینامه با عکس چهره‌ی کاراکتر |
| `qbx_radialmenu` | منوی دایره‌ای (Z): کارهای سریع، ماشین، شغل |
| `qbx_scoreboard` | لیست بازیکن‌ها و تعداد پلیس/آمبولانس آنلاین |
| `qbx_seatbelt` | کمربند ایمنی؛ بدون کمربند در تصادف از ماشین پرت می‌شوید |
| `qbx_carwash` | کارواش |
| `qbx_properties` | **خانه و آپارتمان**: خرید، ورود، انبار، دکوراسیون، پارکینگ خانه |
| `qbx_medical` | سیستم زخمی شدن، خون‌ریزی، زمین افتادن |
| `qbx_prison` | زندان |

### شغل‌ها (`[qbx-jobs]`)
| اسکریپت | کار |
|---|---|
| `qbx_policejob` | پلیس: دستبند، بازرسی، جریمه، ماشین و اسلحه‌خانه، زندان |
| `qbx_ambulancejob` | آمبولانس: درمان، احیا، بیمارستان |
| `qbx_mechanicjob` | مکانیک: تعمیر قطعه به قطعه، یدک‌کش |
| `qbx_taxijob` | تاکسی با تاکسی‌متر |
| `qbx_towjob` | یدک‌کش |
| `qbx_garbagejob` | رفتگر |
| `qbx_busjob` | راننده‌ی اتوبوس |
| `qbx_truckerjob` | راننده‌ی کامیون |
| `qbx_newsjob` | خبرنگار (دوربین و میکروفون) |
| `qbx_recyclejob` | بازیافت |

### خلاف (`[qbx-crime]`)
| اسکریپت | کار |
|---|---|
| `qbx_bankrobbery` | سرقت بانک (Fleeca، Paleto، Pacific) |
| `qbx_jewelery` | سرقت جواهرفروشی |
| `qbx_houserobbery` | دزدی از خانه‌ها |
| `qbx_pawnshop` | فروش اجناس دزدی |
| `qbx_scrapyard` | اوراق کردن ماشین دزدی |
| `qbx_streetraces` | مسابقه‌ی خیابانی با شرط‌بندی |

`qbx_storerobbery` (سرقت سوپرمارکت) هنوز توسط سازنده کامل نشده و اضافه نشد.

### گوشی (`[phone]`)
| اسکریپت | کار |
|---|---|
| `npwd` | گوشی کامل: تماس، پیام، مخاطبین، عکس، توییتر، مارکت، یادداشت، دارک‌چت |
| `qbx_npwd` | اتصال گوشی به QBox |
| `npwd_qbx_mail` | اپ ایمیل |
| `screencapture` | عکس گرفتن با دوربین گوشی |
