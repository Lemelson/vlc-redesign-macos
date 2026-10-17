# Native Swift interface. The engine and stock display modules stay upstream.
MXR_DIR = gui/macosx_redesign
MXR_SWIFT_OUT = $(MXR_DIR)/swift
MXR_SWIFT_LIB = $(MXR_SWIFT_OUT)/libMXRPlugin.a
MXR_SWIFT_FILES = $(shell cd "$(srcdir)" && find $(MXR_DIR)/Sources -type f 2>/dev/null)
MXR_SWIFT_TEST_FILES = $(shell cd "$(srcdir)" && find $(MXR_DIR)/Tests -type f 2>/dev/null)
MXR_NATIVE_FILES = $(shell cd "$(srcdir)" && find $(MXR_DIR)/module -type f 2>/dev/null)
MXR_SWIFT_INPUTS = $(srcdir)/$(MXR_DIR)/Package.swift \
	$(addprefix $(srcdir)/,$(MXR_SWIFT_FILES))

.PHONY: mxr-swift-inputs-force
mxr-swift-inputs-force:

# SwiftPM owns incremental state; always invoke it so deleted inputs are observed.
$(MXR_SWIFT_LIB): mxr-swift-inputs-force $(MXR_SWIFT_INPUTS) $(srcdir)/$(MXR_DIR)/tools/swiftpm-build.sh
	$(AM_V_GEN)$(SHELL) "$(srcdir)/$(MXR_DIR)/tools/swiftpm-build.sh" \
	  "$(abs_top_srcdir)/modules/$(MXR_DIR)" "$(abs_builddir)/$(MXR_DIR)/swiftpm" \
	  "$(MXR_SWIFT_ARCH)" "$(MXR_SWIFT_CONFIGURATION)" "$(MXR_SANITIZER)" \
	  "$(abs_builddir)/$(MXR_SWIFT_LIB)" "$(abs_builddir)/$(MXR_SWIFT_OUT)/resources"
CLEANFILES += $(MXR_SWIFT_LIB)

libmacosx_redesign_plugin_la_SOURCES = \
	$(MXR_DIR)/module/module.c \
	$(MXR_DIR)/module/MXRIntf.m \
	$(MXR_DIR)/module/MXRVoutWindow.m \
	$(MXR_DIR)/module/bridge/MXRInterfaceBridge.m \
	$(MXR_DIR)/module/bridge/MXRPlayerBridge.m \
	$(MXR_DIR)/module/bridge/MXRServicesBridge.m \
	$(MXR_DIR)/module/bridge/MXRLibraryServices.m \
	$(MXR_DIR)/module/bridge/MXRDialogServices.m \
	$(MXR_DIR)/module/bridge/MXRThumbnailServices.m \
	$(MXR_DIR)/module/bridge/MXRMediaServices.m \
	$(MXR_DIR)/module/bridge/MXRAudioServices.m \
	$(MXR_DIR)/module/bridge/MXRAudioPreferenceServices.m \
	$(MXR_DIR)/module/bridge/MXRDiscoveryServices.m \
	$(MXR_DIR)/module/bridge/MXRSubtitleCueServices.m \
	$(MXR_DIR)/module/bridge/MXREffectsServices.m \
	$(MXR_DIR)/module/bridge/MXRPlatformServices.m
MXR_FLAGS = -mmacosx-version-min=$(MXR_MIN_MACOS) \
	-I$(srcdir)/$(MXR_DIR)/module \
	-I$(srcdir)/$(MXR_DIR)/Sources/MXRBridgeAPI/include
libmacosx_redesign_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) $(MXR_FLAGS)
libmacosx_redesign_plugin_la_CFLAGS = $(AM_CFLAGS) $(MXR_FLAGS)
libmacosx_redesign_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) $(MXR_FLAGS) -fobjc-arc -fobjc-exceptions
libmacosx_redesign_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(gui_RPATH) \
	-mmacosx-version-min=$(MXR_MIN_MACOS) \
	-Wl,-force_load,$(abs_builddir)/$(MXR_SWIFT_LIB) \
	-L$(MXR_SDK_PATH)/usr/lib/swift -L$(MXR_SWIFT_TOOLCHAIN_LIBDIR) \
	-Wl,-rpath,/usr/lib/swift \
	-Wl,-framework,AppKit,-framework,SwiftUI,-framework,AVKit \
	-Wl,-weak_framework,MediaPlayer \
	-Wl,-framework,AVFoundation,-framework,QuartzCore,-framework,CoreVideo \
	-Wl,-framework,CoreMedia,-framework,AudioToolbox,-framework,CoreGraphics,-framework,CoreText
EXTRA_libmacosx_redesign_plugin_la_DEPENDENCIES = $(MXR_SWIFT_LIB)

if ENABLE_MACOSX_REDESIGN
gui_PLUGINS += libmacosx_redesign_plugin.la
install-data-local: install-macosx-redesign-resources
check-local: check-macosx-redesign
endif

install-macosx-redesign-resources: $(MXR_SWIFT_LIB)
	$(MKDIR_P) "$(DESTDIR)$(datadir)/macosx/Contents/Resources"
	cp -R "$(MXR_SWIFT_OUT)/resources/." "$(DESTDIR)$(datadir)/macosx/Contents/Resources/"
	cp "$(srcdir)/gui/macosx/Resources/App-Icons/VLC.icns" "$(DESTDIR)$(datadir)/macosx/Contents/Resources/"
check-macosx-redesign: check-macosx-redesign-generated check-macosx-redesign-native
	python3 "$(srcdir)/$(MXR_DIR)/tools/run-swift-tests.py" \
	  "$(abs_top_srcdir)/modules/$(MXR_DIR)" "$(abs_builddir)/$(MXR_DIR)/swiftpm-test"
	python3 "$(srcdir)/$(MXR_DIR)/tools/test-packaging.py"
	python3 "$(srcdir)/$(MXR_DIR)/tools/test-build-contracts.py"
	python3 "$(srcdir)/$(MXR_DIR)/tools/test-finalize-app.py"
	python3 "$(srcdir)/$(MXR_DIR)/tools/test-install-app.py"
	python3 "$(srcdir)/$(MXR_DIR)/tools/test-schema-drift.py"
	python3 "$(srcdir)/$(MXR_DIR)/tools/test-swift-results.py"
	python3 "$(srcdir)/$(MXR_DIR)/tools/test-native-runtime-isolation.py"
	python3 "$(srcdir)/$(MXR_DIR)/tools/test-native-diagnostics.py"
	python3 "$(srcdir)/$(MXR_DIR)/tools/test-screens-doc.py"

.PHONY: check-macosx-redesign check-macosx-redesign-generated check-macosx-redesign-native
check-macosx-redesign-generated:
	python3 -I "$(srcdir)/$(MXR_DIR)/tools/gen-tokens.py" --check
	python3 -I "$(srcdir)/$(MXR_DIR)/tools/gen-icons.py" --check

check-macosx-redesign-native:
	python3 "$(srcdir)/$(MXR_DIR)/tools/native-tests.py" --engine-build "$(abs_top_builddir)"

# Explicit runtime gates: decoded media/Lua/hardware are never hidden inside a unit check.
.PHONY: check-macosx-redesign-library check-macosx-redesign-audio check-macosx-redesign-media check-macosx-redesign-extensions check-macosx-redesign-subtitle-runtime
check-macosx-redesign-library:
	python3 "$(srcdir)/$(MXR_DIR)/tools/native-tests.py" --engine-build "$(abs_top_builddir)" --suite library
check-macosx-redesign-audio:
	python3 "$(srcdir)/$(MXR_DIR)/tools/native-tests.py" --engine-build "$(abs_top_builddir)" --suite audio
check-macosx-redesign-media:
	python3 "$(srcdir)/$(MXR_DIR)/tools/native-tests.py" --engine-build "$(abs_top_builddir)" --suite media
check-macosx-redesign-extensions:
	python3 "$(srcdir)/$(MXR_DIR)/tools/native-tests.py" --engine-build "$(abs_top_builddir)" --suite extensions
check-macosx-redesign-subtitle-runtime:
	python3 "$(srcdir)/$(MXR_DIR)/tools/native-tests.py" --engine-build "$(abs_top_builddir)" --suite subtitle-runtime

# Installed-app gate (not part of check; run after tools/install-app.sh with the app closed):
# real start/play/quit with the redesign interface, hardware decode, audio, subtitles and
# a fresh plugins.dat. Quote paths with spaces: MXR_SMOKE_MEDIA='"/path/a b.mp4" /path/c.mp4'
MXR_SMOKE_APP = /Applications/VLC Redesign.app
.PHONY: check-macosx-redesign-app
check-macosx-redesign-app:
	@test -n "$(MXR_SMOKE_MEDIA)" || { echo "set MXR_SMOKE_MEDIA to one or more video files" >&2; exit 2; }
	python3 -I "$(srcdir)/$(MXR_DIR)/tools/smoke-native.py" "$(MXR_SMOKE_APP)" \
	  "$(abs_builddir)/macosx-redesign-smoke.log" $(MXR_SMOKE_MEDIA)

# Include every module-owned resource/helper, including required packaging icons and headers.
MXR_RESOURCE_FILES = $(shell cd "$(srcdir)" && find $(MXR_DIR)/Resources -type f 2>/dev/null)
MXR_TOOL_FILES = $(shell cd "$(srcdir)" && find $(MXR_DIR)/tools -type f ! -path '*/__pycache__/*' ! -name '*.pyc' 2>/dev/null)
MXR_GENERATOR_INPUT_FILES = $(shell cd "$(srcdir)" && find ../redesign/design/tokens ../redesign/design/figma/icons-svg ../redesign/patches/engine -type f 2>/dev/null)
EXTRA_DIST += $(MXR_GENERATOR_INPUT_FILES) $(MXR_SWIFT_FILES) $(MXR_SWIFT_TEST_FILES) $(MXR_NATIVE_FILES) \
	$(MXR_RESOURCE_FILES) $(MXR_TOOL_FILES) \
	$(MXR_DIR)/Package.swift $(MXR_DIR)/configure.m4
