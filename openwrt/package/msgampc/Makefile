# Copyright (c) 2010-2013 Stephan Platz

include $(TOPDIR)/rules.mk

PKG_NAME:=msgampc
PKG_VERSION:=0.1
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

PKG_SRC_URL:=github.com/mysmartgrid/msg-prototype-2
PKG_SRCDIR=$(PKG_BUILD_DIR)/src/$(PKG_SRC_URL)
PKG_SOURCE=$(TOPDIR)/feeds/msgflukso/$(PKG_NAME)

GOPATH:=$(PKG_BUILD_DIR)
GOROOT:=/tmp/krueger/go/mips/go-mips32

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/msgampc
  SECTION:=utils
  CATEGORY:=Network
  DEPENDS:=+ip
  TITLE:=Msgampc
  URL:=http://www.hexabus.net
  MAINTAINER:=Kai Krueger <kai.krueger@itwm.fraunhofer.de>
endef

define Package/msgampc/description
	A small daemon to emulate a HexaBus device on a flukso.
endef

define Build/Prepare
	echo "===> Build/Prepare"
	( cd $(PKG_BUILD_DIR); cmake $(PKG_SOURCE) )
	sh -c 'if [ -d $(PKG_SRCDIR) ]; then cd $(PKG_SRCDIR); git pull --rebase; cd ..; else git clone http://$(PKG_SRC_URL).git -b msgampc $(PKG_SRCDIR); fi' \;
	echo "===> Build/Prepare"
	$(CP) msgampc.init $(PKG_BUILD_DIR)
	$(CP) ./config/* $(PKG_BUILD_DIR)/
	$(Build/Patch)
endef

define Build/Configure
	echo "===> Build/Configure"
	(cd $(PKG_BUILD_DIR);  make configure)
	rsync -a ${PKG_SRCDIR}/vendor/ ${PKG_BUILD_DIR}/src/
endef

define Build/Compile
	echo "===> Build/Compile"
	echo "Compile : ${PKG_SRCDIR}"
	(cd $(PKG_BUILD_DIR);  make build)
	PATH=$(GOPATH)/bin:$(GOROOT)/bin:$(PATH)
	( \
		cd ${PKG_SRCDIR}; \
		mkdir -p $(PKG_INSTALL_DIR)/usr/bin; \
		$(CP) msgampc $(PKG_INSTALL_DIR)/usr/bin/ ;\
	)
	echo "compile"
endef

define Build/Install
endef

define Package/msgampc/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/msgampc.uci $(1)/etc/config/msgampc

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/msgampc.init $(1)/etc/init.d/msgampc

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/msgampc $(1)/usr/bin/
endef

$(eval $(call BuildPackage,msgampc))
