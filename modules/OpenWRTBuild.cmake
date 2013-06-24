# -*- mode: cmake; -*-
#
#  Configure and build OpenWRT environement
#

set(ENV{http_proxy} "http://squid.itwm.fhg.de:3128/")

set(_openwrt_url "svn://svn.openwrt.org/openwrt/")
#set(_openwrt_url "svn://localhost/openwrt/")

macro(openwrt_checkout_system _target _workdir _url _output)
  message(STATUS "  checkout ${_url}")
  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${_dest}/${_output}
    COMMAND svn co ${_openwrt_url}/${_url} -r 27608 .
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/${_workdir}
    COMMENT "Checkout openwrt sources ${_url} -r 27608"
    )
  add_custom_target(${_target} DEPENDS ${CMAKE_BINARY_DIR}/${_dest}/${_output})
  message(STATUS "   * add checkout-target ${_target}")
endmacro()

macro(openwrt_checkout_package _target _workdir _url _destdir _output )
  message(STATUS "  checkout ${_url}")
  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${_dest}/${_output}
    COMMAND svn co ${_openwrt_url}/${_url} ${_destdir}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/${_workdir}
    DEPENDS ${CMAKE_BINARY_DIR}/${_dest}/Makefile
    COMMENT "Checkout openwrt sources ${_url}"
    )
  add_custom_target(${_target} DEPENDS ${CMAKE_BINARY_DIR}/${_dest}/${_output})
  message(STATUS "   * add checkout-target ${_target}")
endmacro()

#
#
function(openwrt_checkout _dest)
#  openwrt_checkout_system(openwrt_checkout openwrt branches/backfire Makefile)
  openwrt_checkout_system(openwrt_checkout ${_dest} branches/backfire Makefile ${_dest})

  openwrt_checkout_package(openwrt_package_ntpd ${_dest}/package branches/packages_10.03.1/net/ntpd ntpd package/ntpd/Makefile)

  #openwrt_checkout_package(openwrt_package_sqlite3 openwrt/package packages/libs/sqlite3 sqlite3 package/sqlite3/Makefile)

  #openwrt_checkout_package(openwrt_package_boost openwrt/package packages/libs/boost boost package/boost/Makefile)

  #openwrt_checkout_package(openwrt_package_curl openwrt/package packages/libs/curl curl package/curl/Makefile)

  #openwrt_checkout_package(openwrt_package_libmicrohttpd openwrt/package packages/libs/libmicrohttpd libmicrohttpd package/libmicrohttpd/Makefile)

  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/package.done
    COMMAND touch  ${CMAKE_BINARY_DIR}/package.done
    DEPENDS
    ${CMAKE_BINARY_DIR}/${_dest}/package/ntpd/Makefile
#    ${CMAKE_BINARY_DIR}/${_dest}/package/libmicrohttpd/Makefile
#    ${CMAKE_BINARY_DIR}/${_dest}/package/curl/Makefile
#    ${CMAKE_BINARY_DIR}/${_dest}/package/boost/Makefile
  )
  add_custom_target(openwrt_package
    DEPENDS  ${CMAKE_BINARY_DIR}/package.done
  )
  add_dependencies(openwrt_package openwrt_checkout)
  message(STATUS "   * add checkout-target openwrt_package")

endfunction(openwrt_checkout)

function(openwrt_configure _dest _target)
  message(STATUS "  openwrt configuring")
  file(WRITE ${CMAKE_BINARY_DIR}/${_dest}/feeds.conf
#    "src-link itwm ${CMAKE_SOURCE_DIR}/openwrt/package
"src-link msgflukso ${CMAKE_SOURCE_DIR}/openwrt/package
src-svn packages svn://svn.openwrt.org/openwrt/packages
")


  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/feeds.done
    
    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds update
#    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds update -a itwm
    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -a -p msgflukso
    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -p packages ntp
#    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install  openssl
#    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -p itwm libsml
#    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -p itwm qt4
#    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -p packages uuid
#    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -p packages boost
#    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -p packages sqlite3
#    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -p packages curl
#    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -p packages libmicrohttpd
#    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -p packages libjson
#    COMMAND echo "CONFIG_PACKAGE_libsml=y" >> .config
    COMMAND touch  ${CMAKE_BINARY_DIR}/feeds.done
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest}
    COMMENT "Update feeds"
    DEPENDS ${CMAKE_BINARY_DIR}/package.done
    )

  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/install.done
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_SOURCE_DIR}/openwrt/.config ${CMAKE_BINARY_DIR}/${_dest}
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/openwrt/files ${CMAKE_BINARY_DIR}/${_dest}
    COMMAND ${CMAKE_SOURCE_DIR}/openwrt/install_kk.sh  ${CMAKE_BINARY_DIR}/
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/openwrt
    COMMENT "run installation script"
    DEPENDS ${CMAKE_BINARY_DIR}/feeds.done
    )

  add_custom_target(openwrt_feeds DEPENDS ${CMAKE_BINARY_DIR}/install.done)
  add_dependencies(openwrt_feeds openwrt_package)
  set(${_target} "openwrt_feeds" PARENT_SCOPE)
  message(STATUS "   * add checkout-target openwrt_feeds")
#  configure_file(dot.config_${DEST_TARGET} ${CMAKE_BINARY_DIR}/${_dest}/.config)
#  file(APPEND ${CMAKE_BINARY_DIR}/${_dest}/.config
#    "CONFIG_PACKAGE_ntpd=y
#")
#CONFIG_PACKAGE_libboost=m
#CONFIG_PACKAGE_libcurl=m
#CONFIG_PACKAGE_libsml=m
#CONFIG_PACKAGE_libmicrohttpd=m
#CONFIG_PACKAGE_libsqlite3=m
#CONFIG_PACKAGE_libuuid=y
#CONFIG_PACKAGE_libopenssl=y
#CONFIG_PACKAGE_libpthread=y
#CONFIG_PACKAGE_librt=y
#CONFIG_PACKAGE_zlib=y
#CONFIG_PACKAGE_e2fsprogs=y
#CONFIG_PACKAGE_libext2fs=y
#
#CONFIG_PACKAGE_boost-chrono=m
#CONFIG_PACKAGE_boost-date_time=m
#CONFIG_PACKAGE_boost-filesystem=m
#CONFIG_PACKAGE_boost-graph=m
#CONFIG_PACKAGE_boost-iostreams=m
#CONFIG_PACKAGE_boost-locale=m
#CONFIG_PACKAGE_boost-math=m
#CONFIG_PACKAGE_boost-program_options=m
#CONFIG_PACKAGE_boost-random=m
#CONFIG_PACKAGE_boost-regex=m
#CONFIG_PACKAGE_boost-serialization=m
#CONFIG_PACKAGE_boost-signals=m
#CONFIG_PACKAGE_boost-system=m
#CONFIG_PACKAGE_boost-test=m
#CONFIG_PACKAGE_boost-thread=m
#CONFIG_PACKAGE_boost-timer=m
#CONFIG_PACKAGE_boost-wave=m
#
#CONFIG_BUSYBOX_CONFIG_STTY=y
#CONFIG_BUSYBOX_CONFIG_MODPROBE=y
#
#CONFIG_PACKAGE_kmod-usb-serial=y
#CONFIG_PACKAGE_kmod-usb-serial-airprime=y
#CONFIG_PACKAGE_kmod-usb-serial-ark3116=y
#CONFIG_PACKAGE_kmod-usb-serial-belkin=y
#CONFIG_PACKAGE_kmod-usb-serial-ch341=y
#CONFIG_PACKAGE_kmod-usb-serial-cp210x=y
#CONFIG_PACKAGE_kmod-usb-serial-cypress-m8=y
#CONFIG_PACKAGE_kmod-usb-serial-ftdi=y
#CONFIG_PACKAGE_kmod-usb-serial-keyspan=y
#CONFIG_PACKAGE_kmod-usb-serial-mct=y
#CONFIG_PACKAGE_kmod-usb-serial-motorola-phone=y
#CONFIG_PACKAGE_kmod-usb-serial-option=y
#CONFIG_PACKAGE_kmod-usb-serial-oti6858=y
#CONFIG_PACKAGE_kmod-usb-serial-pl2303=y
#CONFIG_PACKAGE_kmod-usb-serial-sierrawireless=y
#CONFIG_PACKAGE_kmod-usb-serial-visor=y
#CONFIG_PACKAGE_kmod-usb-storage=m
#CONFIG_SDK=y
#CONFIG_MAKE_TOOLCHAIN=y
#CONFIG_PACKAGE_qt4=y
#")

endfunction(openwrt_configure)

function(openwrt_host)
  set(_modulesDir ${CMAKE_BINARY_DIR}/${_dest}/staging_dir/host/Modules)
  file(MAKE_DIRECTORY ${_modulesDir})
  configure_file(${CMAKE_SOURCE_DIR}/Toolchain-OpenWRT.cmake ${_modulesDir} COPYONLY)
  configure_file(${CMAKE_SOURCE_DIR}/modules/CPackDeb.cmake ${_modulesDir} COPYONLY)
  
#  file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest}/host)

endfunction(openwrt_host)

macro(openwrt_env _dest _target)
  file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest})
  openwrt_checkout(${_dest})
  openwrt_configure(${_dest} ${_target})
  message(STATUS "   * add openwrt_env ${${_target}}")
  #openwrt_host()
endmacro(openwrt_env)