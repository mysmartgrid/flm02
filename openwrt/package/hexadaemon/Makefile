# Copyright (c) 2010-2013 Stephan Platz

include $(TOPDIR)/rules.mk

PKG_NAME:=hexadaemon
PKG_VERSION:=0.2
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/hexadaemon
  SECTION:=utils
  CATEGORY:=Network
  DEPENDS:=+libhexabus +boost-system +boost-regex
  TITLE:=HexaDaemon
  URL:=http://www.hexabus.net
  MAINTAINER:=Stephan Platz <stephan.platz@itwm.fraunhofer.de>
endef

define Package/hexadaemon/description
	A small daemon to emulate a HexaBus device on a flukso.
endef

define Build/Prepare
	sh -c 'if [ -d hexabus ]; then cd hexabus; git pull --rebase; cd ..; else git clone http://github.com/mysmartgrid/hexabus.git -b sp-hexadaemon; fi'

	mkdir -p $(PKG_BUILD_DIR)
	cp -R hexabus/* $(PKG_BUILD_DIR)

	cp hexadaemon.init $(PKG_BUILD_DIR)

	$(Build/Patch)
endef

define Build/Configure
	(cd $(PKG_BUILD_DIR)/hostsoftware/hexadaemon; \
	mkdir build; cd build; \
		CFLAGS="$(TARGET_CFLAGS) $(EXTRA_CFLAGS)" \
		CXXFLAGS="$(TARGET_CFLAGS) $(EXTRA_CFLAGS)" \
		cmake \
			-DCMAKE_SYSTEM_NAME=Linux \
			-DCMAKE_SYSTEM_VERSION=1 \
			-DCMAKE_SYSTEM_PROCESSOR=$(ARCH) \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_C_FLAGS_RELEASE="-DNDEBUG" \
			-DCMAKE_CXX_FLAGS_RELEASE="-DNDEBUG" \
			-DCMAKE_C_COMPILER="$(CMAKE_C_COMPILER)" \
			-DCMAKE_C_COMPILER_ARG1="$(CMAKE_C_COMPILER_ARG1)" \
			-DCMAKE_CXX_COMPILER="$(CMAKE_CXX_COMPILER)" \
			-DCMAKE_CXX_COMPILER_ARG1="$(CMAKE_CXX_COMPILER_ARG1)" \
			-DCMAKE_EXE_LINKER_FLAGS="$(TARGET_LDFLAGS)" \
			-DCMAKE_MODULE_LINKER_FLAGS="$(TARGET_LDFLAGS)" \
			-DCMAKE_SHARED_LINKER_FLAGS="$(TARGET_LDFLAGS)" \
			-DCMAKE_FIND_ROOT_PATH=$(STAGING_DIR) \
			-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=BOTH \
			-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
			-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
			-DCMAKE_STRIP=: \
			-DCMAKE_INSTALL_PREFIX=/usr \
			$(CMAKE_OPTIONS) \
		.. \
	)
endef

define Build/Compile
	(rm -rf $(PKG_INSTALL_DIR); \
	mkdir -p $(PKG_INSTALL_DIR); \
	cd $(PKG_BUILD_DIR)/hostsoftware/hexadaemon/build; \
	make DESTDIR="$(PKG_INSTALL_DIR)" install \
	)
	echo "compile"
endef

define Build/Install
endef

define Package/hexadaemon/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/hexadaemon.init $(1)/etc/init.d/hexadaemon

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/hexadaemon $(1)/usr/bin/
endef

$(eval $(call BuildPackage,hexadaemon))
