# -*- mode: cmake; -*-
project(flm02)
cmake_minimum_required(VERSION 2.6.2 FATAL_ERROR)
if(POLICY CMP0011)
  cmake_policy(SET CMP0011 NEW)
endif(POLICY CMP0011)

file(STRINGS openwrt/package/msg-flukso/Makefile VERSION
  REGEX "PKG_VERSION:=.*")
#VERSION=$(grep PKG_VERSION:= package/msg-flukso/Makefile | sed 's/.*:=[0-9]\.//')
message("=== Version: ${VERSION} ===")
string(REGEX REPLACE "PKG_VERSION:=([0-9]+).([0-9]+).([0-9]+)" "\\1" FLM02_MAJOR_VERSION ${VERSION})
string(REGEX REPLACE "PKG_VERSION:=([0-9]+).([0-9]+).([0-9]+)" "\\2" FLM02_MINOR_VERSION ${VERSION})
string(REGEX REPLACE "PKG_VERSION:=([0-9]+).([0-9]+).([0-9]+)" "\\3" FLM02_SUB_VERSION ${VERSION})

set(VERSION_SEP "-")
set(FLM02_SHORT_VERSION "${FLM02_MAJOR_VERSION}${VERSION_SEP}${FLM02_MINOR_VERSION}")
set(FLM02_VERSION "${FLM02_SHORT_VERSION}${VERSION_SEP}${FLM02_SUB_VERSION}")
set(FLM02_RPM_VERSION "${FLM02_MAJOR_VERSION}.${FLM02_MINOR_VERSION}.${FLM02_SUB_VERSION}")
set(VERSION_DATE "2011-12-15")

message("=== Version: ${FLM02_RPM_VERSION} ===")
###########################################################
# Where are the additional libraries installed? Note: provide includes
# path here, subsequent checks will resolve everything else
set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/modules")
set(FLM_BUILD_DIR "flm02.${FLM02_MINOR_VERSION}.${FLM02_SUB_VERSION}/" CACHE  FILEPATH "flm build directory")
set(FLM_FULL_BUILD_DIR "${CMAKE_BINARY_DIR}/${FLM_BUILD_DIR}" CACHE  FILEPATH "flm build directory")
include(OpenWRTBuild)

openwrt_env(${FLM_BUILD_DIR})


#execute_process(
#  COMMAND ${CMAKE_SOURCE_DIR}/openwrt/install_kk.sh ${CMAKE_BINARY_DIR}
#  WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/openwrt
#)
 
if (NOT ${CMAKE_BUILD_TYPE} MATCHES "Release")
  message("Is not release. Modify opkg.conf")
  set(_file_opkg_conf "${FLM_BUILD_DIR}/package/opkg/files/opkg.conf")
  file(READ ${_file_opkg_conf} opkg_conf)
  string(REGEX REPLACE "(.*)[\$]S/packages(.*)" "\\1$S/devel/packages\\2"
    opkg_conf_new ${opkg_conf})
  file(WRITE ${_file_opkg_conf} ${opkg_conf_new})
#message("==>${opkg_conf_new}<==")
endif (NOT ${CMAKE_BUILD_TYPE} MATCHES "Release")

add_custom_target(image ALL
  make
  WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/${FLM_BUILD_DIR}/"
  COMMENT ""
  DEPENDS ${CMAKE_BINARY_DIR}/feeds.done
)

### print some output for the user
message("")
message("        ***** Configuration parameters *****")
message("             prefix: ${CMAKE_INSTALL_PREFIX}")
