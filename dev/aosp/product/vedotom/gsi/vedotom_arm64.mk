#
# vedotom_arm64: AOSP's arm64 GSI, with this project's apps, defaults and fixes.
#
# This is build/make/target/product/aosp_arm64.mk with two changes: the product-partition app set
# comes from vedotom_product.mk instead of aosp_product.mk (so the AOSP apps the Fossify suite
# replaces are not built in at all), and the settings aosp_arm64.mk keeps behind its
# `ifeq (aosp_arm64,$(TARGET_PRODUCT))` guard are applied unconditionally. Everything else is
# inherited from the same upstream makefiles, so the system partition is the stock GSI's.
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/generic_system.mk)
PRODUCT_ENFORCE_ARTIFACT_PATH_REQUIREMENTS := relaxed
$(call inherit-product, $(SRC_TARGET_DIR)/product/handheld_system_ext.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/telephony_system_ext.mk)
$(call inherit-product-if-exists, packages/modules/Virtualization/apex/product_packages.mk)
$(call inherit-product, device/vedotom/gsi/vedotom_product.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/board/generic_arm64/device.mk)

AB_OTA_UPDATER := true
AB_OTA_PARTITIONS ?= system

MODULE_BUILD_FROM_SOURCE ?= true
$(call inherit-product, $(SRC_TARGET_DIR)/product/gsi_release.mk)
PRODUCT_SOONG_DEFINED_SYSTEM_IMAGE := vedotom_system_image
USE_SOONG_DEFINED_SYSTEM_IMAGE := true
# The image module above lives in device/vedotom/gsi/Android.bp: upstream's aosp_system_image
# mirrored without the apps the Fossify suite replaces and with this project's modules added.

PRODUCT_NAME := vedotom_arm64
PRODUCT_DEVICE := generic_arm64
PRODUCT_BRAND := Android
PRODUCT_MODEL := VedoTom AOSP on ARM64
PRODUCT_NO_BIONIC_PAGE_SIZE_MACRO := true

# --- this project's changes --------------------------------------------------------------------

# No boot animation: SurfaceFlinger skips the bootanimation service entirely, so the screen stays
# on the bootloader's splash until the lock screen. To replace the animation instead, drop this
# line and add a bootanimation.zip:
#   PRODUCT_COPY_FILES += device/vedotom/gsi/bootanimation.zip:$(TARGET_COPY_OUT_PRODUCT)/media/bootanimation.zip
# The GSI's artifact-path rules forbid adding properties to the system partition
# (generic_system.mk), so this goes into the product partition's build.prop; property_get() reads all of them.
PRODUCT_PRODUCT_PROPERTIES += \
    debug.sf.nobootanimation=1

# Our look and defaults: dark theme, gesture navigation, our wallpaper (from which Material You
# derives the system colours), Fossify Phone and Messages as the default dialer and SMS app.
# See overlay/ (a static framework RRO).
PRODUCT_PACKAGES += \
    VedoTomFrameworkOverlay

# Fossify Launcher as the home screen. Launcher3QuickStep stays installed because SystemUI binds
# its quickstep service for gesture navigation and recents; this file makes Fossify the preferred
# HOME activity at first boot (PackageManager reads /product/etc/preferred-apps).
PRODUCT_PACKAGES += \
    VedoTomPreferredApps

# The apps. Prebuilt APKs from F-Droid (hash- and signer-pinned in dev/toolchain.json, copied into
# prebuilt/ by apply-local.sh), declared in prebuilt/Android.bp. The Fossify suite replaces AOSP's
# Calendar, Camera2, Contacts, DeskClock, Dialer, Gallery2, Music, messaging and QuickSearchBox,
# which vedotom_handheld_product.mk and vedotom_product.mk leave out.
PRODUCT_PACKAGES += \
    FossifyLauncher \
    FossifyGallery \
    FossifyFileManager \
    FossifyDocuments \
    FossifyCalendar \
    FossifyContacts \
    FossifyPhone \
    FossifyMessages \
    FossifyClock \
    FossifyCalculator \
    FossifyNotes \
    FossifyMusicPlayer \
    FossifyCamera \
    FossifyVoiceRecorder \
    FossifyPaint \
    FossifyKeyboard \
    FDroid

# Organic Maps ships its native libraries compressed, which a system-image prebuilt cannot keep
# without re-signing (and a re-signed app could no longer be updated by F-Droid). It is therefore
# carried as a preload: the APK sits in /product/etc/preload (a prebuilt_etc module; the build
# refuses APKs in PRODUCT_COPY_FILES) and the first-boot service installs it as an ordinary app,
# with F-Droid recorded as the installer, keeping its F-Droid signature.
PRODUCT_PACKAGES += \
    OrganicMapsPreload \
    vedotom-firstboot \
    init.vedotom.rc
