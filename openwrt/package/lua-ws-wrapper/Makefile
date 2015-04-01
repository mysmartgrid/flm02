include $(TOPDIR)/rules.mk

PKG_NAME:=lua-ws-wrapper
PKG_VERSION:=0.1
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/lua-ws-wrapper
  SECTION:=libs
  CATEGORY:=Network
  DEPENDS:=+libwebsockets-openssl
  TITLE:=lua websocket wrapper for msg device protocol
  MAINTAINER:=Phoebe Buckheister<phoebe.buckheister@itwm.fraunhofer.de>
endef

define Package/lua-ws-wrapper/description
  lua-ws-wrapper attempts to provide websocket communication with the mySmartGrid servers for devices,
  for use by lua programs.
endef

CMAKE_SOURCE_DIR:=msgp/flukso
define Build/Prepare
	if [ -d msgp ]; then (cd msgp; git pull --rebase); else git clone https://github.com/mysmartgrid/msg-prototype-2.git msgp; fi

	mkdir -p $(PKG_BUILD_DIR)
	cp -R msgp $(PKG_BUILD_DIR)

	$(Build/Patch)
endef

define Build/Install
endef

define Build/InstallDev
endef

define Package/lua-ws-wrapper/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/lua-ws-wrapper $(1)/usr/bin
endef

$(eval $(call BuildPackage,lua-ws-wrapper))
