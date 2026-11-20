#
# vedotom_handheld_product.mk: build/make/target/product/handheld_product.mk minus the apps the
# Fossify suite replaces (Calendar, Camera2, Contacts, DeskClock, Gallery2, Music), QuickSearchBox,
# which nothing needs, and Browser2, AOSP's WebView test shell (the image has no browser by
# design; see vedotom_arm64.mk). LatinIME stays: a keyboard must work before anything else is
# installed, and it is pure AOSP.
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/media_product.mk)

PRODUCT_PACKAGES += \
    LatinIME \
    preinstalled-packages-platform-handheld-product.xml \
    SettingsIntelligence \
    frameworks-base-overlays

PRODUCT_PACKAGES_DEBUG += \
    frameworks-base-overlays-debug
