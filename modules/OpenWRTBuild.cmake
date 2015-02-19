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
    COMMAND svn co ${_openwrt_url}/${_url} .
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/${_workdir}
    COMMENT "Checkout openwrt sources ${_url}"
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
  openwrt_checkout_system(openwrt_checkout ${_dest} branches/backfire Makefile ${_dest})

  openwrt_checkout_package(openwrt_package_ntpd ${_dest}/package branches/packages_10.03.1/net/ntpd ntpd package/ntpd/Makefile)

  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/package.done
    COMMAND touch  ${CMAKE_BINARY_DIR}/package.done
    DEPENDS
    ${CMAKE_BINARY_DIR}/${_dest}/package/ntpd/Makefile
  )
  add_custom_target(openwrt_package
    DEPENDS  ${CMAKE_BINARY_DIR}/package.done
  )
  add_dependencies(openwrt_package openwrt_checkout)
  message(STATUS "   * add checkout-target openwrt_package")

endfunction(openwrt_checkout)

function(openwrt_configure _dest)
  message(STATUS "  openwrt configuring")
  file(WRITE ${CMAKE_BINARY_DIR}/${_dest}/feeds.conf
"src-link msgflukso ${CMAKE_SOURCE_DIR}/openwrt/package
src-svn packages svn://svn.openwrt.org/openwrt/branches/packages_10.03.2 svn://svn.openwrt.org/openwrt/packages
")


  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/feeds.done
    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds update
    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -a -p msgflukso
    COMMAND ${CMAKE_COMMAND} -E touch  ${CMAKE_BINARY_DIR}/feeds.done
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest}
    COMMENT "Update feeds"
    DEPENDS ${CMAKE_BINARY_DIR}/package.done
    )

  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/install.done
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_SOURCE_DIR}/openwrt/.config ${CMAKE_BINARY_DIR}/${_dest}
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/openwrt/files ${CMAKE_BINARY_DIR}/${_dest}/files
    COMMAND ${CMAKE_COMMAND} -E touch  ${CMAKE_BINARY_DIR}/install.done
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/openwrt
    COMMENT "run installation script"
    DEPENDS ${CMAKE_BINARY_DIR}/feeds.done
    )

  add_custom_target(openwrt_feeds DEPENDS ${CMAKE_BINARY_DIR}/install.done)
  add_dependencies(openwrt_feeds openwrt_package)
  message(STATUS "   * add checkout-target openwrt_feeds")

endfunction(openwrt_configure)

function(openwrt_patch _dest)
  message(STATUS "   openwrt patching")

  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/copy_patches.done
    # add patches to the toolchain
    COMMAND ${CMAKE_COMMAND} -E copy patches/990-add_timerfd_support.patch ${CMAKE_BINARY_DIR}/${_dest}/toolchain/uClibc/patches-0.9.30.1
    # add patches to the linux atheros target
    COMMAND ${CMAKE_COMMAND} -E copy patches/"300-set_AR2315_RESET_GPIO_to_6.patch" ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-2.6.30
    COMMAND ${CMAKE_COMMAND} -E copy patches/"310-hotplug_button_jiffies_calc.patch" ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-2.6.30
    COMMAND ${CMAKE_COMMAND} -E copy patches/"400-spi_gpio_support.patch" ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-2.6.30
    COMMAND ${CMAKE_COMMAND} -E copy patches/"410-spi_gpio_enable_cs_line.patch" ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-2.6.30
    COMMAND ${CMAKE_COMMAND} -E copy patches/"420-tune_spi_bitbanging_for_avr.patch" ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-2.6.30
    # backport loglevel fix to busybox v1.15.3-2
    # see: https://bugs.busybox.net/show_bug.cgi?id=681
    COMMAND ${CMAKE_COMMAND} -E copy patches/820-fix_crond_loglevel.patch ${CMAKE_BINARY_DIR}/${_dest}/package/busybox/patches
    # patch the default OpenWRT Lua package
    COMMAND ${CMAKE_COMMAND} -E remove ${CMAKE_BINARY_DIR}/package/lua/patches/400-luaposix_5.1.4-embedded.patch
    COMMAND ${CMAKE_COMMAND} -E remove ${CMAKE_BINARY_DIR}/package/lua/patches/500-eglibc_config.patch
    COMMAND ${CMAKE_COMMAND} -E copy patches/600-lua-tablecreate.patch ${CMAKE_BINARY_DIR}/${_dest}/package/lua/patches
    # patch squashfs to support setuid
    COMMAND ${CMAKE_COMMAND} -E copy patches/900-squashfs-mode.patch ${CMAKE_BINARY_DIR}/${_dest}/tools/squashfs4/patches
    # copy flash utility to the tools dir
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_SOURCE_DIR}/tools/ap51-flash ${CMAKE_BINARY_DIR}/${_dest}/tools
    COMMAND ${CMAKE_COMMAND} -E touch ${CMAKE_BINARY_DIR}/copy_patches.done
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/openwrt
    COMMENT "copy patches"
    DEPENDS openwrt_feeds
  )

  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/apply_patches.done
    # patch files of the OpenWRT build system
    COMMAND patch -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/"900-disable_console.patch"
    COMMAND patch -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/"900-setuid-ntpclient.patch"
    COMMAND patch -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/"910-set_ttyS0_baud_to_115200.patch"
    COMMAND patch -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/"911-enable_ipv6_router_pref.patch"
    COMMAND patch -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/"920-add-make-flash-option.patch"
    COMMAND patch -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/"921-add-make-publish-option.patch"
    COMMAND patch -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/"950-crond.patch"
    # we don't need rdate, relying on ntpclient instead
    COMMAND ${CMAKE_COMMAND} -E remove ${CMAKE_BINARY_DIR}/package/base-files/files/etc/hotplug.d/iface/40-rdate
    COMMAND ${CMAKE_COMMAND} -E touch ${CMAKE_BINARY_DIR}/apply_patches.done
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest}
    COMMENT "apply patches"
    DEPENDS openwrt_feeds
  )

  add_custom_target(openwrt_patch
    DEPENDS  ${CMAKE_BINARY_DIR}/copy_patches.done ${CMAKE_BINARY_DIR}/apply_patches.done
  )
  message(STATUS "   * add checkout-target openwrt_patch")
endfunction(openwrt_patch)

function(openwrt_host)
  set(_modulesDir ${CMAKE_BINARY_DIR}/${_dest}/staging_dir/host/Modules)
  file(MAKE_DIRECTORY ${_modulesDir})
  configure_file(${CMAKE_SOURCE_DIR}/Toolchain-OpenWRT.cmake ${_modulesDir} COPYONLY)
  configure_file(${CMAKE_SOURCE_DIR}/modules/CPackDeb.cmake ${_modulesDir} COPYONLY)
  
endfunction(openwrt_host)

macro(openwrt_env _dest)
  file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest})
  openwrt_checkout(${_dest})
  openwrt_configure(${_dest})
  openwrt_patch(${_dest})
endmacro(openwrt_env)
