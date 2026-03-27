project(tests LANGUAGES C ASM)

add_subdirectory(Target)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

macro(protea_add_test tar)
  add_executable(${tar} ${ARGN})
  target_link_libraries(${tar} PRIVATE tests_startup)
endmacro()

add_subdirectory(fib)
add_subdirectory(qsort)
