cmake_minimum_required(VERSION 3.22 FATAL_ERROR)

project(protea)


if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set_property(CACHE CMAKE_INSTALL_PREFIX
               PROPERTY VALUE "${CMAKE_BINARY_DIR}/install")
endif()

find_package(Ruby 3.4.8 EXACT REQUIRED)

include(cmake/Bundler.cmake)
include(cmake/CompilerOptions.cmake)
include(cmake/CPM.cmake)
include(CTest)
include(cmake/dependencies.cmake)
include(cmake/softfloat.cmake)

add_subdirectory(lib)
add_subdirectory(sim_lib)
add_subdirectory(sim_gen)

if(UNIT_TESTS)
  add_subdirectory(tests)
endif()
