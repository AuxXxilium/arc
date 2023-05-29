################################################################################
#
# r8125
#
################################################################################

R8125_VERSION = 4b4f60bed1e9dee6ea4394482dcb7449ade95a4a
R8125_SITE = $(call github,AuxXxilium,r8125,$(R8125_VERSION))
R8125_LICENSE = GPL-2.0

$(eval $(kernel-module))
$(eval $(generic-package))

