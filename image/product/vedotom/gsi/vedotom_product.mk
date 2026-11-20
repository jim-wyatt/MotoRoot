#
# vedotom_product.mk: build/make/target/product/aosp_product.mk, minus the apps the Fossify suite
# replaces. Kept line-for-line otherwise so a diff against upstream shows exactly what changed:
#   - handheld_product.mk  -> vedotom_handheld_product.mk (same minus Calendar, Camera2, Contacts,
#                             DeskClock, Gallery2, Music, QuickSearchBox)
#   - telephony_product.mk -> inlined without Dialer (Fossify Phone is the dialer)
#   - messaging dropped     (Fossify Messages is the SMS app)
#

$(call inherit-product, device/vedotom/gsi/vedotom_handheld_product.mk)

# telephony_product.mk without Dialer
PRODUCT_PACKAGES += \
    ImsServiceEntitlement \
    preinstalled-packages-platform-telephony-product.xml

# Default ringtone, notification and alarm sounds, as upstream.
$(call inherit-product-if-exists, frameworks/base/data/sounds/AllAudio.mk)

PRODUCT_PRODUCT_PROPERTIES += \
    ro.config.ringtone?=Ring_Synth_04.ogg \
    ro.config.notification_sound?=pixiedust.ogg \
    ro.com.android.dataroaming?=true \

# PhotoTable (a photo screensaver) is left out.
PRODUCT_PACKAGES += \
    initial-package-stopped-states-aosp.xml \
    preinstalled-packages-platform-aosp-product.xml \
    ThemePicker \

PRODUCT_COPY_FILES += \
    device/sample/etc/apns-full-conf.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/apns-conf.xml
