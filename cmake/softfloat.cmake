# softfloat: floating point arithmetic library 
CPMAddPackage(
  NAME softfloat
  GITHUB_REPOSITORY ucb-bar/berkeley-softfloat-3
  GIT_TAG a0c6494cdc11865811dec815d5c0049fba9d82a8
  DOWNLOAD_ONLY YES
  EXCLUDE_FROM_ALL True
  SYSTEM True)

# Generate platform.h
set(SOFTFLOAT_PLATFORM_H ${CMAKE_CURRENT_BINARY_DIR}/platform.h)
file(WRITE ${SOFTFLOAT_PLATFORM_H}
"#ifndef SOFTFLOAT_PLATFORM_H
#define SOFTFLOAT_PLATFORM_H

#include <stdint.h>
#include <stdbool.h>

#endif
")

# Collect all required source files
file(GLOB SOFTFLOAT_SRC
  ${softfloat_SOURCE_DIR}/source/*.c
  ${softfloat_SOURCE_DIR}/source/s_*.c
  ${softfloat_SOURCE_DIR}/source/specialize/*.c
)

# Use the RISC-V specialization so NaN handling, default-NaN values and
# float-to-int saturation match the RISC-V F/D spec (e.g. default NaN
# 0x7FC00000, i32_fromNaN 0x7FFFFFFF) rather than the 8086/x86 semantics.
file(GLOB SOFTFLOAT_PLATFORM_SRC
  ${softfloat_SOURCE_DIR}/source/RISCV/*.c
)
set(SOFTFLOAT_PLATFORM_DIR ${softfloat_SOURCE_DIR}/source/RISCV)

list(APPEND SOFTFLOAT_SRC ${SOFTFLOAT_PLATFORM_SRC})

# Exclude unsupported formats
list(FILTER SOFTFLOAT_SRC EXCLUDE REGEX ".*F80.*")
list(FILTER SOFTFLOAT_SRC EXCLUDE REGEX ".*F128.*")
list(FILTER SOFTFLOAT_SRC EXCLUDE REGEX ".*bf16.*")
list(FILTER SOFTFLOAT_SRC EXCLUDE REGEX ".*f16_.*")

# Create the static library
add_library(softfloat STATIC ${SOFTFLOAT_SRC})

target_include_directories(softfloat PUBLIC
  ${softfloat_SOURCE_DIR}/source/include
  ${softfloat_SOURCE_DIR}/source
  ${SOFTFLOAT_PLATFORM_DIR}
  ${CMAKE_CURRENT_BINARY_DIR}
)

target_compile_definitions(softfloat PRIVATE 
  SOFTFLOAT_FAST_INT64
  SOFTFLOAT_FAST_INT64
)
