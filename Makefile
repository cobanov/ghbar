# GHBar — derleme, paketleme, imzalama, noterleme, yayin
#
#   make            derle
#   make bundle     GHBar.app olustur (imzasiz)
#   make sign       Developer ID ile imzala
#   make notarize   Apple'a noterlet ve staple et
#   make zip        dagitilabilir arsiv
#   make release    yukaridakilerin hepsi, sirayla
#   make install    /Applications'a kur ve baslat
#   make test       testler
#   make clean

VERSION     := 0.1.0
APP         := GHBar
BUNDLE_ID   := run.cobanov.ghbar
MIN_MACOS   := 14.0

BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP).app
CONTENTS    := $(APP_BUNDLE)/Contents
BINARY      := .build/release/$(APP)
ICONSET     := $(BUILD_DIR)/$(APP).iconset
ICNS        := $(BUILD_DIR)/$(APP).icns
ZIP         := $(BUILD_DIR)/$(APP)-$(VERSION)-macos.zip

# Imzalama kimligi. security find-identity -v -p codesigning ile listelenir.
SIGN_ID     := Developer ID Application: AHMET MERT COBANOGLU (6U58AKY6F8)
# xcrun notarytool store-credentials ile kaydedilen profil adi.
NOTARY_PROFILE := ghbar

.PHONY: all build test icon bundle sign notarize zip release install clean run

all: build

build:
	swift build -c release

test:
	swift test

run:
	swift run $(APP)

# --- Ikon ---------------------------------------------------------------
# AppKit ile programatik ciziliyor; harici cizim araci gerekmiyor.

icon: $(ICNS)

$(ICNS): Tools/makeicon.swift
	@mkdir -p $(BUILD_DIR)
	swift Tools/makeicon.swift $(ICONSET)
	iconutil -c icns $(ICONSET) -o $(ICNS)

# --- Paket --------------------------------------------------------------

bundle: build $(ICNS)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BINARY) $(CONTENTS)/MacOS/$(APP)
	cp $(ICNS) $(CONTENTS)/Resources/$(APP).icns
	@printf '%s' 'APPL????' > $(CONTENTS)/PkgInfo
	@/usr/libexec/PlistBuddy -c "Clear dict" \
	  -c "Add :CFBundleName string $(APP)" \
	  -c "Add :CFBundleDisplayName string $(APP)" \
	  -c "Add :CFBundleIdentifier string $(BUNDLE_ID)" \
	  -c "Add :CFBundleExecutable string $(APP)" \
	  -c "Add :CFBundleIconFile string $(APP)" \
	  -c "Add :CFBundlePackageType string APPL" \
	  -c "Add :CFBundleShortVersionString string $(VERSION)" \
	  -c "Add :CFBundleVersion string $(VERSION)" \
	  -c "Add :LSMinimumSystemVersion string $(MIN_MACOS)" \
	  -c "Add :LSUIElement bool true" \
	  -c "Add :NSHumanReadableCopyright string 'Copyright © 2026 Mert Cobanov. MIT License.'" \
	  -c "Add :NSSupportsAutomaticTermination bool false" \
	  -c "Add :NSSupportsSuddenTermination bool false" \
	  $(CONTENTS)/Info.plist >/dev/null
	@echo "paketlendi: $(APP_BUNDLE)"

# LSUIElement=true: Dock'ta ikon gostermez, uygulama degistiricide cikmaz.
# Menu cubugu uygulamalari icin sart.

# --- Imzalama -----------------------------------------------------------
# --options runtime (hardened runtime) noterleme icin zorunlu.
# --timestamp guvenilir zaman damgasi ekler; sertifika suresi dolsa bile
# eski imzalar gecerli kalir.

sign: bundle
	codesign --force --options runtime --timestamp \
	  --sign "$(SIGN_ID)" \
	  $(CONTENTS)/MacOS/$(APP)
	codesign --force --options runtime --timestamp \
	  --sign "$(SIGN_ID)" \
	  $(APP_BUNDLE)
	@echo "--- dogrulama ---"
	codesign --verify --deep --strict --verbose=2 $(APP_BUNDLE)

# --- Noterleme ----------------------------------------------------------
# Apple'a gonderilir, taranir, sonra bilet uygulamaya "staple" edilir.
# Staple sayesinde kullanicinin makinesi cevrimdisiyken bile dogrulanir.

notarize: sign zip
	xcrun notarytool submit $(ZIP) \
	  --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP_BUNDLE)
	@rm -f $(ZIP)
	$(MAKE) zip
	@echo "--- Gatekeeper degerlendirmesi ---"
	spctl --assess --type execute --verbose=4 $(APP_BUNDLE)

zip:
	@rm -f $(ZIP)
	cd $(BUILD_DIR) && ditto -c -k --keepParent --sequesterRsrc $(APP).app $(notdir $(ZIP))
	@echo "arsiv: $(ZIP)"
	@shasum -a 256 $(ZIP)

release: test notarize
	@echo
	@echo "yayina hazir: $(ZIP)"
	@shasum -a 256 $(ZIP)
	@echo
	@echo "sonraki adim: make publish"

# --- Yayin --------------------------------------------------------------
# Noterlenmis arsivi GitHub Release olarak yayinlar ve Homebrew cask'ini
# yeni surum + sha256 ile gunceller.

publish:
	@test -f $(ZIP) || { echo "$(ZIP) yok — once 'make notarize' calistir"; exit 1; }
	@echo "--- noterleme dogrulamasi ---"
	@spctl --assess --type execute --verbose=4 $(APP_BUNDLE) 2>&1 | grep -q accepted \
	  || { echo "HATA: paket Gatekeeper'dan gecmiyor, yayinlanmayacak"; exit 1; }
	gh release create v$(VERSION) $(ZIP) \
	  --title "GHBar $(VERSION)" \
	  --notes-file docs/release-notes/v$(VERSION).md \
	  --repo cobanov/ghbar
	@echo
	@echo "cask icin sha256:"
	@shasum -a 256 $(ZIP) | cut -d' ' -f1

# --- Kurulum ------------------------------------------------------------

install: bundle
	@pkill -x $(APP) 2>/dev/null || true
	@rm -rf /Applications/$(APP).app
	cp -R $(APP_BUNDLE) /Applications/
	@echo "kuruldu: /Applications/$(APP).app"
	open /Applications/$(APP).app

clean:
	rm -rf $(BUILD_DIR) .build
