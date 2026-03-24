cmake_minimum_required(VERSION 3.22 FATAL_ERROR)

project(protea)

set(TARGET_NAME RISCV)

option(PROTEA_BUILD_TESTS
       "Enable tests build (requires riscv gnu toolchain)" OFF)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set_property(CACHE CMAKE_INSTALL_PREFIX
               PROPERTY VALUE "${CMAKE_BINARY_DIR}/install")
endif()

find_package(Ruby 3.4.8 EXACT REQUIRED)
find_package(Python3 3.12 EXACT REQUIRED COMPONENTS Interpreter)
message("Python found: ${Python3_EXECUTABLE}")

include(ExternalProject)
include(cmake/Bundler.cmake)
include(cmake/QEMU.cmake)
include(cmake/CompilerOptions.cmake)
include(cmake/CPM.cmake)
include(cmake/dependencies.cmake)
include(cmake/CompilerConfig.cmake)

if(PROTEA_BUILD_TESTS)
  enable_testing()
endif()

add_subdirectory(lib)
add_subdirectory(sim_lib)
add_subdirectory(sim_gen)
add_subdirectory(test)
