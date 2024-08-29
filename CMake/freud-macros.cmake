# Use CMake's newer config-based package finding before falling back to the old
# find package mechanism.
macro(find_package_config_first package)
  # VERSION_GREATER_EQUAL requires CMake >=3.7, so use NOT ... VERSION_LESS
  if(NOT ${CMAKE_VERSION} VERSION_LESS 3.15)
    set(_old_prefer_config ${CMAKE_FIND_PACKAGE_PREFER_CONFIG})
    set(CMAKE_FIND_PACKAGE_PREFER_CONFIG TRUE)
    find_package(${package} ${ARGN})
    set(CMAKE_FIND_PACKAGE_PREFER_CONFIG ${_old_prefer_config})
  else()
    find_package(${package} QUIET CONFIG ${ARGN})
    if(NOT ${package}_FOUND)
      find_package(${package} MODULE ${ARGN} REQUIRED)
    endif()
  endif()
endmacro()

# set the rpath for installing python extension modules
function(target_set_install_rpath _target)
  if(_using_conda)
    set_target_properties(${_target} PROPERTIES INSTALL_RPATH_USE_LINK_PATH
                                                True)
  endif()
endfunction()
