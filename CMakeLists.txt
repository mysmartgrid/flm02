# -*- mode: cmake; -*-
project(flm02)
cmake_minimum_required(VERSION 2.6.2 FATAL_ERROR)
if(POLICY CMP0011)
  cmake_policy(SET CMP0011 NEW)
endif(POLICY CMP0011)

set(FLM02_MAJOR_VERSION 0)
set(FLM02_MINOR_VERSION 1)
set(FLM02_SUB_VERSION   0)
set(VERSION_SEP "-")
set(FLM02_SHORT_VERSION "${FLM02_MAJOR_VERSION}${VERSION_SEP}${FLM02_MINOR_VERSION}")
set(FLM02_VERSION "${FLM02_SHORT_VERSION}${VERSION_SEP}${FLM02_SUB_VERSION}")
set(FLM02_RPM_VERSION "${FLM02_MAJOR_VERSION}.${FLM02_MINOR_VERSION}.${FLM02_SUB_VERSION}")
set(VERSION_DATE "2011-12-15")

###########################################################
# Where are the additional libraries installed? Note: provide includes
# path here, subsequent checks will resolve everything else
set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/modules")


execute_process(
  COMMAND ${CMAKE_SOURCE_DIR}/openwrt/install_kk.sh ${CMAKE_BINARY_DIR}
  WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/openwrt
)
  
add_custom_target(image ALL
  make
  WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/flm02.0.3/"
  COMMENT ""
)


### print some output for the user
message("")
message("        ***** Configuration parameters *****")
message("             prefix: ${CMAKE_INSTALL_PREFIX}")
