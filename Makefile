NAME := Feather
SCHEME := Feather
PLATFORMS := iphoneos
BUILD_SETTINGS ?=

TMP := $(TMPDIR)/$(NAME)
CERT_JSON_URL := https://backloop.dev/pack.json

.PHONY: all clean deps verify preview-screenshots $(PLATFORMS)

all: verify $(PLATFORMS) preview-screenshots

verify:
	xcrun swiftc -target $$(uname -m)-apple-macosx15.0 Feather/Backend/Observable/BackgroundDownloadStore.swift Feather/Backend/Storage/LocalAppFiles.swift tools/background-tests/main.swift -o /tmp/fizer-background-tests
	/tmp/fizer-background-tests
	python3 tools/check_preview.py
	python3 tools/test_promote.py
	xcrun swiftc Feather/Backend/Observable/CatalogCategory.swift tools/catalog-tests/main.swift -o /tmp/feather-catalog-tests
	/tmp/feather-catalog-tests
	xcrun swiftc Feather/Backend/Observable/FeatherAccessLease.swift Feather/Backend/Observable/FeatherAccessManager.swift tools/access-tests/main.swift -o /tmp/feather-access-tests
	/tmp/feather-access-tests
	xcrun swiftc Feather/Backend/Observable/RepositoryFileIdentity.swift Feather/Backend/Observable/DownloadPresentation.swift tools/identity-tests/main.swift -o /tmp/fizer-identity-tests
	/tmp/fizer-identity-tests
	xcrun swiftc -target $$(uname -m)-apple-macosx15.0 Feather/Backend/Observable/RepositoryFileIdentity.swift Feather/Backend/Observable/RepositoryInstallCoordinator.swift tools/coordinator-tests/main.swift -o /tmp/fizer-coordinator-tests
	/tmp/fizer-coordinator-tests

preview-screenshots:
	python3 tools/capture_preview.py

clean:
	rm -rf $(TMP)
	rm -rf packages
	rm -rf Payload

deps:
	rm -rf deps || true
	mkdir -p deps

	curl -fsSL "$(CERT_JSON_URL)" -o cert.json
	jq -r '.cert' cert.json > deps/server.crt
	jq -r '.key1, .key2' cert.json > deps/server.pem
	jq -r '.info.domains.commonName' cert.json > deps/commonName.txt


$(PLATFORMS): deps
	rm -rf _build

	@if [ "$@" = "iphoneos" ]; then \
		DEST="generic/platform=iOS"; \
	else \
		DEST="generic/platform=macOS,variant=Mac Catalyst"; \
	fi; \
	xcodebuild \
		-project Feather.xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination "$$DEST" \
		-derivedDataPath $(TMP)/$@ \
		-skipPackagePluginValidation \
		CODE_SIGNING_ALLOWED=NO \
		ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO $(BUILD_SETTINGS)

	mkdir -p _build/Payload
	cp -R _build/Applications/*.app _build/Payload/Feather.app
	chmod -R 0755 _build/Payload/Feather.app
	codesign --force --sign - --timestamp=none _build/Payload/Feather.app
	cp deps/* _build/Payload/Feather.app/ || true

	mkdir -p packages

	@if [ "$@" = "iphoneos" ]; then \
		ditto -c -k --sequesterRsrc --keepParent _build/Payload "packages/Feather.ipa"; \
	else \
		ditto -c -k --sequesterRsrc --keepParent _build/Payload/Feather.app "packages/Feather_Catalyst.zip"; \
	fi
	python3 tools/check_preview.py --ipa packages/Feather.ipa
