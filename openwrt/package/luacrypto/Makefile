include $(TOPDIR)/rules.mk

PKG_NAME:=luacrypto
PKG_VERSION:=0.3.2
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/mkottman/luacrypto.git
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE_VERSION:=$(PKG_VERSION)
PKG_SOURCE_PROTO:=git

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

include $(INCLUDE_DIR)/package.mk

define Package/luacrypto
  SUBMENU:=Lua
  SECTION:=lang
  CATEGORY:=Languages
  TITLE:=luacrypto
  URL:=https://github.com/mkottman/luacrypto
  DEPENDS:=+lua +libopenssl
  MAINTAINER:=Phoebe Buckheister<phoebe.buckheister@itwm.fraunhofer.de>
endef

TARGET = luacrypto
LIBS = -lcrypto -ldl -llua
TARGET_CFLAGS += $(FPIC)
TARGET_LDFLAGS += -shared

define Package/luacrypto/description
  luacrypto
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) \
		-I$(STAGING_DIR)/usr/include \
		-c $(PKG_BUILD_DIR)/src/lcrypto.c \
		-o $(PKG_BUILD_DIR)/$(TARGET).o
	$(TARGET_CC) $(TARGET_LDFLAGS) \
		$(LIBS) \
		$(PKG_BUILD_DIR)/$(TARGET).o \
		-o $(PKG_BUILD_DIR)/crypto.so
endef

define Package/luacrypto/install
	$(INSTALL_DIR) $(1)/usr/lib/lua
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/crypto.so $(1)/usr/lib/lua/
endef

$(eval $(call BuildPackage,luacrypto))
