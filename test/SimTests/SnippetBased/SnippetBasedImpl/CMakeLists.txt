cmake_minimum_required(VERSION 3.22 FATAL_ERROR)

project(tests LANGUAGES CXX C ASM)

set(INIT_DIR "${CMAKE_CURRENT_BINARY_DIR}/init")
set(BIN_DIR  "${CMAKE_CURRENT_BINARY_DIR}/init_bin")
set(QEMU_LOG_DIR "${CMAKE_CURRENT_BINARY_DIR}/qemu_log")
set(OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/tests")

add_custom_target(init-tests
  ALL
  COMMAND ${CMAKE_COMMAND} -E make_directory "${INIT_DIR}"
  COMMAND ${BUNDLE_PATH} exec ruby ${CMAKE_CURRENT_SOURCE_DIR}/InitTestGen.rb
    ${IR_PATH} ${CMAKE_CURRENT_SOURCE_DIR}/Target/${TARGET_NAME}/Snippets ${INIT_DIR}
  COMMENT "Generating test .s files"
)

set(COMPILER      "${CMAKE_C_COMPILER}")
set(COMPILER_FLAGS
    "${CMAKE_C_FLAGS} ${CMAKE_EXE_LINKER_FLAGS}"
    CACHE INTERNAL "Compiler flags for assembling and linking"
)

set(SCRIPT_PATH "${CMAKE_CURRENT_SOURCE_DIR}/compile-and-run.sh")
set(COMPILE_SCRIPT_PATH "${CMAKE_CURRENT_SOURCE_DIR}/compile-dir.sh")

add_custom_target(run-qemu-tests
  ALL
  DEPENDS init-tests
  COMMAND ${CMAKE_COMMAND} -E make_directory "${BIN_DIR}"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${QEMU_LOG_DIR}"
  COMMAND "${SCRIPT_PATH}"
    "${INIT_DIR}"
    "${BIN_DIR}"
    "${COMPILER}"
    "${QEMU_PATH}"
    "${QEMU_LOG_DIR}"
    "${COMPILER_FLAGS}"
  COMMENT "Compile all .s files and run each with QEMU"
  VERBATIM
)

add_custom_target(gen-tests
  ALL
  DEPENDS run-qemu-tests
  COMMAND ${CMAKE_COMMAND} -E make_directory "${OUTPUT_DIR}"
  COMMAND ${BUNDLE_PATH} exec ruby "${CMAKE_CURRENT_SOURCE_DIR}/TestGen.rb"
    "${IR_PATH}" "${CMAKE_CURRENT_SOURCE_DIR}/Target/${TARGET_NAME}/Snippets" "${INIT_DIR}" "${QEMU_LOG_DIR}" "${OUTPUT_DIR}")

add_custom_target(compile-tests
  ALL
  DEPENDS gen-tests
  COMMAND ${CMAKE_COMMAND} -E make_directory "${OUTPUT_TESTS_DIR}"
  COMMAND ${COMPILE_SCRIPT_PATH} "${OUTPUT_DIR}" "${OUTPUT_TESTS_DIR}" "${COMPILER}" "${COMPILER_FLAGS}") 
