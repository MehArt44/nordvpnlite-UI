# راهنمای جامع NordVPN Lite UI برای OpenWrt 25

[![OpenWrt](https://img.shields.io/badge/OpenWrt-25.12%2B-blue)](https://openwrt.org/)
[![License](https://img.shields.io/badge/License-MIT-green)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/MehArt44/nordvpnlite-UI)](https://github.com/MehArt44/nordvpnlite-UI/releases)

**NordVPN Lite UI** یک رابط کاربری سبک، سریع و کاملاً واکنش‌گرا (Responsive) بر پایه LuCI برای مدیریت آسان NordVPN روی روترهای OpenWrt است. این پروژه با جاوااسکریپت خالص (بدون وابستگی به کتابخانه‌های سنگین خارجی) طراحی شده و از **OpenWrt 25.12+** با سیستم مدیریت بسته **apk** پشتیبانی می‌کند.

---

## 📋 فهرست مطالب

- [نصب سریع](#-نصب-سریع)
- [پیش‌نیازها](#-پیش‌نیازها)
- [ویژگی‌های کلیدی داشبورد](#-ویژگی‌های-کلیدی-داشبورد)
  - [۱. وضعیت اتصال و داشبورد مرکزی](#۱-وضعیت-اتصال-و-داشبورد-مرکزی)
  - [۲. بخش امنیت و حریم خصوصی](#۲-بخش-امنیت-و-حریم-خصوصی)
  - [۳. تنظیمات پیشرفته شبکه](#۳-تنظیمات-پیشرفته-شبکه)
  - [۴. سیستم لاگ زنده](#۴-سیستم-لاگ-زنده)
- [معماری و ساختار پروژه](#-معماری-و-ساختار-پروژه)
- [دستورات مدیریتی](#-دستورات-مدیریتی)
- [عیب‌یابی و رفع مشکلات رایج](#-عیب‌یابی-و-رفع-مشکلات-رایج)
- [حذف کامل](#-حذف-کامل)
- [مجوز](#-مجوز)

---

## 🚀 نصب سریع

برای نصب، از طریق SSH به روتر خود متصل شوید و دستور زیر را اجرا کنید:

```bash
wget -O /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh \
  https://github.com/MehArt44/nordvpnlite-UI/releases/download/0.1.0-r1/nordvpnlite.0.1.0-r1_UI_Final.sh

sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh install
```

> **⚠️ توجه:** اجرای اسکریپت حتماً نیاز به دسترسی `root` دارد.

پس از نصب، منوی **NordVPN Lite** به رابط وب روتر شما اضافه خواهد شد. **حتماً از حساب کاربری LuCI خارج و مجدداً وارد شوید** و سپس صفحه را با `Ctrl+Shift+R` رفرش کنید.

### گزینه‌های نصب (اختیاری)

```bash
sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh install --dns     # فعال‌سازی اجباری DNS Hardening
sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh install --no-dns  # غیرفعال‌سازی DNS Hardening
sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh install --ks-on   # فعال‌سازی خودکار Kill Switch
sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh install --allow-wan # اجازه دسترسی به WAN
```

---

## 📦 پیش‌نیازها

- **سیستم‌عامل:** OpenWrt 25.12 یا بالاتر (با پشتیبانی از apk)
- **معماری:** arm64، x86_64 یا سایر معماری‌های پشتیبانی‌شده
- **فضای دیسک:** حداقل ۵ مگابایت فضای آزاد
- **پکیج‌های مورد نیاز (به‌صورت خودکار نصب می‌شوند):**
  - `nordvpnlite` (از مخزن رسمی NordVPN)
  - `rpcd-mod-file`
  - `wireguard-tools` و `kmod-wireguard` (برای حالت Fixed Server)
  - `luci-proto-wireguard`
  - `curl` و `ca-bundle`

> **نکته:** از OpenWrt 25.12 به بعد، مدیریت بسته از `opkg` به `apk` (Alpine Package Keeper) تغییر کرده است. اسکریپت نصب به‌صورت خودکار نسخه OpenWrt شما را تشخیص داده و از مدیر بسته مناسب استفاده می‌کند.

---

## 🎨 ویژگی‌های کلیدی داشبورد

### ۱. وضعیت اتصال و داشبورد مرکزی

- **نظارت لحظه‌ای:** نمایش وضعیت فعلی تونل (متصل، در حال اتصال، قطع، فاقد مسیر ارتباطی، یا نیازمند توکن) با کدهای رنگی بصری.
- **وضعیت ترافیک:** مانیتورینگ زنده میزان پینگ (Ping) بر حسب میلی‌ثانیه، و حجم دانلود و آپلود.
- **مدیریت IP:** نمایش آدرس IP خروجی (Endpoint)، IP عمومی (Public) و IP پایه (Baseline) به همراه دکمه‌های کپی سریع در کلیپ‌بورد.
- **نمایش کشور و سرور:** پرچم، نام کشور و هاست مقصد به‌صورت خودکار از سرور NordVPN استخراج و نمایش داده می‌شود.
- **نمایش Uptime:** مدت زمان اتصال به‌همراه سن آخرین Handshake.

### ۲. بخش امنیت و حریم خصوصی (Security & Privacy)

| ابزار امنیتی | توضیحات عملکردی |
|---|---|
| **Kill Switch** | با فعال‌سازی این قابلیت، در صورت قطع شدن غیرمنتظره ارتباط VPN، ترافیک اینترنت کاملاً مسدود می‌شود تا از لو رفتن هویت شما جلوگیری شود. |
| **IPv6 Mode** | قابلیت انتخاب بین دو حالت: مسدودسازی کامل IPv6 در کل روتر (حداکثر امنیت) یا صرفاً مسدودسازی فورواردینگ از شبکه محلی به سمت WAN (حالت توصیه‌شده). |
| **محافظت در برابر نشت (Leak Protection)** | بررسی مداوم وضعیت تونل، نشت DNS و نشت IP. با زدن دکمه «Privacy Check» یک گزارش متنی عمیق از وضعیت امنیت و حریم خصوصی در لحظه تولید می‌شود. |
| **DoH Enforcement** | مسدودسازی ترافیک DNS-over-HTTPS برای جلوگیری از دور زدن قوانین DNS. شامل دو حالت Standard (مسدودسازی QUIC) و Strict (مسدودسازی TCP 443 به ارائه‌دهندگان DoH). |

### ۳. تنظیمات پیشرفته شبکه (Advanced Settings)

- **احراز هویت (Token):** فیلد اختصاصی برای وارد کردن توکن حساب NordVPN با سیستم هشدار هوشمند در صورت خالی بودن. قابلیت ذخیره یا فراموشی توکن در این بخش تعبیه شده است.
- **انتخاب سرور و کشور:** یک منوی کشویی پیشرفته با قابلیت جستجوی متنی، نمایش نام و پرچم کشورها، و پشتیبانی از اتصال خودکار (Automatic).
- **پروتکل‌های ارتباطی:** پشتیبانی فعال از پروتکل مبتنی بر WireGuard (با نام NordLynx) و در نظر گرفتن معماری لازم برای پروتکل‌های آینده (مانند NordWhisper و OpenVPN).
- **حالت‌های مسدودسازی DoH:**
  - **Standard:** مسدودسازی ترافیک QUIC (UDP 443) برای جلوگیری از دور زدن قوانین DNS.
  - **Strict:** علاوه بر QUIC، ترافیک TCP 443 به سمت ارائه‌دهندگان معروف DoH نیز مسدود می‌شود.
- **بهینه‌سازی MTU:** امکان قرار دادن MTU روی حالت `Auto` (توصیه‌شده — 1420 برای WireGuard) یا تنظیم دستی مقادیری نظیر 1280، 1360 تا 1500 متناسب با نوع شبکه (مثل PPPoE).
- **LAN Discovery:** گزینه‌ای برای مستثنی کردن شبکه‌های خصوصی (RFC1918) از تونل VPN، تا دسترسی به دستگاه‌های درون شبکه محلی قطع نشود.
- **لیست مجاز (Allowlist):** فیلدی برای وارد کردن ساب‌نت‌ها (CIDR) در خطوط مجزا تا ترافیک آن‌ها مستقیماً و بدون عبور از VPN مسیریابی شود.
- **رمزنگاری پساکوانتومی (Post-quantum):** کلید فعال‌سازی استانداردهای رمزنگاری جدید برای مقابله با تهدیدات کامپیوترهای کوانتومی.
- **ارسال گزارش‌های تحلیلی (Analytics):** امکان فعال یا غیرفعال کردن ارسال داده‌های تحلیلی ناشناس به سرور.

### ۴. سیستم لاگ زنده (Live Logs)

داشبورد مجهز به یک ترمینال داخلی است که فایل `/var/log/nordvpnlite.log` را در لحظه پایش می‌کند.

- عبارات بر اساس نوع (INFO, ERROR, WARN, SEC) و کلمات کلیدی (مانند timeout یا connected) با رنگ‌های متمایز نشانه‌گذاری می‌شوند تا عیب‌یابی به سریع‌ترین شکل ممکن انجام شود.
- سیستم به صورت خودکار به جدیدترین لاگ‌ها اسکرول می‌کند.
- امکان رفرش دستی یا پاک‌سازی لاگ‌ها از طریق دکمه‌های موجود فراهم است.

---

## 🏗 معماری و ساختار پروژه

این پروژه از یک اسکریپت Shell تشکیل شده که فایل‌های رابط کاربری و اجرایی را در مسیرهای مناسب OpenWrt نصب می‌کند:

| مسیر | توضیح |
|---|---|
| `/usr/libexec/nordvpnlite-ui` | فایل اجرایی پس‌زمینه (Helper) که ارتباط بین UI و سیستم را برقرار می‌کند. |
| `/www/luci-static/resources/view/nordvpnlite/settings.js` | فایل جاوااسکریپت اصلی رابط کاربری (LuCI View). |
| `/usr/share/luci/menu.d/luci-app-nordvpnlite.json` | فایل تعریف منوی LuCI. |
| `/usr/share/rpcd/acl.d/luci-app-nordvpnlite-ui.json` | فایل ACL برای کنترل دسترسی‌های امن. |
| `/etc/nordvpnlite/` | پوشه تنظیمات و فایل‌های پیکربندی. |

رابط کاربری برای اعمال تغییرات و دریافت داده‌ها، مستقیماً با فایل اجرایی `/usr/libexec/nordvpnlite-ui` ارتباط برقرار می‌کند.

---

## 🛠 دستورات مدیریتی

پس از نصب، می‌توانید از دستورات زیر برای مدیریت استفاده کنید:

```bash
# به‌روزرسانی به آخرین نسخه
sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh upgrade

# بازیابی به حالت اولیه (حذف تونل WireGuard و بازگشت به حالت خودکار)
sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh recover

# اتصال دستی به یک سرور خاص (WireGuard)
SERVER_HOST="de1119.nordvpn.com" sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh wireguard

# حذف تونل WireGuard دستی
sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh wireguard remove
```

### دستورات داخلی Helper

```bash
/usr/libexec/nordvpnlite-ui status           # نمایش وضعیت کامل
/usr/libexec/nordvpnlite-ui killswitch-on    # فعال‌سازی Kill Switch
/usr/libexec/nordvpnlite-ui killswitch-off   # غیرفعال‌سازی Kill Switch
/usr/libexec/nordvpnlite-ui diagnostics      # اجرای تشخیص کامل
/usr/libexec/nordvpnlite-ui route-debug      # اشکال‌زدایی مسیر
/usr/libexec/nordvpnlite-ui log              # نمایش لاگ زنده
```

---

## 🔧 عیب‌یابی و رفع مشکلات رایج

| مشکل | راه‌حل |
|---|---|
| **پیام "توکن احراز هویت مورد نیاز است"** | به بخش تنظیمات رفته و توکن NordVPN خود را وارد کنید. توکن را می‌توانید از [Nord Account](https://my.nordaccount.com/) → Manual setup → NordLynx → Access token دریافت کنید. |
| **اتصال برقرار می‌شود اما اینترنت کار نمی‌کند** | احتمالاً مشکل MTU وجود دارد. به بخش تنظیمات پیشرفته رفته و MTU را روی 1280 یا 1360 تنظیم کنید. |
| **Kill Switch فعال نمی‌شود** | اطمینان حاصل کنید که توکن ذخیره شده و تونل VPN متصل است. Kill Switch فقط زمانی فعال می‌شود که Handshake برقرار باشد. |
| **DNS Leak detected** | مطمئن شوید که حالت DoH روی Standard یا Strict تنظیم شده است. همچنین می‌توانید از دکمه «Privacy Check» برای بررسی دقیق‌تر استفاده کنید. |
| **بعد از آپدیت، UI بارگذاری نمی‌شود** | دستور `upgrade` را دوباره اجرا کنید. اسکریپت به‌صورت خودکار فایل `settings.js` را بازیابی می‌کند. |
| **سرور Fixed Server وصل نمی‌شود** | از دکمه «Diagnose» در بخش Fixed server استفاده کنید و لاگ را بررسی نمایید. |


## 🗑 حذف کامل

```bash
# حذف رابط کاربری (تنظیمات و مخازن حفظ می‌شوند)
sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh uninstall

# حذف کامل (شامل Kill Switch، DNS Hardening، Allowlist و مخازن)
sh /tmp/nordvpnlite.0.1.0-r1_UI_Final.sh uninstall --purge
```

> **⚠️ توجه:** اگر حالت Fixed Server فعال است، ابتدا با دستور `recover` آن را غیرفعال کنید.

---

## 📄 مجوز

این پروژه تحت مجوز MIT منتشر شده است. برای اطلاعات بیشتر به فایل [LICENSE](LICENSE) مراجعه کنید.

---

## 🤝 مشارکت

از مشارکت شما استقبال می‌شود! لطفاً برای گزارش باگ یا درخواست ویژگی جدید، از بخش [Issues](https://github.com/MehArt44/nordvpnlite-UI/issues) استفاده کنید.

---

## 🔗 لینک‌های مفید

- [مخزن GitHub پروژه](https://github.com/MehArt44/nordvpnlite-UI)
- [NordVPN Lite روی OpenWrt](https://openwrt.org/docs/guide-user/services/vpn/nordvpn)
- [مستندات LuCI](https://openwrt.org/docs/guide-developer/luci)
- [انجمن OpenWrt](https://forum.openwrt.org/)

---

**ساخته شده با ❤️ برای جامعه OpenWrt**

محیط نرم افزار


<img width="2154" height="1556" alt="image" src="https://github.com/user-attachments/assets/b763a67d-efe2-4325-9eae-74743cc80617" />

