# GHBar — Tasarım Dokümanı

**Tarih:** 2026-08-18
**Durum:** Onaylandı, uygulamaya hazır

---

## 1. Amaç

Repolarına başkaları tarafından açılan pull request ve issue'ları, ayrıca senden
review istenen PR'ları macOS menü çubuğundan tek bakışta görebilmek.

Bugün bu bilgi iki yerde duruyor: `~/bin/gh-prs` script'i (terminalden elle
çalıştırılıyor) ve `com.cobanov.gh-prs` launchd ajanı (15 dakikada bir telefona
ntfy bildirimi atıyor). İkisi de "şu an ne bekliyor?" sorusuna anlık cevap
vermiyor — biri terminal açmayı, diğeri telefona bakmayı gerektiriyor.

GHBar bu boşluğu dolduruyor: sayı menü çubuğunda hep görünür, detay bir tık uzakta.

### Başarı ölçütü

- Menü çubuğunda bekleyen iş sayısı görünüyor.
- Menüyü açmak listeyi gösteriyor; bir satıra tıklamak GitHub'da açıyor.
- Yeni bir PR/issue geldiğinde Mac'te bildirim çıkıyor.
- Mevcut ntfy izleyicisi bozulmadan çalışmaya devam ediyor.

---

## 2. Kapsam dışı

Bilinçli olarak yapılmayacaklar:

- PR merge etme, kapatma, yorum yazma — GHBar salt okunur bir gösterge.
- Diff görüntüleme.
- Birden fazla GitHub hesabı.
- Grafik ayar penceresi (bkz. §7 — ayarlar bir JSON dosyası).
- Bildirim geçmişi / arşiv.

---

## 3. Mimari

Uygulama on küçük parçadan oluşuyor. Her biri tek bir işten sorumlu ve
diğerlerinden bağımsız test edilebiliyor.

| Dosya | Sorumluluk |
|---|---|
| `main.swift` | Uygulamayı başlatır, `NSApplication` kurar |
| `AppDelegate.swift` | Durum çubuğu öğesi, zamanlayıcı, yenileme döngüsü |
| `Config.swift` | Ayar dosyasını okur, varsayılanları verir, sorgu metnini üretir |
| `GitHubClient.swift` | `gh` alt sürecini çalıştırır, JSON'u çözer |
| `Models.swift` | `Item`, `Section`, `RateLimit`, `Viewer` veri tipleri |
| `Filtering.swift` | Bot elemesi, sıralama, bölümlere ayırma |
| `SeenStore.swift` | Hangi öğelerin görüldüğünü diskte tutar |
| `MenuBuilder.swift` | Veriden `NSMenu` üretir |
| `Notifier.swift` | Yeni öğeler için macOS bildirimi |
| `Formatting.swift` | Yaş metni (`17sa`, `3g`), başlık kırpma, sayı biçimi |

**Bağımlılık yönü tek taraflı:** `AppDelegate` → (`Config`, `GitHubClient`,
`Filtering`, `SeenStore`, `MenuBuilder`, `Notifier`). Alt katmanlar birbirini
tanımıyor; `MenuBuilder` ağ bilmiyor, `GitHubClient` menü bilmiyor. Bu sayede
`Filtering`, `SeenStore` ve `Formatting` saf fonksiyonlar olarak test edilebiliyor.

### Dosya düzeni

```
ghbar/
  Package.swift
  Makefile
  Sources/GHBar/
    main.swift
    AppDelegate.swift
    Config.swift
    GitHubClient.swift
    Models.swift
    Filtering.swift
    SeenStore.swift
    MenuBuilder.swift
    Notifier.swift
    Formatting.swift
    Resources/
      query.graphql
  Tests/GHBarTests/
    FilteringTests.swift
    FormattingTests.swift
    SeenStoreTests.swift
    ParsingTests.swift
    ConfigTests.swift
  docs/superpowers/specs/
```

---

## 4. Veri akışı

```
zamanlayıcı (5 dk)  ─┐
menü açılışı        ─┼─→ AppDelegate.refresh()
uykudan uyanma      ─┤
elle "Refresh" (⌘R) ─┘
                          │
                          ▼
              Config.buildQueries()      ← ~/.config/ghbar/config.json
                          │
                          ▼
              GitHubClient.fetch()       ← /opt/homebrew/bin/gh api graphql
                          │
                          ▼
              Filtering.process()        ← botları ele, sırala, bölümle
                          │
                          ├──→ SeenStore.diff()  → yeni olanlar → Notifier
                          │
                          ▼
              MenuBuilder.build()        → NSStatusItem.menu
```

Yenileme **eşzamansız** (arka planda) çalışır; menü çizimi ana iş parçacığında
yapılır. Yenileme sürerken menü açılırsa eski veri gösterilir — boş menü
göstermek daha kötü olurdu.

Aynı anda ikinci bir yenileme başlatılmaz; süren bir istek varken gelen tetikler
yok sayılır.

---

## 5. GitHub sorgusu

Tek bir GraphQL isteği; üç arama, profil bilgisi ve kota durumu birlikte geliyor.

**Doğrulandı (2026-08-18):** sorgu çalışıyor ve toplam maliyeti **1 puan**.
5 dakikada bir yenileme = saatte 12 puan; kota saatte 5000.

`Sources/GHBar/Resources/query.graphql`:

```graphql
query($prs: String!, $issues: String!, $review: String!, $first: Int!) {
  viewer { login name avatarUrl }

  prs: search(query: $prs, type: ISSUE, first: $first) {
    issueCount
    nodes { ... on PullRequest {
      number title url createdAt isDraft
      author { login __typename }
      repository { nameWithOwner }
    } }
  }

  issues: search(query: $issues, type: ISSUE, first: $first) {
    issueCount
    nodes { ... on Issue {
      number title url createdAt
      author { login __typename }
      repository { nameWithOwner }
    } }
  }

  review: search(query: $review, type: ISSUE, first: $first) {
    issueCount
    nodes { ... on PullRequest {
      number title url createdAt isDraft
      author { login __typename }
      repository { nameWithOwner }
    } }
  }

  rateLimit { limit remaining resetAt cost }
}
```

`first` değeri **100** (GitHub aramanın üst sınırı). Sayfalama yapılmayacak —
ölçüm sırasında en büyük küme 64 öğeydi, 100 fazlasıyla yetiyor. Sonuç 100'e
dayanırsa menüde uyarı satırı gösterilir (§12).

### Sorgu metinlerinin üretimi

`Config` şu üç metni üretir (`owners` ve `exclude` ayarlarından):

```
prs    = "is:pr is:open user:cobanov -author:cobanov -repo:cobanov/team-cobanov"
issues = "is:issue is:open user:cobanov -author:cobanov -repo:cobanov/team-cobanov"
review = "is:pr is:open review-requested:cobanov"
```

Kurallar:

- Her `owners` girdisi bir `user:<owner>` parçası olur.
- Her `owners` girdisi ayrıca bir `-author:<owner>` parçası olur (kendi
  açtıklarını görmek istemiyoruz).
- Her `exclude` girdisi bir `-repo:<owner>/<name>` parçası olur. Girdi `/`
  içermiyorsa ilk owner ile birleştirilir (`team-cobanov` →
  `-repo:cobanov/team-cobanov`).
- `review` sorgusu `owners`'dan bağımsız — senden review istenen her PR, hangi
  repoda olursa olsun.

**Dışlama neden sorgunun içinde?** Arama en fazla 100 sonuç döndürüyor. Ölçümde
64 PR'ın 50'si `team-cobanov`'dan geliyordu. Dışlamayı sonradan yapsaydık,
o repo büyüdüğünde gerçek PR'lar 100'lük pencerenin dışında kalıp görünmez
olurdu — üstelik sessizce.

---

## 6. Filtreleme kuralları

Sorgudan dönen sonuçlara istemci tarafında uygulanır:

1. **Bot elemesi.** `author.__typename == "Bot"` **veya** `author.login`
   `[bot]` ile bitiyorsa atılır. `showBots: true` ise bu adım atlanır.
   İki koşul birlikte gerekli: GitHub bazı bot hesaplarını `User` tipiyle
   döndürüyor, bazılarının login'i `[bot]` ekiyle geliyor.
2. **Yazarsız öğeler.** `author` `null` olabilir (silinmiş hesap). Bu öğeler
   atılır — kime ait olduğu belli olmayan bir satır göstermenin anlamı yok.
3. **Sıralama.** `createdAt` azalan (en yeni üstte).
4. **Bölümleme.** `prs` → Pull Requests, `issues` → Issues, `review` →
   Review Requested.
5. **`review` ile `prs` çakışması.** Kendi repolarından birinde senden review
   istenmişse aynı PR iki bölümde de çıkabilir. Bu durumda öğe **sadece
   Review Requested** bölümünde gösterilir — review istenmiş olmak daha güçlü
   bir sinyal.

**Neden bot elemesi istemci tarafında?** GitHub aramada "bot olmayan" diye genel
bir nitelik yok; tek tek `-author:app/dependabot` yazmak gerekir ve yeni bir bot
çıktığında sessizce sızar. `__typename` her yazar için bedavaya geliyor, o yüzden
eleme burada yapılıyor. Ölçümde 64 PR'dan sadece 3'ü bottu, yani 100'lük pencereyi
zorlamıyor.

---

## 7. Yapılandırma

**Konum:** `~/.config/ghbar/config.json`

Dosya yoksa ilk çalıştırmada varsayılanlarla oluşturulur.

```jsonc
{
  "owners": ["cobanov"],
  "exclude": ["team-cobanov"],
  "showBots": false,
  "refreshMinutes": 5,
  "maxRowsPerSection": 5,
  "notifications": true,
  "menuBarStyle": "avatar"
}
```

| Alan | Anlamı | Varsayılan |
|---|---|---|
| `owners` | Taranacak hesap/organizasyonlar | `["cobanov"]` |
| `exclude` | Dışlanacak repolar (`ad` veya `owner/ad`) | `["team-cobanov"]` |
| `showBots` | Bot PR'ları gösterilsin mi | `false` |
| `refreshMinutes` | Yenileme aralığı, dakika (en az 1) | `5` |
| `maxRowsPerSection` | Bölüm başına doğrudan gösterilen satır | `5` |
| `notifications` | macOS bildirimi çıksın mı | `true` |
| `menuBarStyle` | `"avatar"` veya `"icon"` | `"avatar"` |

**"Configure" menü satırı** bu dosyayı sistemin varsayılan editöründe açar
(`NSWorkspace.open`). Ayrı bir ayar penceresi yazılmıyor — kazancı, maliyetini
karşılamıyor.

Dosya `DispatchSource` ile izlenir; kaydedildiğinde ayarlar yeniden okunur ve
hemen bir yenileme tetiklenir.

Dosya bozuksa (geçersiz JSON) varsayılanlarla devam edilir ve menüde uyarı
satırı gösterilir (§12) — sessizce varsayılana düşmek, kullanıcının değişikliğinin
neden işe yaramadığını anlamasını engeller.

**Not:** Ölçümde `paul-graham-turkce` reposunun 18 açık issue'su olduğu görüldü
(toplam 32'nin yarısından fazlası). Kullanıcı isterse `exclude` listesine ekler;
varsayılana konmadı çünkü bunlar gerçek, insan tarafından açılmış issue'lar.

---

## 8. Görülme durumu

**Konum:** `~/Library/Application Support/GHBar/seen.json`

```jsonc
{
  "version": 1,
  "seen": {
    "https://github.com/cobanov/herdrchat/pull/55": "2026-08-18T11:29:00Z"
  }
}
```

Anahtar öğenin URL'i (kalıcı ve benzersiz), değer görüldüğü an.

**Bir öğe şu durumlarda görülmüş sayılır:**
- Satırına tıklandığında (tarayıcıda açılırken),
- Bölümündeki "Mark All as Seen" tıklandığında,
- Bildirimine tıklandığında.

**Temizlik.** Her yenilemede, artık sonuçlarda olmayan (kapanmış/merge olmuş)
URL'ler dosyadan silinir. Aksi halde dosya sonsuza kadar büyür.

**`gh-prs` ile ilişkisi: yok.** `gh-prs` kendi durumunu
`~/.local/state/gh-prs/seen.txt` içinde tutuyor ve GHBar bu dosyaya **hiç
dokunmuyor**. İkisi paylaşsaydı, Mac'te gördüğün bir PR telefonuna hiç
düşmezdi. Ayrı tutulunca iki kanal bağımsız çalışıyor.

---

## 9. Menü yapısı

Standart `NSMenu`. Raycast'in GitHub Profile komutuyla aynı görsel dil.

```
┌────────────────────────────────────────────────────┐
│  ⬤  Mert Cobanov  @cobanov                         │
├────────────────────────────────────────────────────┤
│  Pull Requests                                     │  ← sectionHeader
│  ⑂  herdrchat #55        Let the last row scr…     │  ← yeşil ikon = yeni
│  ⑂  instagram #3         fix: the virustotal a…    │
│  ⑂  awesome-diffusion #1 Add prompt-to-asset t…    │  ← gri ikon = görülmüş
│     6 tane daha…                                >  │
│  ✓  Mark All as Seen                               │
├────────────────────────────────────────────────────┤
│  Issues                                            │
│  ⊙  bucketmark #12       MCP endpoint returns 4…   │
│  ✓  Mark All as Seen                               │
├────────────────────────────────────────────────────┤
│  Review Requested                                  │
│  ⑂  someorg/thing #204   Refactor auth middlew…    │
│  ✓  Mark All as Seen                               │
├────────────────────────────────────────────────────┤
│  API                                               │
│  ◔  Rate Limit  4,911 / 5,000        58dk sonra    │
├────────────────────────────────────────────────────┤
│  🌐  Open Profile on GitHub                   ⌘O   │
│  ⚙   Configure                                ⌘,   │
│  ↻   Refresh                                  ⌘R   │
│  ⏻   Quit                                     ⌘Q   │
└────────────────────────────────────────────────────┘
```

### Görsel kurallar

**Bölüm başlıkları** — `NSMenuItem.sectionHeader(title:)`. macOS 14 ile gelen
API; hedef sürüm macOS 14+. (Geliştirme makinesi macOS 26.)

**Satır metni** — tek bir `NSAttributedString`, iki renk:

| Parça | Renk | Örnek |
|---|---|---|
| `repo #numara` | `.labelColor` | `herdrchat #55` |
| iki boşluk + başlık | `.secondaryLabelColor` | `Let the last row scr…` |

Sağa yaslama veya sütun hizalama yok — Raycast'teki "Followers 2,601"
görünümünün sırrı bu: değer, etiketin hemen devamı.

**Başlık kırpma** — 48 karakter, sonuna `…`. Kelime ortasından kesmemek için
son boşluğa kadar geri gidilir.

**İkonlar** — SF Symbols:

| Yer | Sembol | Renk |
|---|---|---|
| PR (yeni) | `arrow.trianglehead.pull` | `.systemGreen` |
| PR (görülmüş) | `arrow.trianglehead.pull` | `.secondaryLabelColor` |
| PR (taslak) | `arrow.trianglehead.pull` | `.tertiaryLabelColor` |
| Issue (yeni) | `smallcircle.filled.circle` | `.systemGreen` |
| Issue (görülmüş) | `smallcircle.filled.circle` | `.secondaryLabelColor` |
| Mark All as Seen | `checkmark.circle` | varsayılan |
| Rate Limit | `gauge.with.needle` | duruma göre (aşağıda) |
| Open Profile | `globe` | varsayılan |
| Configure | `gearshape` | varsayılan |
| Refresh | `arrow.clockwise` | varsayılan |
| Quit | `power` | varsayılan |

Renklendirme `NSImage.withSymbolConfiguration(.init(paletteColors:))` ile.
Ayrı bir "okunmadı" noktası çizilmiyor — ikonun rengi bu işi görüyor.

**Taşma** — bölüm başına `maxRowsPerSection` (varsayılan 5) satır doğrudan;
fazlası "N tane daha…" satırının alt menüsünde, aynı biçimde.

**Boş bölüm** — hiç öğe yoksa bölüm başlığı dahil tamamen gizlenir.

**Rate Limit satırı** — `4,911 / 5,000` biçiminde, yanında sıfırlanmaya kalan
süre. Kalan %10'un altındaysa ikon `.systemRed`, %25'in altındaysa
`.systemOrange`. Bu satır tıklanabilir değil.

**Klavye kısayolları** — sadece alt bloktaki dört satırda (⌘O, ⌘,, ⌘R, ⌘Q).

### Menü çubuğu öğesi

`menuBarStyle: "avatar"` (varsayılan): dairesel avatar (16×16) + toplam
görülmemiş sayısı. Sayı sıfırsa sadece avatar.

`menuBarStyle: "icon"`: avatar yerine `arrow.trianglehead.pull` sembolü.

Avatar `viewer.avatarUrl`'den bir kez indirilip
`~/Library/Application Support/GHBar/avatar.png` içine yazılır. Sonraki
açılışlarda diskten okunur; URL değişirse yeniden indirilir. İndirme başarısız
olursa `"icon"` stiline düşülür.

### Tıklama davranışı

| Satır | Davranış |
|---|---|
| Profil başlığı | `github.com/<login>` açılır |
| PR / issue satırı | URL tarayıcıda açılır **ve** görülmüş işaretlenir |
| `N tane daha…` | Alt menü açılır (tıklama gerektirmez) |
| Mark All as Seen | O bölümdeki tüm öğeler görülmüş işaretlenir, menü yenilenir |
| Open Profile on GitHub | `github.com/<login>` açılır |
| Configure | Ayar dosyası editörde açılır |
| Refresh | Hemen yenileme tetikler |
| Quit | Uygulama kapanır |

---

## 10. Yenileme tetikleyicileri

| Tetik | Not |
|---|---|
| Zamanlayıcı | `refreshMinutes` (varsayılan 5) |
| Menü açılışı | `NSMenuDelegate.menuWillOpen`; son yenilemeden 30 sn geçtiyse |
| Uykudan uyanma | `NSWorkspace.didWakeNotification` |
| Ağın geri gelmesi | `NWPathMonitor` durumu `satisfied` olunca |
| Ayar dosyası değişimi | `DispatchSource` dosya izleyici |
| Elle | ⌘R |

Uykudan uyanma tetiği önemli: onsuz kapağı açtığında saatler öncesinin verisini
görürsün ve bunun bayat olduğunu anlamanın bir yolu olmaz.

Menü açılışında 30 saniyelik alt sınır var — menüyü art arda açıp kapatmak
gereksiz istek üretmesin diye.

---

## 11. Bildirimler

`UNUserNotificationCenter` kullanılır. `notifications: false` ise atlanır.

- **Ne zaman:** yenileme sonrası, `seen.json`'da olmayan **ve** önceki
  yenilemede de görülmemiş yeni öğeler için.
- **İlk çalıştırma:** hiç bildirim atılmaz; mevcut her şey "başlangıç durumu"
  olarak kaydedilir. Aksi halde ilk açılışta 43 bildirim yağardı.
- **Toplu gelme:** yeni öğe sayısı 5'i aşarsa tek bir özet bildirimi
  ("Repolarına 12 yeni PR geldi") gönderilir.
- **Tıklama:** bildirime tıklamak öğeyi tarayıcıda açar ve görülmüş işaretler.
  Özet bildirimine tıklamak menüyü açar.

**İzin.** İlk çalıştırmada `requestAuthorization` çağrılır. Kullanıcı reddederse
uygulama bildirimsiz çalışmaya devam eder; her açılışta tekrar sormaz.

**Risk ve yedek plan:** `UNUserNotificationCenter` imzalı bir uygulama paketi
ister. Ad-hoc imza (`codesign -s -`) yeterli olmalı, ama garanti değil. İlk
çalışan sürümde bu test edilecek; çalışmazsa yedek yol
`osascript -e 'display notification …'` — çirkin ama kesin çalışıyor ve
davranışsal olarak eşdeğer.

---

## 12. Hata durumları

Hiçbir hata sessizce yutulmaz; hepsi menüde görünür bir satıra dönüşür. Boş
liste göstermek en kötü sonuç — "iş yok" ile "bakamadım" ayırt edilemez hale gelir.

| Durum | Davranış |
|---|---|
| `gh` bulunamadı | Menüde `⚠ gh bulunamadı` + tıklayınca kurulum sayfası. Konum sırası: `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, `PATH` |
| `gh` oturumu yok | `⚠ GitHub oturumu yok — gh auth login` |
| Ağ yok | `⚠ Bağlantı yok · son güncelleme 14:22`, eski liste gösterilmeye devam eder |
| GraphQL hatası | `⚠ GitHub hatası` + alt menüde mesaj |
| Kota bitti | `⚠ API kotası doldu · 14:58'de sıfırlanır`, yenileme sıfırlanma anına kadar duraklatılır |
| Sonuç 100'e dayandı | Bölüm sonunda `⚠ 100+ sonuç — exclude listesine repo ekle` |
| Ayar dosyası bozuk | `⚠ config.json okunamadı` + tıklayınca dosyayı açar; varsayılanlarla devam |
| `seen.json` bozuk | Sessizce sıfırlanır (yan etkisi sadece bir kerelik fazla bildirim), log'a yazılır |

**Yeniden deneme.** Ağ/GitHub hatasında üstel geri çekilme: 1, 2, 4, 8 dakika,
en fazla 15 dakika. Başarılı yenilemede sıfırlanır.

---

## 13. Paketleme

Swift Package Manager + `Makefile`.

```
make          # derle
make bundle   # GHBar.app olustur
make install  # /Applications'a kopyala
make test     # testleri calistir
```

`make bundle` şunları yapar:

1. `swift build -c release`
2. `GHBar.app/Contents/MacOS/` içine ikiliyi kopyalar
3. `Info.plist` yazar — kritik alan **`LSUIElement = true`**: bu bayrak
   uygulamanın Dock'ta ikon göstermemesini ve uygulama değiştiricide
   çıkmamasını sağlar. Menü çubuğu uygulamaları için şart.
4. `Resources/` içine `query.graphql` kopyalar
5. `codesign --force --deep --sign -` ile ad-hoc imzalar

**Neden Xcode projesi değil:** `.xcodeproj` devasa bir XML dosyası; git'te takip
etmesi ve elle düzenlemesi zahmetli. SPM + Makefile düz metin ve tamamen
komut satırından sürülebilir.

**Bundle identifier:** `run.cobanov.ghbar`

**Girişte başlatma:** `SMAppService.mainApp.register()`. Menüde "Login'de
Başlat" anahtarı yok — kurulumdan sonra bir kez `make install` yeterli;
kayıt ilk çalıştırmada otomatik yapılır ve `config.json`'daki bir alanla
değil, sistem Ayarlar > Genel > Giriş Öğeleri'nden yönetilir.

---

## 14. Test stratejisi

Test edilecekler saf fonksiyonlar — ağ, dosya sistemi ve UI dışarıda tutuluyor.

**`FilteringTests`**
- Bot elemesi: `__typename == "Bot"` yakalanıyor
- Bot elemesi: `login` `[bot]` ile bitiyorsa yakalanıyor
- `showBots: true` iken botlar geçiyor
- `author == null` olan öğe atılıyor
- Aynı PR hem `prs` hem `review` içindeyse sadece Review Requested'da çıkıyor
- Sıralama: en yeni üstte

**`ParsingTests`**
- Gerçek GraphQL cevabı (diske kaydedilmiş örnek) doğru çözülüyor
- Eksik alanlar (`author: null`, `name: null`) çökmeye yol açmıyor
- Boş sonuç kümesi doğru işleniyor

**`FormattingTests`**
- Yaş: 45 dk → `45dk`, 3 saat → `3sa`, 2 gün → `2g`, 90 gün → `3ay`
- Sınır değerler: 59 dk → `59dk`, 60 dk → `1sa`
- Başlık kırpma: 48 karakterden uzun olan kelime ortasından kesilmiyor
- Sayı biçimi: `4911` → `4,911`

**`SeenStoreTests`**
- İşaretle → oku turu
- Artık listede olmayan URL'ler temizleniyor
- Bozuk dosya sıfırlanıyor, çökmüyor
- İlk çalıştırma: her şey görülmüş sayılıyor, bildirim listesi boş

**`ConfigTests`**
- Sorgu metni üretimi: `owners` + `exclude` → beklenen sorgu metni
- `exclude` girdisi `/` içermiyorsa ilk owner ile birleşiyor
- Bozuk JSON → varsayılanlar + hata bayrağı

Menü çizimi ve `gh` alt süreci test edilmiyor — maliyeti değmiyor, elle
doğrulanacak.

---

## 15. Riskler

| Risk | Etki | Karşılık |
|---|---|---|
| Ad-hoc imza ile bildirim çalışmayabilir | Orta | `osascript` yedeği (§11) |
| `.app` içinde `PATH` boş, `gh` bulunamaz | Yüksek | Tam yol denemesi + görünür hata (§12) |
| GitHub arama 100 ile sınırlı | Düşük | Dışlama sorgu içinde (§5) + uyarı satırı |
| `NSMenuItem.sectionHeader` macOS 14+ | Düşük | Hedef sürüm macOS 14; geliştirme makinesi macOS 26 |
| `gh` sürümü değişir, çıktı bozulur | Düşük | Çözümleme hatası menüde görünür |

---

## 16. Ölçümler (2026-08-18)

Tasarım kararlarının dayandığı gerçek sayılar:

| Ölçüm | Değer |
|---|---|
| GraphQL sorgu maliyeti | 1 puan (üç arama + profil + kota dahil) |
| Saatlik kota | 5.000 |
| 5 dk'da bir yenilemenin saatlik maliyeti | 12 puan (kotanın %0,24'ü) |
| Ham açık PR (başkalarının) | 64 |
| Bot PR | 3 (dependabot) |
| `team-cobanov` reposundaki PR | 50 |
| Filtre sonrası PR | **11** |
| Ham açık issue (başkalarının) | 32 |
| Bot issue | 0 |
| `paul-graham-turkce` reposundaki issue | 18 |
| Review istenen PR | 0 |
