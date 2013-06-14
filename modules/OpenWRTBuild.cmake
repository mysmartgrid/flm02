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
src-svn packages svn://svn.openwrt.org/openwrt/packages
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
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/openwrt/files ${CMAKE_BINARY_DIR}/${_dest}
    COMMAND ${CMAKE_SOURCE_DIR}/openwrt/install_kk.sh  ${CMAKE_BINARY_DIR}/
    COMMAND ${CMAKE_COMMAND} -E touch  ${CMAKE_BINARY_DIR}/install.done
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/openwrt
    COMMENT "run installation script"
    DEPENDS ${CMAKE_BINARY_DIR}/feeds.done
    )

  add_custom_target(openwrt_feeds DEPENDS ${CMAKE_BINARY_DIR}/install.done)
  add_dependencies(openwrt_feeds openwrt_package)
  message(STATUS "   * add checkout-target openwrt_feeds")

endfunction(openwrt_configure)

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
endmacro(openwrt_env)
