#
# vedotom_arm64: AOSP's arm64 GSI (aosp_arm64) plus this project's changes.
#
# Everything the stock GSI is, with the customisations below layered on top, so the upstream
# product makefiles stay untouched. aosp_arm64.mk keeps its GSI-specific settings behind an
# `ifeq (aosp_arm64,$(TARGET_PRODUCT))` guard, which a derived product does not satisfy, so
# those settings are repeated here (the same pattern AOSP's own aosp_arm64_fullmte.mk uses).
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_arm64.mk)

# --- what the aosp_arm64 guard would have set -------------------------------------------------
PRODUCT_ENFORCE_ARTIFACT_PATH_REQUIREMENTS := relaxed
MODULE_BUILD_FROM_SOURCE ?= true
$(call inherit-product, $(SRC_TARGET_DIR)/product/gsi_release.mk)
PRODUCT_SOONG_DEFINED_SYSTEM_IMAGE := aosp_system_image
USE_SOONG_DEFINED_SYSTEM_IMAGE := true

# --- identity ------------------------------------------------------------------------------------
PRODUCT_NAME := vedotom_arm64
PRODUCT_MODEL := VedoTom AOSP on ARM64

# --- this project's changes --------------------------------------------------------------------
# No boot animation: SurfaceFlinger skips the bootanimation service entirely, so the screen stays
# on the bootloader's splash until the lock screen. To replace the animation instead, drop this
# line and add a bootanimation.zip:
#   PRODUCT_COPY_FILES += device/vedotom/gsi/bootanimation.zip:$(TARGET_COPY_OUT_PRODUCT)/media/bootanimation.zip
# The GSI's artifact-path rules forbid adding properties to the system partition
# (generic_system.mk), so this goes into the product partition's build.prop; property_get() reads all of them.
PRODUCT_PRODUCT_PROPERTIES += \
    debug.sf.nobootanimation=1
