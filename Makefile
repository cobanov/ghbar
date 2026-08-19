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

VERSION     := 0.1.1
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

.PHONY: all build test icon bundle sign notarize zip release install clean run publish tap check build-mas bundle-mas sign-mas pkg

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
	  -c "Add :LSApplicationCategoryType string public.app-category.developer-tools" \
	  -c "Add :ITSAppUsesNonExemptEncryption bool false" \
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
	$(MAKE) tap

# Homebrew cask'ini yeni surum + sha256 ile tap'e gonderir. Ayri clone yok:
# gh api ile tek dosya PUT ediliyor.
tap:
	@SHA=$$(shasum -a 256 $(ZIP) | cut -d' ' -f1); \
	sed -e "s/{{VERSION}}/$(VERSION)/g" -e "s/{{SHA256}}/$$SHA/g" \
	  Packaging/ghbar.rb.template > $(BUILD_DIR)/ghbar.rb; \
	B64=$$(base64 -i $(BUILD_DIR)/ghbar.rb); \
	EXISTING=$$(gh api repos/cobanov/homebrew-tap/contents/Casks/ghbar.rb --jq .sha 2>/dev/null || true); \
	if [ -n "$$EXISTING" ]; then \
	  gh api -X PUT repos/cobanov/homebrew-tap/contents/Casks/ghbar.rb \
	    -f message="ghbar $(VERSION)" -f content="$$B64" -f sha="$$EXISTING" > /dev/null; \
	else \
	  gh api -X PUT repos/cobanov/homebrew-tap/contents/Casks/ghbar.rb \
	    -f message="ghbar $(VERSION)" -f content="$$B64" > /dev/null; \
	fi; \
	echo "tap guncellendi: brew install hazir"

# --- Kurulum ------------------------------------------------------------

install: bundle
	@# Yerel kurulum ad-hoc imzalanir: paket muhru olmadan bildirimlerin
	@# istedigi kararli kod kimligi olusmaz (linker yalnizca ikiliyi imzalar).
	codesign --force --deep --sign - $(APP_BUNDLE)
	@pkill -x $(APP) 2>/dev/null || true
	@rm -rf /Applications/$(APP).app
	cp -R $(APP_BUNDLE) /Applications/
	@echo "kuruldu: /Applications/$(APP).app"
	open /Applications/$(APP).app

# --- MAS varyanti ----------------------------------------------------------
# Ayri scratch path SART: -DMAS'li ve bayraksiz nesneler ayni .build'de
# karisirsa hangi ikilinin hangi bayrakla derlendigi belirsizlesir.
MAS_SCRATCH   := .build-mas
MASFLAGS      := -Xswiftc -DMAS
MAS_DIR       := $(BUILD_DIR)/mas
MAS_BUNDLE    := $(MAS_DIR)/$(APP).app
MAS_CONTENTS  := $(MAS_BUNDLE)/Contents
MAS_SIGN_ID   := Apple Distribution: AHMET MERT COBANOGLU (6U58AKY6F8)
MAS_PKG_ID    := 3rd Party Mac Developer Installer: AHMET MERT COBANOGLU (6U58AKY6F8)
MAS_PROFILE   := Packaging/GHBar_MAS.provisionprofile
PKG           := $(BUILD_DIR)/$(APP)-$(VERSION)-mas.pkg

# Iki varyanti da derle + testler. Yayin oncesi tek dogrulama kapisi
# (spec §20 korkuluk #2): MAS varyantini bozan degisiklik burada patlar.
check: test build build-mas
	@echo "check: iki varyant da derlendi, testler yesil"

build-mas:
	swift build -c release --scratch-path $(MAS_SCRATCH) $(MASFLAGS)

bundle-mas: build-mas $(ICNS)
	@rm -rf $(MAS_BUNDLE)
	@mkdir -p $(MAS_CONTENTS)/MacOS $(MAS_CONTENTS)/Resources
	cp $(MAS_SCRATCH)/release/$(APP) $(MAS_CONTENTS)/MacOS/$(APP)
	cp $(ICNS) $(MAS_CONTENTS)/Resources/$(APP).icns
	@printf '%s' 'APPL????' > $(MAS_CONTENTS)/PkgInfo
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
	  -c "Add :LSApplicationCategoryType string public.app-category.developer-tools" \
	  -c "Add :ITSAppUsesNonExemptEncryption bool false" \
	  -c "Add :NSHumanReadableCopyright string 'Copyright © 2026 Mert Cobanov.'" \
	  $(MAS_CONTENTS)/Info.plist >/dev/null
	@test -f $(MAS_PROFILE) \
	  && cp $(MAS_PROFILE) $(MAS_CONTENTS)/embedded.provisionprofile \
	  || echo "UYARI: $(MAS_PROFILE) yok — App Store yuklemesi provisioning profile ister"
	@echo "MAS paketi: $(MAS_BUNDLE)"

sign-mas: bundle-mas
	codesign --force --timestamp \
	  --entitlements Packaging/GHBar-MAS.entitlements \
	  --sign "$(MAS_SIGN_ID)" $(MAS_CONTENTS)/MacOS/$(APP)
	codesign --force --timestamp \
	  --entitlements Packaging/GHBar-MAS.entitlements \
	  --sign "$(MAS_SIGN_ID)" $(MAS_BUNDLE)
	codesign --verify --deep --strict $(MAS_BUNDLE)

# App Store'a gidecek .pkg. Yukleme Transporter.app ile yapilir (kullanici).
pkg: sign-mas
	@rm -f $(PKG)
	productbuild --component $(MAS_BUNDLE) /Applications \
	  --sign "$(MAS_PKG_ID)" $(PKG)
	@echo "App Store paketi: $(PKG) — Transporter.app ile yukle"

clean:
	rm -rf $(BUILD_DIR) .build $(MAS_SCRATCH)
