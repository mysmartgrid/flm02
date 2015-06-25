# Copyright (c) 2010-2013 Stephan Platz

include $(TOPDIR)/rules.mk

PKG_NAME:=libhexabus
PKG_VERSION:=0.4
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/libhexabus
  SECTION:=libs
  CATEGORY:=Libraries
  DEPENDS:=+boost-system +boost-filesystem +boost-program_options +boost-thread +boost-date_time +boost-test
  TITLE:=Libhexabus
  URL:=http://www.hexabus.net
  MAINTAINER:=Stephan Platz <stephan.platz@itwm.fraunhofer.de>
endef

define Package/hexaswitch
  SECTION:=utils
  CATEGORY:=Network
  DEPENDS:=libhexabus
  TITLE:=HexaSwitch
  URL:=http://www.hexabus.net
  MAINTAINER:=Stephan Platz <stephan.platz@itwm.fraunhofer.de>
endef

define Package/libhexabus/description
  This package contains libhexabus, a library to interact with the HexaBus Home Automation Network.
endef

define Package/hexaswitch/description
  Small utility to send and receive hexabus packets.
endef

define Build/Prepare
	sh -c 'if [ -d hexabus ]; then cd hexabus; git pull --rebase; cd ..; else git clone http://github.com/mysmartgrid/hexabus.git -b rel_0.6; fi'

	mkdir -p $(PKG_BUILD_DIR)
	cp -R hexabus/* $(PKG_BUILD_DIR)

	$(Build/Patch)
endef

define Build/Configure
	(cd $(PKG_BUILD_DIR)/hostsoftware/libhexabus; \
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
			-DWITHOUT_CPACK=TRUE \
			$(CMAKE_OPTIONS) \
		.. \
	)
endef

define Build/Compile
	(rm -rf $(PKG_INSTALL_DIR); \
	mkdir -p $(PKG_INSTALL_DIR); \
	cd $(PKG_BUILD_DIR)/hostsoftware/libhexabus/build; \
	make DESTDIR="$(PKG_INSTALL_DIR)" install \
	)
	echo "compile"
endef

define Build/Install
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/libhexabus
	$(CP) $(PKG_INSTALL_DIR)/usr/include/libhexabus/*.{h,hpp} $(1)/usr/include/libhexabus/

	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libhexabus.a $(1)/usr/lib
endef

define Package/libhexabus/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libhexabus.a $(1)/usr/lib
	$(INSTALL_DIR) $(1)/usr/share/libhexabus
	$(CP) $(PKG_INSTALL_DIR)/usr/share/libhexabus/endpoint_registry $(1)/usr/share/libhexabus
endef

define Package/hexaswitch/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/hexaswitch $(1)/usr/bin/
endef

$(eval $(call BuildPackage,libhexabus))
$(eval $(call BuildPackage,hexaswitch))
