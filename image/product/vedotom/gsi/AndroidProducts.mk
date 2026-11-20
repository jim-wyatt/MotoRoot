# VedoTom's own GSI product. Copied into the AOSP tree as device/vedotom/gsi/ by
# image/build/apply-local.sh; the source of truth is this file in the repository.
PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/vedotom_arm64.mk

COMMON_LUNCH_CHOICES := \
    vedotom_arm64-trunk_staging-userdebug \
    vedotom_arm64-trunk_staging-eng
