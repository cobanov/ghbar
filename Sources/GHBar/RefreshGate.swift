/// Ayni anda tek yenileme calissin, ama cakisan istekler kaybolmasin.
///
/// Devam eden yenileme eski ayarlarla baslamis olur. Cakisan istegi sessizce
/// dusurmek, ayar degisikligini bir sonraki zamanlayici turuna kadar
/// gorunmez birakiyordu: takili bir baglanti 15 saniye boyunca kapiyi kapali
/// tuttugu icin org secimi hicbir sey yapmamis gibi duruyordu.
struct RefreshGate {

    /// Menu "Refreshing…" satirini bu bayrakla gosteriyor.
    private(set) var isRunning = false
    private var queued = false

    /// Yenileme baslatilabiliyorsa true. Baslatilamiyorsa istek kuyruga girer.
    mutating func begin() -> Bool {
        guard !isRunning else {
            queued = true
            return false
        }
        isRunning = true
        return true
    }

    /// Calisan yenileme bitti. Bu sirada gelen istek varsa true doner ve
    /// cagiran yeni bir yenileme baslatir.
    mutating func finish() -> Bool {
        isRunning = false
        guard queued else { return false }
        queued = false
        return true
    }
}
