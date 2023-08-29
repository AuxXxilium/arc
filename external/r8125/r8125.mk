################################################################################
#
# r8125
#
################################################################################

R8125_VERSION = 834fa240aef5dc3cfe0f688efcb61cec58c055eb
R8125_SITE = $(call github,AuxXxilium,r8125,$(R8125_VERSION))
R8125_LICENSE = GPL-2.0
R8125_LICENSE_FILES = LICENSE
R8125_MODULE_SUBDIRS = src

R8125_MODULE_MAKE_OPTS = CONFIG_R8125=m \
    USER_EXTRA_CFLAGS="-DCONFIG_$(call qstrip,$(BR2_ENDIAN))_ENDIAN -Wno-error"

define R8125_MAKE_SUBDIR
    (cd $(@D)/src; ln -s . r8125)
endef

R8125_PRE_CONFIGURE_HOOKS += R8125_MAKE_SUBDIR

$(eval $(kernel-module))
$(eval $(generic-package))
