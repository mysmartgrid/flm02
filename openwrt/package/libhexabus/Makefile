# Copyright (c) 2010-2013 Stephan Platz

include $(TOPDIR)/rules.mk

PKG_NAME:=libhexabus
PKG_VERSION:=0.1
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

define Package/libhexabus/description
	This package contains libhexabus, a library to interact with the HexaBus Home Automation Network
endef

define Build/Prepare
	sh -c 'if [ -d hexabus ]; then cd hexabus; git pull --rebase; cd ..; else git clone http://github.com/mysmartgrid/hexabus.git -b development; fi'

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
			$(CMAKE_OPTIONS) \
		.. \
	)
endef

define Build/Compile
	(cd $(PKG_BUILD_DIR)/hostsoftware/libhexabus/build; \
	make \
	)
endef

define Package/libhexabus/install
endef

$(eval $(call BuildPackage,libhexabus))
