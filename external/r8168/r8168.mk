################################################################################
#
# r8168
#
################################################################################

R8168_VERSION = 4aebcf6519a4aaccbb19afd5c2f7e36a50a9fa34
R8168_SITE = $(call github,AuxXxilium,r8168,$(R8168_VERSION))
R8168_LICENSE = GPL-2.0

$(eval $(kernel-module))
$(eval $(generic-package))
