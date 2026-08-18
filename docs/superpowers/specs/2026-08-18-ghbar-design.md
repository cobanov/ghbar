# GHBar — Tasarım Dokümanı

**Tarih:** 2026-08-18
**Durum:** Onaylandı, uygulamaya hazır
**Kitle:** Genel — açık kaynak, Homebrew ve GitHub Releases üzerinden dağıtılacak

> **Revizyon notu.** Bu dokümanın ilk hali kişisel bir araç için yazılmıştı ve
> yazarın makinesine ait varsayımlar taşıyordu (`gh` kurulu, ayarlar bir JSON
> dosyası, `owners: ["cobanov"]`, ad-hoc imza). Uygulama herkese dağıtılacağı
> için doküman baştan yazıldı. Değişenler §17'de listeli.

---

## 1. Amaç

Repolarına başkaları tarafından açılan pull request ve issue'ları, ayrıca
senden review istenen PR'ları macOS menü çubuğundan tek bakışta görebilmek.

Sorun şu: GitHub'ın bildirim kutusu her şeyi karıştırıyor — kendi açtığın
PR'ın yorumu, abone olduğun bir konu, CI sonucu, hepsi aynı listede. "Benim
repoma biri katkı yolladı" sinyali bu gürültünün içinde kayboluyor. GHBar
sadece o sinyali gösteriyor ve menü çubuğunda tutuyor.

### Başarı ölçütü

- Menü çubuğunda bekleyen iş sayısı görünüyor.
- Menüyü açmak listeyi gösteriyor; bir satıra tıklamak GitHub'da açıyor.
- Yeni bir PR/issue geldiğinde macOS bildirimi çıkıyor.
- İlk açılışta kullanıcı hiçbir şey yapılandırmadan çalışıyor.

---

## 2. Kapsam dışı

Bilinçli olarak yapılmayacaklar:

- PR merge etme, kapatma, yorum yazma — GHBar salt okunur bir gösterge.
- Diff görüntüleme.
- Birden fazla GitHub hesabıyla eşzamanlı oturum.
- GitHub Enterprise Server (yalnızca github.com).
- Mention / assigned / abone olunan konular — bunlar GitHub bildirim kutusunun
  işi; GHBar'ın ayrışma sebebi tam olarak onları göstermemek.
- Otomatik güncelleme çatısı (Sparkle). Yerine §14'teki hafif sürüm kontrolü.
- İngilizce dışında dil (v1). Metinler String Catalog'a konacak, çeviri sonra.

---

## 3. Mimari

| Dosya | Sorumluluk |
|---|---|
| `GHBarApp.swift` | `App` gövdesi, `Settings` sahnesi, `MenuBarExtra` yerine `NSStatusItem` kurulumu |
| `AppDelegate.swift` | Durum çubuğu öğesi, yenileme döngüsü, tetikleyiciler |
| `AppState.swift` | Gözlemlenebilir durum: öğeler, hata, son yenileme, kota |
| `TokenProvider.swift` | Token bulur: Keychain → `gh` → OAuth. §5 |
| `DeviceFlowAuth.swift` | GitHub OAuth device flow |
| `Keychain.swift` | Token'ı Keychain'e yazar/okur |
| `GitHubClient.swift` | GraphQL isteğini atar, cevabı çözer |
| `Query.swift` | Ayarlardan arama metinlerini üretir |
| `Models.swift` | `Item`, `Section`, `RateLimit`, `Viewer` |
| `Filtering.swift` | Bot elemesi, repo filtresi, sıralama, gruplama |
| `SeenStore.swift` | Görülme durumu |
| `MenuBuilder.swift` | Veriden `NSMenu` üretir |
| `Notifier.swift` | macOS bildirimleri |
| `Formatting.swift` | Yaş metni, başlık kırpma, sayı biçimi |
| `UpdateChecker.swift` | GitHub Releases'ten yeni sürüm kontrolü |
| `Settings/SettingsView.swift` | Üç sekmeli ayarlar penceresi |
| `Settings/AccountsPane.swift` | İzlenecek hesap/organizasyonlar |
| `Settings/RepositoriesPane.swift` | Repo listesi + tersine çeviren kutucuk |
| `Settings/GeneralPane.swift` | Yenileme, bildirim, giriş, görünüm |
| `Settings/Defaults+Keys.swift` | Tüm ayar anahtarları tek yerde |
| `Onboarding/WelcomeView.swift` | İlk açılış / giriş ekranı |

**Bağımlılık yönü tek taraflı.** `AppDelegate` üsttedir; `MenuBuilder` ağ
bilmez, `GitHubClient` menü bilmez, `Filtering`/`Formatting`/`Query` saf
fonksiyonlardır (girdi → çıktı, yan etki yok). Testler bu üçüne ve
`SeenStore`'a odaklanır.

### Bağımlılıklar

Tek harici paket:

- **`sindresorhus/Defaults`** — tip güvenli `UserDefaults` sarmalayıcısı.
  Gerekçe: ayarlarımızda `[String]` dizileri var (hesaplar, repolar) ve
  SwiftUI'ın yerleşik `@AppStorage`'ı dizi desteklemiyor; elle JSON kodlamak
  gerekirdi. `Defaults` bunu `@Default` özellik sarmalayıcısıyla veriyor.

Bilinçli olarak **alınmayanlar**:

| Paket | Neden alınmadı |
|---|---|
| `sindresorhus/Settings` | SwiftUI'ın yerleşik `Settings { }` sahnesi 3 panel için yeterli; pencere, ⌘, kısayolu ve sekme şeridi hazır geliyor |
| `LaunchAtLogin-Modern` | `SMAppService.mainApp.register()` doğrudan ~10 satır |
| `Sparkle` | v1 için fazla (appcast XML + EdDSA anahtarı + barındırma). Yerine §14'teki hafif kontrol |

---

## 4. Veri akışı

```
zamanlayıcı ─┐
menü açılışı ─┼─→ refresh()
uyanma       ─┤
⌘R           ─┘
                  │
                  ▼
          TokenProvider.token()      ← Keychain / gh / OAuth
                  │
                  ▼
          Query.build(settings)      ← Defaults
                  │
                  ▼
          GitHubClient.fetch()       ← api.github.com/graphql
                  │
                  ▼
          Filtering.process()        ← bot elemesi, repo filtresi, gruplama
                  │
                  ├──→ SeenStore.diff() → yeni olanlar → Notifier
                  ├──→ AppState.knownRepos  (Ayarlar > Repositories bunu okur)
                  │
                  ▼
          MenuBuilder.build()        → NSStatusItem.menu
```

Yenileme arka planda, menü çizimi ana iş parçacığında. Yenileme sürerken menü
açılırsa eski veri gösterilir — boş menü göstermek daha kötü olurdu. Aynı anda
ikinci yenileme başlatılmaz.

---

## 5. Kimlik doğrulama

Token üç kaynaktan gelebilir; sıra önemli:

**1. Keychain.** Daha önce OAuth ile giriş yapıldıysa token orada. Bu birinci
sırada çünkü kullanıcı açıkça bir hesap seçmişse o seçim `gh`'ın hesabını
ezmeli.

**2. `gh auth token`.** `gh` kurulu ve giriş yapılmışsa token oradan alınır ve
kullanıcı hiç giriş ekranı görmez. Geliştirici kitlesi için sıfır sürtünme.

Aranacak konumlar, sırayla: `/opt/homebrew/bin/gh` (Apple Silicon),
`/usr/local/bin/gh` (Intel), `PATH`. **Uyarı:** `.app` içinden başlatılan bir
süreç kabuk ortamını miras almaz — `PATH` neredeyse boştur. Bu yüzden tam yol
denemesi şart; sadece `PATH`'e güvenmek çoğu makinede sessizce başarısız olur.

`gh` token'ı bir yan etki taşır: uygulama `gh`'ın verdiği kapsamları (`repo`,
`read:org`, `gist`, `workflow`) devralır. Bizim ihtiyacımız bunun alt kümesi,
sorun değil.

**3. OAuth device flow.** İkisi de yoksa hoş geldin ekranı çıkar.

```
POST https://github.com/login/device/code
     client_id, scope=repo read:org
  → user_code ("WDJB-MJHT"), verification_uri, device_code, interval

Ekranda kod gösterilir + "Open GitHub" düğmesi
Arka planda POST https://github.com/login/oauth/access_token yoklanır
  → access_token → Keychain
```

**Device flow neden?** Klasik web akışı bir `client_secret` ister; dağıtılan
bir uygulamada bu sır kullanıcının diskinde durur, yani sır değildir. Device
flow secret istemez — tam olarak bu durum için tasarlanmış.

**Kapsamlar.** Varsayılan `repo read:org`. `repo` özel repolardaki PR/issue'ları
görmek için, `read:org` organizasyon repoları için. Hoş geldin ekranında
"yalnızca herkese açık repolar" seçeneği de sunulur (kapsamsız token) —
kapsamların ne işe yaradığı orada bir cümleyle açıklanır.

**Depolama.** Keychain, `kSecClassGenericPassword`, service `run.cobanov.ghbar`,
account = GitHub login. Token asla `UserDefaults`'a veya diske düz metin
yazılmaz.

**Çıkış.** Ayarlar > Accounts içinde "Sign Out": Keychain kaydını siler,
`seen.json`'ı temizler, hoş geldin ekranına döner.

**Token geçersizleşirse.** GraphQL `401` dönerse token silinir ve menüde
"Sign in again" satırı gösterilir. Sessizce boş liste gösterilmez.

---

## 6. GitHub sorgusu

Tek GraphQL isteği; üç arama, profil ve kota birlikte.

**Doğrulandı (2026-08-18):** çalışıyor, toplam maliyet **1 puan**.

```graphql
query($prs: String!, $issues: String!, $review: String!, $first: Int!) {
  viewer {
    login name avatarUrl
    organizations(first: 50) { nodes { login } }
  }

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

`viewer.organizations` ilk açılışta Ayarlar > Accounts listesini doldurmak için;
her yenilemede geliyor ki kullanıcı yeni bir organizasyona katıldığında listede
belirsin.

`first` = **100** (GitHub aramanın üst sınırı). Sayfalama yok. Sonuç 100'e
dayanırsa menüde uyarı satırı (§13).

### Arama metinlerinin üretimi

`Query.build()` ayarlardan üç metin üretir. `accounts = [alice]`,
`repoList = [alice/noisy]`, `repoListIsAllowList = false` için:

```
prs    = "is:pr is:open user:alice -author:@me -repo:alice/noisy"
issues = "is:issue is:open user:alice -author:@me -repo:alice/noisy"
review = "is:pr is:open review-requested:@me"
```

Kurallar:

- Her hesap bir `user:<hesap>` parçası olur.
- Kendi açtıklarını elemek için **`-author:@me`** eklenir. `@me`, GitHub
  aramada "token'ın sahibi" anlamına gelen kısayol; **doğrulandı** —
  `-author:@me` ile `-author:cobanov` birebir aynı sonucu veriyor.

  Bu, tasarımdaki bir sıra bağımlılığını kaldırıyor: sorgunun artık
  kullanıcının login'ini bilmesi gerekmiyor, dolayısıyla "önce `viewer`'ı
  çek, sonra sorguyu kur" diye iki aşamalı bir açılış gerekmiyor.
  Aynı sebeple `review` sorgusu `review-requested:@me` kullanır ve
  yapılandırılmamış ilk çalıştırmanın varsayılan hesabı `@me` olur —
  kullanıcı hiçbir şey ayarlamadan doğru sonucu görür.
- `repoListIsAllowList == false` → her repo `-repo:<owner>/<ad>` olur.
- `repoListIsAllowList == true` → her repo `repo:<owner>/<ad>` olur ve
  `user:` parçaları **kullanılmaz** (repo listesi kapsamı zaten belirliyor).
  Birden fazla `repo:` GitHub aramada VEYA anlamına gelir — doğrulandı.
- Repo girdisi `/` içermiyorsa ilk hesapla birleştirilir.
- Beyaz liste açık ama liste boşsa: hiçbir şey gösterilmez ve menüde
  "No repositories selected" satırı çıkar. Sessizce her şeyi göstermek,
  kullanıcının kurduğu filtreyi görmezden gelmek olurdu.
- `review` sorgusu hesap listesinden bağımsız; ama repo filtresi ona da
  uygulanır (aynı `-repo:` / `repo:` parçaları eklenir).

**Filtre neden sorgunun içinde?** Arama en fazla 100 sonuç veriyor. Ölçümde
64 PR'ın 50'si tek bir gürültülü repodan geliyordu. Filtreyi sonradan
uygulasaydık, o repo büyüdüğünde gerçek PR'lar 100'lük pencerenin dışında
kalıp **sessizce** kaybolurdu.

**Uzunluk sınırı.** GitHub'ın belgelediği 256 karakter sınırı REST/web
aramasına ait; GraphQL aramasında geçerli değil. **Ölçüldü:** 3085 karakterlik
bir sorgu hatasız çalıştı ve en sondaki `-repo:` bile uygulandı. Yani uzun
filtre listeleri güvenli, istemci tarafında yedek filtreye gerek yok.
Yine de 4000 karakteri aşarsa uyarı verilir ve liste kırpılır.

---

## 7. Filtreleme ve gruplama

Sorgudan dönen sonuçlara istemci tarafında uygulanır:

1. **Bot elemesi.** `author.__typename == "Bot"` **veya** `author.login`
   `[bot]` ile bitiyorsa atılır. Ayarlarda "Show bot activity" açıksa atlanır.
   İki koşul birlikte gerekli: GitHub bazı botları `User` tipiyle döndürüyor,
   bazılarının login'i `[bot]` ekiyle geliyor.
2. **Yazarsız öğeler** (silinmiş hesap, `author == null`) atılır.
3. **Sıralama:** `createdAt` azalan.
4. **Bölümleme:** Pull Requests / Issues / Review Requested.
5. **Çakışma.** Aynı PR hem `prs` hem `review` içindeyse yalnızca **Review
   Requested**'da gösterilir — review istenmiş olmak daha güçlü bir sinyal.
6. **Repo gruplama.** Bir bölümde tek bir repodan `repoGroupThreshold`
   (varsayılan 3) taneden fazla öğe varsa, bunlar tek bir satıra toplanır ve
   alt menüde listelenir:

   ```
   📁 alice/translations            18 issues    >
   ```

   Gerekçe: tek bir gürültülü repo bir bölümü boğduğunda kullanıcının ilk
   içgüdüsü onu tamamen dışlamak oluyor — ama o zaman oradan gelen gerçek bir
   katkıyı da kaçırıyor. Gruplama gürültüyü tek satıra indiriyor, hiçbir şeyi
   gizlemeden. Grup içinde okunmamış varsa satır vurgulanır.

**Bot elemesi neden istemci tarafında?** GitHub aramada "bot değil" diye genel
bir nitelik yok; tek tek `-author:app/dependabot` yazmak gerekir ve yeni bir
bot çıktığında sessizce sızar. `__typename` her yazar için bedava geliyor.

---

## 8. Ayarlar

**Depolama:** `UserDefaults` (`run.cobanov.ghbar`), `sindresorhus/Defaults` ile.
JSON dosyası yok — indiren birine "şu dosyayı elle düzenle" denemez.

**Pencere:** SwiftUI'ın yerleşik `Settings { }` sahnesi, üç sekme. Pencere
yönetimi, ⌘, kısayolu ve üst sekme şeridi bedavaya geliyor.

### Accounts sekmesi

- Oturum açan kullanıcı: avatar, ad, `@login`, "Sign Out" düğmesi.
- **Watched accounts** — kutucuklu liste. Oturum sahibinin kendi login'i ve
  `viewer.organizations`'tan gelen organizasyonlar otomatik listelenir.
  Varsayılan: yalnızca kendi login'i işaretli. Organizasyonlar isteğe bağlı —
  hepsini varsayılan açmak, 300 repoluk bir organizasyona üye olan birinin
  ilk açılışta boğulması demek olurdu.
- Listede olmayan bir hesap/organizasyon elle eklenebilir (`+` düğmesi).

### Repositories sekmesi

```
┌──────────────────────────────────────────────────┐
│  ☑ alice/webapp                      3 items     │
│  ☑ alice/cli-tool                    1 item      │
│  ☐ alice/translations               18 items     │
│  ☑ acme/backend                      2 items     │
│                                                  │
│  [ + ] [ − ]     ☐ Watch only the listed repos   │
│                                                  │
│  Repositories appear here as GHBar sees activity │
│  in them. Uncheck one to stop showing its items. │
└──────────────────────────────────────────────────┘
```

Liste, son yenilemelerde **gerçekten öğe üretmiş** repolardan doluyor
(`AppState.knownRepos`, diskte saklanır). Kullanıcı repo adını elle yazmak
zorunda değil — yazım hatası sessizce hiçbir şeyi filtrelemez, bu kötü bir
hata türü. `+` ile elle de eklenebilir (henüz görülmemiş bir repoyu önden
elemek için).

**"Watch only the listed repos" kutucuğu** listenin anlamını tersine çevirir:
kapalıyken işaretsizler dışlanır (kara liste), açıkken yalnızca işaretliler
gösterilir (beyaz liste).

> Bu kalıp Maccy'nin "Ignore Applications" panelinden alındı
> (`ignoreAllAppsExceptListed`). İki ayrı liste tutmaya göre üstünlüğü: bakılacak
> tek yer var, hangisinin kazandığı sorusu doğmuyor ve anlam kutucuğun yanındaki
> yazıda görünüyor.

Liste düzenleme `ControlGroup` içinde `+`/`−` düğmeleri ve `onDeleteCommand`
ile — macOS'un standart kalıbı.

### General sekmesi

| Ayar | Tip | Varsayılan |
|---|---|---|
| Refresh every | Seçim: 1/5/15/30/60 dk | 5 dk |
| Show notifications | Kutucuk | açık |
| Show bot activity | Kutucuk | kapalı |
| Show drafts | Kutucuk | açık |
| Menu bar shows | Seçim: Avatar + count / Icon + count / Icon only | Avatar + count |
| Group repos with more than | Seçim: 3/5/10/never | 3 |
| Launch at login | Kutucuk (`SMAppService`) | kapalı |
| Check for Updates | Düğme | — |

Ayar değişimi `Defaults` yayınları üzerinden anında yenileme tetikler.

---

## 9. Görülme durumu

**Konum:** `~/Library/Application Support/GHBar/seen.json`

```jsonc
{ "version": 1,
  "seen": { "https://github.com/alice/webapp/pull/55": "2026-08-18T11:29:00Z" } }
```

Anahtar öğenin URL'i (kalıcı, benzersiz), değer görüldüğü an.

**Görülmüş sayılma anları:** satıra tıklama, bölümdeki "Mark All as Seen",
bildirime tıklama.

**Temizlik.** Her yenilemede, artık sonuçlarda olmayan URL'ler silinir; yoksa
dosya sonsuza kadar büyür.

**İlk çalıştırma.** Mevcut her şey "görülmüş" kaydedilir ve hiç bildirim
atılmaz. Aksi halde uygulamayı kuran biri ilk saniyede onlarca bildirimle
karşılaşırdı.

---

## 10. Menü

Standart `NSMenu`. Arayüz dili İngilizce.

```
menü çubuğu:   ⬤ 14
┌────────────────────────────────────────────────────┐
│  ⬤  Alice Smith  @alice                            │
├────────────────────────────────────────────────────┤
│  Pull Requests                                     │
│  ⑂  webapp #55           Fix the floating tab ba…  │
│  ⑂  cli-tool #3          Handle empty config fi…   │
│  ⑂  acme/backend #204    Refactor auth middlewa…   │
│     6 more…                                     >  │
│  ✓  Mark All as Seen                               │
├────────────────────────────────────────────────────┤
│  Issues                                            │
│  ⊙  webapp #12           Crash on cold start       │
│  📁 translations                 18 issues      >  │
│  ✓  Mark All as Seen                               │
├────────────────────────────────────────────────────┤
│  Review Requested                                  │
│  ⑂  acme/api #77         Add rate limiting         │
│  ✓  Mark All as Seen                               │
├────────────────────────────────────────────────────┤
│  API                                               │
│  ◔  Rate Limit  4,911 / 5,000          resets 58m  │
├────────────────────────────────────────────────────┤
│  🌐  Open GitHub                              ⌘O   │
│  ⚙   Settings…                                ⌘,   │
│  ↻   Refresh                                  ⌘R   │
│  ⏻   Quit GHBar                               ⌘Q   │
└────────────────────────────────────────────────────┘
```

### Görsel kurallar

**Bölüm başlıkları** — `NSMenuItem.sectionHeader(title:)` (macOS 14+).

**Satır metni** — tek `NSAttributedString`, iki renk:

| Parça | Renk | Örnek |
|---|---|---|
| `repo #numara` | `.labelColor` | `webapp #55` |
| iki boşluk + başlık | `.secondaryLabelColor` | `Fix the floating tab ba…` |

Sağa yaslama veya sütun hizalama yok. Raycast'in menülerindeki temizliğin
sebebi bu: değer, etiketin hemen devamı olarak akıyor.

**Repo adı** — izlenen tek hesap varsa yalnızca repo adı (`webapp #55`); birden
fazla hesap izleniyorsa tam ad (`acme/backend #204`). Tek hesaplı kullanıcıda
her satırda kendi adını tekrar görmek gereksiz gürültü.

**Başlık kırpma** — 48 karakter, kelime ortasından kesmemek için son boşluğa
kadar geri gidilir, sonuna `…`.

**İkonlar** (SF Symbols) ve renk kodu:

| Durum | Sembol | Renk |
|---|---|---|
| PR, okunmamış | `arrow.trianglehead.pull` | `.systemGreen` |
| PR, görülmüş | `arrow.trianglehead.pull` | `.secondaryLabelColor` |
| PR, taslak | `arrow.trianglehead.pull` | `.tertiaryLabelColor` |
| Issue, okunmamış | `smallcircle.filled.circle` | `.systemGreen` |
| Issue, görülmüş | `smallcircle.filled.circle` | `.secondaryLabelColor` |
| Repo grubu | `folder` | içinde okunmamış varsa yeşil |
| Mark All as Seen | `checkmark.circle` | varsayılan |
| Rate Limit | `gauge.with.needle` | duruma göre |

Ayrı bir "okunmadı" noktası çizilmiyor — ikon rengi bu işi görüyor.

**Taşma** — bölüm başına 5 satır doğrudan; fazlası "N more… >" alt menüsünde.
(Yukarıdaki çizim kısaltılmıştır; gerçekte taşma satırından önce 5 satır olur.)

**Boş bölüm** — tamamen gizlenir (başlık dahil).

**Rate Limit** — `4,911 / 5,000` + sıfırlanmaya kalan süre. Kalan %10'un
altında ikon kırmızı, %25'in altında turuncu. Tıklanabilir değil.

### Menü çubuğu öğesi

Varsayılan: dairesel avatar (16×16) + okunmamış sayısı. Sıfırsa yalnız avatar.
Diğer seçenekler: simge + sayı, yalnız simge.

Avatar `viewer.avatarUrl`'den bir kez indirilip
`~/Library/Application Support/GHBar/avatar.png`'ye yazılır; URL değişirse
yenilenir. İndirme başarısızsa simge stiline düşülür.

### Tıklama davranışı

| Satır | Davranış |
|---|---|
| Profil başlığı | `github.com/<login>` |
| PR / issue | URL açılır **ve** görülmüş işaretlenir |
| Repo grubu | Alt menü |
| Mark All as Seen | O bölüm görülmüş işaretlenir, menü yenilenir |
| Open GitHub | `github.com/<login>` |
| Settings… | Ayarlar penceresi |
| Refresh | Hemen yenileme |
| Quit GHBar | Çıkış |

---

## 11. İlk açılış

Token yoksa menü tıklanınca hoş geldin penceresi açılır:

```
┌──────────────────────────────────────────┐
│              ⑂  GHBar                    │
│                                          │
│   Pull requests and issues from your     │
│   repositories, in the menu bar.         │
│                                          │
│        [ Sign in with GitHub ]           │
│                                          │
│   ○ Include private repositories         │
│     Grants the "repo" scope. Turn off    │
│     to watch only public repositories.   │
└──────────────────────────────────────────┘
```

`gh` bulunup token alınabiliyorsa bu pencere **hiç görünmez** — uygulama
doğrudan çalışmaya başlar. Bu, geliştirici kitlesi için tasarlanmış bir
kısayol; kullanıcı isterse Ayarlar > Accounts'tan başka hesapla giriş yapabilir.

Giriş tamamlanınca ilk çekim yapılır, `owners` oturum sahibinin login'iyle
doldurulur, mevcut her şey görülmüş sayılır (§9).

---

## 12. Yenileme tetikleyicileri

| Tetik | Not |
|---|---|
| Zamanlayıcı | Ayarlardaki aralık (varsayılan 5 dk) |
| Menü açılışı | Son yenilemeden 30 sn geçtiyse |
| Uykudan uyanma | `NSWorkspace.didWakeNotification` |
| Ağın dönmesi | `NWPathMonitor` → `satisfied` |
| Ayar değişimi | `Defaults` yayını |
| Elle | ⌘R |

Uyanma tetiği önemli: onsuz kapağı açtığında saatler öncesinin verisini
görürsün ve bunun bayat olduğunu anlamanın yolu yoktur.

Menü açılışındaki 30 saniyelik alt sınır, menüyü art arda açıp kapatmanın
gereksiz istek üretmesini engeller.

---

## 13. Hata durumları

Hiçbir hata sessizce yutulmaz. Boş liste en kötü sonuç: "bekleyen iş yok" ile
"bakamadım" ayırt edilemez hale gelir ve kullanıcı ikincisini birincisi sanar.

| Durum | Menüde görünen |
|---|---|
| Token yok | `Sign in to GitHub…` → hoş geldin penceresi |
| Token geçersiz (401) | `Session expired — sign in again` |
| Ağ yok | `No connection · last updated 14:22`, eski liste durur |
| GraphQL hatası | `GitHub error` + alt menüde mesaj |
| Kota bitti | `Rate limit reached · resets 14:58`, yenileme o ana kadar durur |
| Sonuç 100'e dayandı | Bölüm sonunda `Showing first 100 — narrow your filters` |
| Beyaz liste boş | `No repositories selected` → Ayarlar'ı açar |
| Sorgu 4000 karakteri aştı | `Too many filters — some were dropped` |
| `seen.json` bozuk | Sessizce sıfırlanır (yan etkisi bir kerelik fazla bildirim), log'a yazılır |

**Yeniden deneme.** Ağ/GitHub hatasında üstel geri çekilme: 1, 2, 4, 8 dakika,
tavan 15 dakika. Başarılı yenilemede sıfırlanır.

---

## 14. Paketleme ve dağıtım

Swift Package Manager + `Makefile`.

```
make          # derle
make bundle   # GHBar.app olustur
make sign     # Developer ID ile imzala
make notarize # Apple'a noterlet, staple et
make dmg      # dagitilabilir .dmg
make test
```

**Bundle identifier:** `run.cobanov.ghbar`
**`LSUIElement = true`** — Dock'ta ikon göstermez. Menü çubuğu uygulamaları için şart.

### İmzalama ve noterleme

Başkasının Mac'inde açılabilmesi için **`Developer ID Application`**
sertifikası gerekiyor. Bu, App Store dışında dağıtılan Mac uygulamalarını
imzalayan tek sertifika tipi.

> **Ön koşul (kullanıcının yapması gereken):** Mevcut Apple Developer hesabında
> (`6U58AKY6F8`) şu an yalnızca `Apple Development` ve `Apple Distribution`
> sertifikaları var; ikisi de App Store/TestFlight içindir. developer.apple.com
> → Certificates → **Developer ID Application** oluşturulmalı. Ek ücret yok.
> Ayrıca noterleme için `xcrun notarytool store-credentials` ile bir
> uygulamaya özel parola saklanmalı. İkisi de tek seferlik.

Noterleme **hardened runtime** ister. Alt süreç çalıştırmak (`gh`) için ek bir
yetki gerekmiyor; sandbox kullanılmadığı için (App Store dışı) sorun yok.

### Dağıtım

- **Homebrew cask** — birincil yol: `brew install --cask ghbar`.
- **GitHub Releases** — noterlenmiş `.dmg`.

### Güncelleme kontrolü

Sparkle yerine hafif bir kontrol: `UpdateChecker` GitHub Releases API'sinden
en son etiketi okur, mevcut sürümden yeniyse menüde `Update available →`
satırı gösterir ve tıklayınca sürüm sayfasını açar. Günde bir kez, ayrıca
Ayarlar'daki düğmeyle elle.

Gerekçe: Homebrew ile kuranlar `brew upgrade` ile güncelleniyor; ama `.dmg`'yi
doğrudan indirenler sessizce eski sürümde kalır. Sparkle bunu tam çözer ama
appcast XML, EdDSA imza anahtarı ve barındırma getirir — v1 için fazla.
Sparkle sonradan, bu tasarımı bozmadan eklenebilir.

---

## 15. Test stratejisi

Saf fonksiyonlar test edilir; ağ, disk ve UI dışarıda.

**`QueryTests`**
- Tek hesap → beklenen üç metin
- Çok hesap → birden fazla `user:` parçası
- Kara liste → `-repo:` parçaları
- Beyaz liste → `repo:` parçaları, `user:` **yok**
- Beyaz liste boş → özel durum bayrağı
- `/` içermeyen repo girdisi ilk hesapla birleşiyor
- Uzunluk 4000'i aşarsa kırpma + bayrak

**`FilteringTests`**
- `__typename == "Bot"` eleniyor
- `login` `[bot]` ile bitiyorsa eleniyor
- "Show bots" açıkken geçiyor
- `author == null` atılıyor
- `prs` ∩ `review` → yalnız Review Requested
- Gruplama: eşiğin üstü toplanıyor, altı satır olarak kalıyor
- Grupta okunmamış varsa grup okunmamış işaretleniyor
- Sıralama: en yeni üstte

**`ParsingTests`**
- Kaydedilmiş gerçek GraphQL cevabı doğru çözülüyor
- Eksik alanlar (`author: null`, `name: null`) çökertmiyor
- Boş sonuç kümesi

**`FormattingTests`**
- 45 dk → `45m`, 3 saat → `3h`, 2 gün → `2d`, 90 gün → `3mo`
- Sınırlar: 59 dk → `59m`, 60 dk → `1h`
- Başlık kırpma kelime ortasından kesmiyor
- `4911` → `4,911`

**`SeenStoreTests`**
- İşaretle → oku
- Listede olmayan URL'ler temizleniyor
- Bozuk dosya sıfırlanıyor, çökmüyor
- İlk çalıştırma: her şey görülmüş, bildirim listesi boş

**`TokenProviderTests`**
- Sıra: Keychain → gh → yok
- `gh` bulunamadığında düzgün `nil`, çökmüyor

Menü çizimi, ayarlar penceresi, OAuth akışı ve `gh` alt süreci elle
doğrulanacak — otomatik test maliyeti değmiyor.

---

## 16. Riskler

| Risk | Etki | Karşılık |
|---|---|---|
| `Developer ID` sertifikası henüz yok | **Yüksek** — imzasız .app başkasında açılmaz | Dağıtımdan önce oluşturulacak (§14) |
| `.app` içinde `PATH` boş, `gh` bulunamaz | Yüksek | Tam yol denemesi + görünür hata (§5, §13) |
| Device flow için OAuth App gerekiyor | Orta | GitHub'da kayıt edilecek; client ID herkese açık olabilir, secret yok |
| Bildirimler imzalı uygulama ister | Orta | Developer ID imzasıyla çözülür; ad-hoc'ta `osascript` yedeği |
| GitHub arama 100 sınırı | Düşük | Filtre sorgu içinde + uyarı satırı |
| `NSMenuItem.sectionHeader` macOS 14+ | Düşük | Hedef sürüm macOS 14 |
| `gh` çıktı biçimi değişir | Düşük | Yalnızca `gh auth token` kullanılıyor, en durağan komut |

---

## 17. İlk taslaktan değişenler

| Konu | İlk hali (kişisel) | Şimdi (genel) |
|---|---|---|
| Kimlik doğrulama | Yalnızca `gh` | `gh` varsa o, yoksa OAuth device flow |
| Ayarlar | `~/.config/ghbar/config.json` | Üç sekmeli pencere, `UserDefaults` |
| Varsayılan hesap | `["cobanov"]` sabit | `viewer.login`'den otomatik |
| Varsayılan dışlama | `["team-cobanov"]` sabit | Boş |
| Repo filtresi | Yalnızca kara liste | Tek liste + tersine çeviren kutucuk |
| Arayüz dili | Türkçe/karışık | İngilizce |
| İmza | Ad-hoc | Developer ID + noterleme |
| Dağıtım | `make install` | Homebrew cask + Releases |
| Güncelleme | Yok | GitHub Releases kontrolü |
| Repo gruplama | Yok | Var (eşik 3) |
| İlk açılış | Yok | Hoş geldin / giriş ekranı |

---

## 18. Ölçümler (2026-08-18)

Tasarım kararlarının dayandığı gerçek sayılar. Ölçüm hesabı: `cobanov`,
81 herkese açık repo.

| Ölçüm | Değer |
|---|---|
| GraphQL sorgu maliyeti | **1 puan** (üç arama + profil + kota dahil) |
| Saatlik kota | 5.000 |
| 5 dk'da bir yenilemenin saatlik maliyeti | 12 puan (kotanın %0,24'ü) |
| Ham açık PR (başkalarının) | 64 |
| Bot PR | 3 |
| Tek bir gürültülü repodaki PR | 50 (%78) |
| Filtre sonrası PR | 11 |
| Ham açık issue (başkalarının) | 32 |
| Bot issue | 0 |
| Tek bir repodaki issue | 18 (%56) |
| `-repo:` niteleyicisi | çalışıyor (64 → 14) |
| Çoklu `repo:` | VEYA anlamında, çalışıyor |
| Sorgu uzunluk tavanı | **3085 karakterde hata yok**, en sondaki niteleyici bile uygulanıyor |
| `user:@me` / `-author:@me` / `review-requested:@me` | üçü de çalışıyor, login'i açıkça yazan sürümle **birebir aynı** sonuç |

Son iki satır önemli: filtreyi sorguya gömme kararı (§6) buna dayanıyor.
Belgelenen 256 karakter sınırı GraphQL aramasında geçerli değil.

---

## 19. Uygulama sırası

Bu, tek oturumda yazılacak bir uygulama değil. Dört aşamaya bölünüyor; her
aşamanın sonunda **çalışan bir şey** var, sonraki aşama onun üstüne biniyor.

**Aşama 1 — Çekirdek (çalışır menü).**
`gh` ile token, tek GraphQL sorgusu, filtreleme, `NSMenu`, görülme durumu.
Ayarlar yok (kod içinde varsayılanlar), OAuth yok, paketleme yok — `swift run`
ile çalışır. Bitince: menü çubuğunda gerçek veri görünüyor.

**Aşama 2 — Paketleme ve bildirimler.**
`Makefile`, `.app` paketi, `LSUIElement`, ad-hoc imza, `UNUserNotificationCenter`,
girişte başlatma. Bitince: kendi makinende kurulu, günlük kullanılabilir bir
uygulama. §16'daki iki bilinmez (ad-hoc imzayla bildirim, `.app` içinden `gh`)
burada test edilir.

**Aşama 3 — Ayarlar ve OAuth.**
`Defaults`, üç sekmeli ayarlar penceresi, repo listesi + tersine çeviren
kutucuk, device flow, Keychain, hoş geldin ekranı. Bitince: `gh` kurulu
olmayan birinde de çalışıyor. Genel kullanıma hazır.

**Aşama 4 — Dağıtım.**
`Developer ID` sertifikası, noterleme, `.dmg`, Homebrew cask, README, LICENSE,
uygulama ikonu, sürüm kontrolü. Bitince: `brew install --cask ghbar`.

Aşama 1 ve 2 kişisel araç olarak zaten değerli; 3 ve 4 onu dağıtılabilir hale
getiriyor. Aşama 2'den sonra durup bir süre kullanmak, 3'ü tasarlarken gerçek
kullanım bilgisiyle karar vermeyi sağlar.
