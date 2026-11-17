#
# vedotom_handheld_product.mk: build/make/target/product/handheld_product.mk minus the apps the
# Fossify suite replaces (Calendar, Camera2, Contacts, DeskClock, Gallery2, Music) and
# QuickSearchBox, which nothing needs. Browser2 and LatinIME stay: a working browser and keyboard
# must exist before anything else is installed, and both are pure AOSP.
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/media_product.mk)

PRODUCT_PACKAGES += \
    Browser2 \
    LatinIME \
    preinstalled-packages-platform-handheld-product.xml \
    SettingsIntelligence \
    frameworks-base-overlays

PRODUCT_PACKAGES_DEBUG += \
    frameworks-base-overlays-debug
