# RISC-V Cross Compilation Toolchain File Usage: cmake
# -DCMAKE_TOOLCHAIN_FILE=path/to/this/file.cmake ..

# Base settings
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv)
set(CMAKE_LINKER_TYPE DEFAULT)

# Toolchain prefix (modify this according to your toolchain) Common prefixes:
# riscv64-unknown-elf-, riscv64-unknown-linux-gnu-, riscv32-unknown-elf-
set(RISCV_TOOLCHAIN_PREFIX
    "riscv32-unknown-elf-"
    CACHE STRING "RISC-V toolchain prefix")

# Target architecture (modify these according to your needs)
set(RISCV_ARCH
    "rv32i"
    CACHE STRING "RISC-V architecture")
set(RISCV_ABI
    "ilp32"
    CACHE STRING "RISC-V ABI")

# Cross-compilation tools
if(DEFINED RISCV_TOOLCHAIN_DIR)
  set(CMAKE_C_COMPILER "${RISCV_TOOLCHAIN_DIR}/${RISCV_TOOLCHAIN_PREFIX}gcc")
  set(CMAKE_CXX_COMPILER "${RISCV_TOOLCHAIN_DIR}/${RISCV_TOOLCHAIN_PREFIX}g++")
  set(CMAKE_ASM_COMPILER "${RISCV_TOOLCHAIN_DIR}/${RISCV_TOOLCHAIN_PREFIX}gcc")
  set(CMAKE_AR "${RISCV_TOOLCHAIN_DIR}/${RISCV_TOOLCHAIN_PREFIX}ar")
  set(CMAKE_RANLIB "${RISCV_TOOLCHAIN_DIR}/${RISCV_TOOLCHAIN_PREFIX}ranlib")
else()
  set(CMAKE_C_COMPILER "${RISCV_TOOLCHAIN_PREFIX}gcc")
  set(CMAKE_CXX_COMPILER "${RISCV_TOOLCHAIN_PREFIX}g++")
  set(CMAKE_ASM_COMPILER "${RISCV_TOOLCHAIN_PREFIX}gcc")
  set(CMAKE_AR "${RISCV_TOOLCHAIN_PREFIX}ar")
  set(CMAKE_RANLIB "${RISCV_TOOLCHAIN_PREFIX}ranlib")
endif()

# Compiler flags Search settings
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Optional: Specify sysroot if needed set(CMAKE_SYSROOT
# "/path/to/riscv/sysroot")

# Optional: Additional flags for specific use cases
set(COMMON_FLAGS
    "-march=${RISCV_ARCH} -mabi=${RISCV_ABI} -Wall -Wextra -nostdlib -nodefaultlibs -nostartfiles -static -fno-builtin"
)
set(CMAKE_C_FLAGS
    "${COMMON_FLAGS}"
    CACHE STRING "C compiler flags")
set(CMAKE_ASM_FLAGS
    "${COMMON_FLAGS}"
    CACHE STRING "ASM compiler flags")

set(CMAKE_EXE_LINKER_FLAGS_INIT
    "-nostdlib -nodefaultlibs -nostartfiles -fno-builtin -static"
    CACHE STRING "Linker flags")

# Test compiler
if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.6)
  set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
endif()
