# -*- mode: cmake; -*-
#
#  Configure and build OpenWRT environement
#

set(_openwrt_url "git://git.openwrt.org/12.09/openwrt.git")
set(_package_url "git://git.openwrt.org/12.09/packages.git")

option(openwrt_update_feeds "Update OpenWRT package feeds from upstream repositories" ON)

macro(openwrt_checkout_system _target _workdir _url _output)
  message(STATUS "  checkout ${_url}")
  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${_dest}/${_output}
    COMMAND git clone ${_openwrt_url}/ ${_workdir}
    COMMAND cp ${CMAKE_BINARY_DIR}/feeds.conf ${_workdir}/
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/
    COMMENT "Checkout openwrt sources ${_url}"
    )
  add_custom_target(${_target} DEPENDS ${CMAKE_BINARY_DIR}/${_dest}/${_output})
  message(STATUS "   * add checkout-target ${_target}")
endmacro()

macro(openwrt_checkout_package _target _workdir _url _destdir _output )
  message(STATUS "  checkout ${_url}")
  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${_dest}/${_output}
    COMMAND git clone ${_package_url}/${_url} ${_destdir}
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
  openwrt_checkout_system(openwrt_checkout ${_dest} branches/attitude_adjustment Makefile ${_dest})

  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/checkout.done
    COMMAND touch  ${CMAKE_BINARY_DIR}/checkout.done
    DEPENDS openwrt_checkout
  )
  add_custom_target(openwrt_system_checkout
    DEPENDS  ${CMAKE_BINARY_DIR}/checkout.done
  )
  message(STATUS "   * add checkout-target openwrt_system_checkout")

endfunction(openwrt_checkout)

function(openwrt_configure _dest)
  message(STATUS "  openwrt configuring")
  file(WRITE ${CMAKE_BINARY_DIR}/feeds.conf
"src-link msgflukso ${CMAKE_SOURCE_DIR}/openwrt/package
src-git packages https://github.com/openwrt/packages.git
src-git luci http://git.openwrt.org/project/luci.git
")


  add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/feeds.done
    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds update
    COMMAND ${CMAKE_BINARY_DIR}/${_dest}/scripts/feeds install -a -p msgflukso
    COMMAND ${CMAKE_COMMAND} -E touch  ${CMAKE_BINARY_DIR}/feeds.done
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest}
    COMMENT "Update feeds"
    DEPENDS ${CMAKE_BINARY_DIR}/checkout.done
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
    # add patches to the atheros target
    COMMAND ${CMAKE_COMMAND} -E copy patches/300-set_AR2315_RESET_GPIO_to_6.patch ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-3.3
    COMMAND ${CMAKE_COMMAND} -E copy patches/310-register_gpio_leds.patch ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-3.3
    COMMAND ${CMAKE_COMMAND} -E copy patches/320-flm_spi_platform_support.patch ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-3.3
    COMMAND ${CMAKE_COMMAND} -E copy patches/330-export_spi_rst_gpio_to_userspace.patch ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-3.3
    COMMAND ${CMAKE_COMMAND} -E copy patches/340-tune_spi_bitbanging_for_avr.patch ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-3.3
    COMMAND ${CMAKE_COMMAND} -E copy patches/500-early_printk_disable.patch ${CMAKE_BINARY_DIR}/${_dest}/target/linux/atheros/patches-3.3

    # patch the default OpenWRT Lua package
    COMMAND ${CMAKE_COMMAND} -E copy patches/600-lua-tablecreate.patch ${CMAKE_BINARY_DIR}/${_dest}/package/lua/patches

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
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/900-disable_console.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/910-redirect-console-to-devnull.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/915-kernel_posix_mqueue_support.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/920-add-make-flash-option.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/921-add-make-publish-option.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/925-add_mac_address_to_radio0.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/930-boot_crond_without_crontabs.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/940-wpa_supd_hook.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/950-ntpd_supd_hook.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/960-remove_default_banner.patch

    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/965-nixio_tls.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/970-nixio_timerfd.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/971-nixio_spi.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/972-nixio_numexp.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/973-nixio_binary.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/974-httpclient_create_persistent.patch
    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/975-sys_iwinfo.patch

    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/976-rpc.patch

    COMMAND patch -N -p0 < ${CMAKE_SOURCE_DIR}/openwrt/patches/990-crond.patch

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

function(openwrt_update _dest)
  message(STATUS "   openwrt updating")

  add_custom_target(openwrt_system_update
    COMMAND git pull
    DEPENDS openwrt_patch
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest}
    COMMENT "update OpenWRT sources"
  )
  if(${openwrt_update_feeds} STREQUAL "ON")
    set(_openwrt_feeds_update_options "")
  else()
    set(_openwrt_feeds_update_options "-i")
  endif()
  message("Openwrt Feeds Update Command: ./scripts/feeds update ${_openwrt_feeds_update_options}")
  add_custom_target(openwrt_feeds_update
    COMMAND ./scripts/feeds update ${_openwrt_feeds_update_options}
    DEPENDS openwrt_system_update
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest}
    COMMENT "update feeds"
  )
  add_custom_target(openwrt_config_update
    COMMAND make oldconfig
    DEPENDS openwrt_feeds_update
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest}
    COMMENT "update .config"
  )

  add_custom_target(openwrt_update
    DEPENDS openwrt_config_update)

  message(STATUS "   * add target openwrt_update")
endfunction(openwrt_update)

function(openwrt_host)
  set(_modulesDir ${CMAKE_BINARY_DIR}/${_dest}/staging_dir/host/Modules)
  file(MAKE_DIRECTORY ${_modulesDir})
  configure_file(${CMAKE_SOURCE_DIR}/Toolchain-OpenWRT.cmake ${_modulesDir} COPYONLY)
  configure_file(${CMAKE_SOURCE_DIR}/modules/CPackDeb.cmake ${_modulesDir} COPYONLY)
  
endfunction(openwrt_host)

macro(openwrt_env _dest)
  openwrt_checkout(${_dest})
  #file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/${_dest})
  openwrt_configure(${_dest})
  openwrt_patch(${_dest})
  openwrt_update(${_dest})
endmacro(openwrt_env)

function(info)
  message("Order of build targets:")
  message("make openwrt_checkout")
  message("make openwrt_feeds")
  message("make openwrt_patch")
#  message("make openwrt_update")
  message("make openwrt_system_update")
  message("make openwrt_feeds_update")
  message("make openwrt_config_update")
  message("make image")
endfunction(info)
