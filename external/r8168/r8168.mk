################################################################################
#
# r8168
#
################################################################################
# Version: Commits on Nov 30, 2022
R8168_VERSION = be2159ff80167b70825bdc7dae2836c041205d38
R8168_SITE = $(call github,AuxXxilium,r8168,$(R8168_VERSION))
R8168_LICENSE = GPL-2.0
R8168_LICENSE_FILES = LICENSE
R8168_MODULE_SUBDIRS = src

R8168_MODULE_MAKE_OPTS += ENABLE_USE_FIRMWARE_FILE=y
R8168_MODULE_MAKE_OPTS += CONFIG_R8168_NAPI=y
R8168_MODULE_MAKE_OPTS += CONFIG_R8168_VLAN=y
R8168_MODULE_MAKE_OPTS += CONFIG_ASPM=y
R8168_MODULE_MAKE_OPTS += ENABLE_S5WOL=y
R8168_MODULE_MAKE_OPTS += ENABLE_EEE=y
R8168_MODULE_MAKE_OPTS += \
    USER_EXTRA_CFLAGS="-DCONFIG_$(call qstrip,$(BR2_ENDIAN))_ENDIAN -Wno-error"

define R8168_MAKE_SUBDIR
    (cd $(@D)/src; ln -s . r8168)
endef

R8168_PRE_CONFIGURE_HOOKS += R8168_MAKE_SUBDIR

$(eval $(kernel-module))
$(eval $(generic-package))
