################################################################################
#
# r8169
#
################################################################################

R8169_VERSION = d555e4a0007d94c6dba87379e345f7f5a00fcf30
R8169_SITE = $(call github,AuxXxilium,r8169,$(R8169_VERSION))
R8169_LICENSE = GPL-2.0

R8169_MODULE_MAKE_OPTS = \
    USER_EXTRA_CFLAGS="-DCONFIG_$(call qstrip,$(BR2_ENDIAN))_ENDIAN -Wno-error"

$(eval $(kernel-module))
$(eval $(generic-package))
