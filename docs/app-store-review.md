# App Store review — red gerekçesi ve hazır cevaplar

**Durum:** macOS 1.0 (build 0.2.0) reddedildi.
**Gerekçe:** Guideline 2.1 — Information Needed, New App Submission.
**Mesaj tarihi:** 20 Ağustos 2026, 19:24.

> **Durum (21 Ağustos 11:16):** Notes alanı dolduruldu ve kaydedildi.
> Resolution Center cevabı **taslak** olarak kaydedildi, gönderilmedi.
> Kalan tek adım: ekran kaydını çekip cevaba eklemek, sonra Reply + Resubmit.
> Ayrıntı için bölüm 6.

Bu bir hata/uyumsuzluk reddi değil. Apple yeni uygulamalarda **App Review
Information → Notes alanı boşsa** bu standart mesajı gönderiyor ve incelemeyi
durduruyor. Kontrol ettim: Notes alanı gerçekten boş. Uygulamada, imzada,
sandbox'ta, gizlilik sayfasında bir sorun bildirilmemiş.

Sign-In Information zaten doldurulmuş (`ghbar-review`) ve demo hesabı da
doğru kurulmuş — GHBar'ın gerçek sorgularını hesap üzerinde çalıştırdım:

| Bölüm | Sonuç |
|---|---|
| `is:pr is:open user:@me -author:@me` | 2 PR (ikisi de @cobanov açmış) |
| `is:issue is:open user:@me -author:@me` | 3 issue |
| `is:pr is:open review-requested:@me` | 1 PR |

Yani reviewer giriş yaptığında menüde üç bölüm de dolu görünecek. Tek eksik
Apple'ın istediği bilgiler.

---

## Apple ne istedi

1. Fiziksel bir cihazda, güncel işletim sisteminde çekilmiş, uygulamanın
   açılışından başlayıp ana akışı gösteren **ekran kaydı**
2. Test edilen **cihaz modelleri ve işletim sistemi sürümleri**
3. Uygulamanın **ne yaptığı ve hedef kitlesi**
4. **Kurulum ve erişim talimatları**, gereken giriş bilgileri
5. Kullanılan **dış servisler** (veri sağlayıcı, kimlik doğrulama, ödeme, AI…)
6. **Bölgesel farklar** var mı
7. **Düzenlemeye tabi sektör** veya korumalı üçüncü taraf materyali var mı

1 numarayı senin çekmen gerekiyor (bkz. bölüm 3). 2–7 aşağıda hazır.

---

## 1. Notes alanına yapıştırılacak metin

**Yapıldı** — 21 Ağustos 11:14'te Notes alanına yazıldı ve kaydedildi;
sayfa yeniden yüklenerek doğrulandı (3.857 karakter, 4.000 sınırının altında).
Aşağıdaki metin kayıt için duruyor.

Doldurulacak yer kalmadı: cihaz bilgisi bu Mac'ten alındı (Mac mini M4 Pro,
macOS 26.6.1) ve ekran kaydı satırı "attached to this submission" olarak
yazıldı — kaydı Notes'un hemen altındaki **Attachment** alanına ekleyeceksin.
Başka bir Mac'te de test ettiysen 4. maddeye bir satır ekle.

```
GHBar is a macOS menu bar utility. Please read item 1 before testing: the
app deliberately has no Dock icon and no main window.

1. HOW TO LAUNCH AND FIND THE APP
GHBar is a menu bar accessory app (LSUIElement = true). After launching it,
nothing appears in the Dock or in the app switcher. Look for the GHBar icon
in the menu bar at the top-right of the screen, next to the system icons,
and click it to open the app's menu. On first launch a "Welcome to GHBar"
window also opens automatically.

2. SIGNING IN — DEMO ACCOUNT
Sign-in uses GitHub's OAuth 2.0 Device Authorization Grant (RFC 8628):
  a. Click "Sign in with GitHub" in the Welcome window.
  b. The app shows an 8-character code, copies it to the clipboard and opens
     https://github.com/login/device in the default browser.
  c. Sign in on github.com with the demo account provided in the Sign-In
     Information fields above (username: ghbar-review). Two-factor
     authentication is disabled on that account.
  d. Paste the code, click Continue, then Authorize.
  e. The Welcome window closes and the menu is populated.
Please leave the "Include private repositories" checkbox unchecked — all of
the demo account's content is public. If github.com asks for a verification
code sent by email, please tell us in Resolution Center and we will provide
it immediately.

3. WHAT THE APP DOES AND WHO IT IS FOR
GHBar shows a developer the pull requests and issues that OTHER people have
opened on their own GitHub repositories, plus pull requests waiting on their
review, as a menu bar list with an unread count. GitHub's own notification
inbox mixes these with comments, CI results and subscribed threads; GHBar
isolates the one signal that requires the repository owner to act. Target
audience: developers and open source maintainers who own GitHub
repositories. The demo account is prepared with 2 pull requests, 3 issues
and 1 review request, so all three sections of the menu are populated.

4. DEVICES AND OPERATING SYSTEMS TESTED
  - Mac mini (Mac16,11), Apple M4 Pro, macOS 26.6.1 (build 25G76)
A physical Mac, not a virtual machine. The submitted build is installed and
in daily use on this machine.

5. EXTERNAL SERVICES USED
  - GitHub GraphQL API (api.github.com) — the only data source. Queried with
    the signed-in user's own OAuth token, one request per refresh.
  - GitHub OAuth device flow (github.com/login/device) — authentication.
There is no other network destination. GHBar has no server or backend of its
own, no analytics, no crash reporting, no advertising SDK, no AI service and
no payment processing.

6. REGIONAL DIFFERENCES
None. The app behaves identically in every region, has a single English
localization, and contains no region-gated content, features or pricing.

7. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. GHBar is a developer tool and does not operate in a regulated
industry. It displays only content from the signed-in user's own GitHub
account, retrieved with that user's own credentials through GitHub's public
API and under GitHub's Terms of Service. No third-party protected material is
bundled: the app icon and the entire interface are original work. GHBar is an
independent open-source project (MIT licensed) and is not affiliated with or
endorsed by GitHub, Inc. Source code: https://github.com/cobanov/ghbar

8. PERMISSIONS AND PRIVACY
The only system permission GHBar requests is notifications, asked for when
the first notification is about to be posted rather than at launch. No
location, contacts, camera, microphone or tracking permission is requested.
The OAuth token is stored only in the macOS Keychain. Privacy policy:
https://ghbar.cobanov.dev/privacy

9. SCREEN RECORDING
A recording of the complete flow — launch, menu bar icon, sign-in, populated
menu, opening an item, settings — is attached to this submission.
```

---

## 2. Resolution Center'a yazılacak cevap

**Taslak olarak kaydedildi** — App Store → App Review → 19 Ağustos
submission'ı → Reply to App Review. Mesaj listesinde "Mert Cobanoglu, Today
11:16 AM" olarak görünüyor, altında **Continue Draft** / **Delete Draft**
bağlantıları var. Apple'a **gitmedi**; Reply düğmesine basılmadı.

```
Thank you for the review. We have filled in the App Review Information Notes
field with all seven items you requested, and we are attaching a screen
recording of the complete user flow.

A summary:

- GHBar is a macOS menu bar utility. It has no Dock icon and no main window
  by design (LSUIElement). After launch, the app is accessed by clicking the
  GHBar icon in the menu bar at the top-right of the screen. A "Welcome to
  GHBar" window also opens automatically on first launch.
- Demo account credentials are in the Sign-In Information fields (username:
  ghbar-review, two-factor authentication disabled). Sign-in uses GitHub's
  OAuth 2.0 Device Authorization Grant; step-by-step instructions are in the
  Notes field. The account is prepared with pull requests, issues and a
  review request so that every section of the menu shows content.
- The app's only external service is the GitHub API, queried with the
  signed-in user's own token. GHBar has no server, no analytics and no
  third-party SDKs, and collects no data.
- The app behaves identically in all regions, is not part of a regulated
  industry and bundles no protected third-party material.

Please let us know if anything else would help the review.
```

---

## 3. Ekran kaydı — çekim listesi

Apple'ın istediği tek şey senin yapman gereken kısım. QuickTime Player → File
→ New Screen Recording yeterli. 60–120 saniye, kesintisiz, sesli anlatım
şart değil.

**Önce uygulamayı sıfırla** ki kayıt gerçekten "ilk açılış"tan başlasın:

```bash
security delete-generic-password -s run.cobanov.ghbar 2>/dev/null
rm -rf ~/Library/Application\ Support/GHBar
pkill -x GHBar
```

Sandbox'lı MAS derlemesini test ediyorsan `seen.json` konteynerde durur:

```bash
rm -rf ~/Library/Containers/run.cobanov.ghbar
```

**Sıra:**

1. Finder'da Applications klasörü, GHBar.app'e çift tıkla — kayıt açılışla
   başlamalı, Apple bunu özellikle istiyor.
2. İmleci menü çubuğundaki GHBar simgesine götür, bir an bekle. Dock'ta hiçbir
   şey çıkmadığı görülsün — reddin asıl sebebi bu belirsizlik.
3. Açılan Welcome penceresinde "Sign in with GitHub"a tıkla.
4. Tarayıcı `github.com/login/device`'ı açar; `ghbar-review` hesabıyla gir,
   kodu yapıştır, Authorize'a bas.
5. Menü çubuğu simgesine tıkla — Pull Requests, Issues ve Review Requested
   bölümlerinin dolu olduğu görünsün.
6. Bir satıra tıkla, GitHub tarayıcıda açılsın.
7. Menüden Settings'i aç, üç sekmeyi de göster.
8. Menüden Quit.

Kaydı `.mov` olarak bırak. Notes'un altındaki **Attachment** alanına ekle;
dosya büyükse bir yere yükleyip bağlantısını Notes'un 9. maddesine yaz.

---

## 4. Sıradaki tur için risk: 3. ekran görüntüsü

Apple'ın mesajının sonundaki "common issues" listesinde şu var: *ekran
görüntüleri uygulamayı kullanımda göstermeli, sadece başlık görseli, giriş
sayfası veya açılış ekranı olmamalı* (Guideline 2.3.3).

Şu an üç ekran görüntüsü var ve üçüncüsü (`3-signin.png`) tam olarak giriş
ekranı. Bu tur için bir bulgu olarak yazılmamış, ama bir sonraki turda
takılabilir. `ScreenshotRenderer.renderAll` içindeki üçüncü kaydı uygulamayı
kullanımda gösteren bir sahneyle değiştirmek (ör. bildirim, ya da katlanmış
repo grubu olan bir menü) bu riski kapatır — istersen ekleyebilirim.

---

## 4b. App Sandbox Information — boş kalmalı

Version sayfasındaki bu bölüm opsiyonel ve boş. Açtım, baktım: listenin başlığı
"Required Entitlement Keys" ve içinde yalnızca **gerekçe isteyen** anahtarlar
var — `com.apple.security.temporary-exception.*`, photos project-conversion,
videotoolbox gibi. GHBar sadece `com.apple.security.app-sandbox` ve
`com.apple.security.network.client` kullanıyor; ikisi de bu listede yok, çünkü
açıklama gerektirmiyorlar. Bölümü boş bırakmak doğru.

## 5. App Privacy — kontrol et

Red mesajında geçmiyor, ben de dokunmadım. Forma bakmakta fayda var. Doğru cevap:

> **Data Collection: No, we do not collect data from this app.**

Apple'ın "collect" tanımı verinin cihazdan çıkıp **geliştiriciye** ulaşmasıdır.
GHBar'ın sunucusu, analytics'i, crash reporting'i yok; token Keychain'de,
görülmüşlük kaydı ve avatar konteynerde. Kullanıcının GitHub'a giden trafiği
kendi hesabının trafiği — bu "collection" sayılmaz.

| Alan | Değer |
|---|---|
| Privacy Policy URL | `https://ghbar.cobanov.dev/privacy` |
| Support URL | `https://ghbar.cobanov.dev` |
| Marketing URL | `https://ghbar.cobanov.dev` |
| Category | Developer Tools |
| Encryption | `ITSAppUsesNonExemptEncryption=false` (Info.plist'te) |

---

## 6. Kalan adımlar — sırasıyla

1. Bölüm 3'teki listeye göre ekran kaydını çek.
2. App Store Connect → App Review → 19 Ağustos submission'ı → mesajlardaki
   kendi taslağının altındaki **Continue Draft**.
3. Açılan pencerede **Attach File** ile kaydı ekle.
4. **Reply** düğmesine bas — cevap Apple'a o zaman gider.
5. Sayfanın üstündeki **Resubmit to App Review**.

Yeni build gerekmiyor — reddedilen 0.2.0 build'i duruyor, sadece metadata ve
cevap değişiyor.

Kayıt dosyası ekleyemeyecek kadar büyükse bir yere yükleyip bağlantısını
cevaba ekle; Notes'un 9. maddesi "attached to this submission" diyor, o
durumda o cümleyi bağlantıyla değiştirmek gerekir.

Yeni build göndereceksen:

```bash
make check        # iki varyant da derlenir, testler koşar
make pkg          # build/GHBar-<VERSION>-mas.pkg, Distribution ile imzalı
```

Sonra Transporter.app ile yükle. `Makefile` içindeki `VERSION`'ı artırmayı
unutma — aynı build numarası ikinci kez kabul edilmiyor.

---

## 7. Yedek cevaplar — bu turda gerekmiyor

Bir sonraki turda başka gerekçe gelirse diye hazır duruyor.

### 4.8 / 5.1.1(v) — "Login Services" veya zorunlu hesap

```
GHBar is a client for a single, specific service: GitHub. It does not create
or maintain an account of its own, and GitHub is not used as a social login
to authenticate a GHBar account — the GitHub account *is* the content being
displayed. The app's entire function is to show the signed-in person their
own pull requests and issues, which cannot be retrieved without their GitHub
credentials. GHBar collects no personal data, has no server and no analytics,
and stores the OAuth token only in the local macOS Keychain. Sign-in uses
GitHub's official OAuth 2.0 Device Authorization Grant, so the app never sees
the user's GitHub password.
```

### 4.2 — "Minimum Functionality"

```
GHBar is not a repackaged website — it is a native macOS AppKit/SwiftUI menu
bar client. It maintains local state that the GitHub website does not
provide: a per-item read/unread record that survives restarts, native macOS
notifications for new contributions, automatic refresh on wake from sleep,
per-repository filtering and grouping rules, launch at login, and a menu bar
badge count. None of this is available by visiting github.com in a browser.
```
