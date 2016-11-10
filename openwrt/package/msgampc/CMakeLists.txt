# -*- mode: cmake; -*-
project(msgampc)

cmake_minimum_required(VERSION 2.6.2 FATAL_ERROR)
if(POLICY CMP0011)
  cmake_policy(SET CMP0011 NEW)
endif(POLICY CMP0011)

set(MSGAMPC_MAJOR_VERSION 0)
set(MSGAMPC_MINOR_VERSION 1)
set(MSGAMPC_SUB_VERSION   0)
set(VERSION_SEP "-")
set(MSGAMPC_SHORT_VERSION "${MSGAMPC_MAJOR_VERSION}${VERSION_SEP}${MSGAMPC_MINOR_VERSION}")
set(MSGAMPC_VERSION "${MSGAMPC_SHORT_VERSION}${VERSION_SEP}${MSGAMPC_SUB_VERSION}")
set(MSGAMPC_RPM_VERSION "${MSGAMPC_MAJOR_VERSION}.${MSGAMPC_MINOR_VERSION}.${MSGAMPC_SUB_VERSION}")
set(VERSION_DATE "2016-11-08")

set(GOROOT "/tmp/krueger/go/mips/go-mips32")

###########################################################
# Where are the additional libraries installed? Note: provide includes
# path here, subsequent checks will resolve everything else
set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/modules")

### print some output for the user
message("")
message("        ***** Configuration parameters *****")
message("             prefix: ${CMAKE_INSTALL_PREFIX}")

file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/pkg)
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/src/github.com/mysmartgrid)

set(SRCDIR "${CMAKE_BINARY_DIR}/src/github.com/mysmartgrid/msg-prototype-2")

set(ENV{GOROOT} ${GOROOT})
set(ENV{GOPATH} ${CMAKE_BINARY_DIR})
set(PATH   "${GOROOT}/bin:${CMAKE_BINARY_DIR}/bin:$ENV{PATH}")
set(ENV{PATH}   "${GOROOT}/bin:${CMAKE_BINARY_DIR}/bin:$ENV{PATH}")

execute_process(
  COMMAND go get github.com/Masterminds/glide
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_custom_target(configure 
  COMMAND GOPATH=${CMAKE_BINARY_DIR} GOROOT=${GOROOT} PATH=${PATH} glide update
  COMMAND GOPATH=${CMAKE_BINARY_DIR} GOROOT=${GOROOT} PATH=${PATH} glide install
  WORKING_DIRECTORY ${SRCDIR}
  COMMENT "Configure and make depend"
)

add_custom_target(build 
  COMMAND GOPATH=${CMAKE_BINARY_DIR} GOROOT=${GOROOT} PATH=${PATH} GOARCH=mips32 go build ./cmd/msgampc
  WORKING_DIRECTORY ${SRCDIR}
  COMMENT "Configure and make depend"
)
