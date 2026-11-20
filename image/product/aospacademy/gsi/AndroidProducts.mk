# aosp-academy's own GSI product. Copied into the AOSP tree as device/aospacademy/gsi/ by
# image/build/apply-local.sh; the source of truth is this file in the repository.
PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/aospacademy_arm64.mk

COMMON_LUNCH_CHOICES := \
    aospacademy_arm64-trunk_staging-userdebug \
    aospacademy_arm64-trunk_staging-eng
