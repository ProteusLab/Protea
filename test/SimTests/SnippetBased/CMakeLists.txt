project(snippetbased-simtests)

if(PROTEA_BUILD_TESTS)
  string(TOLOWER ${TARGET_NAME} TARGET_NAME_LOWER)
  set(TARGET_TOOLCHAIN_FILE ${protea_SOURCE_DIR}/cmake/toolchain/${TARGET_NAME_LOWER}.cmake)
  set(DEFAULT_ARGS
      -DTARGET_NAME=${TARGET_NAME}
      -DCMAKE_INSTALL_PREFIX:PATH=${CMAKE_INSTALL_PREFIX}
      -DCMAKE_BUILD_TYPE:STRING=Release
      -DCMAKE_TOOLCHAIN_FILE:PATH=${TARGET_TOOLCHAIN_FILE})
  if (DEFINED ${TARGET_NAME}_TOOLCHAIN_DIR)
    list(APPEND DEFAULT_ARGS -D${TARGET_NAME}_TOOLCHAIN_DIR:PATH=${${TARGET_NAME}_TOOLCHAIN_DIR})
  endif()

  set(TESTS_BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/SnippetBasedImpl)
  set(OUTPUT_TESTS_DIR ${CMAKE_CURRENT_BINARY_DIR}/compiled_tests)

  set(RunTests ${tests-common_SOURCE_DIR}/RunTests.py)
  set(GENERATED_SIM_BIN_PATH ${protea_simgen_BINARY_DIR}/sim)

  ExternalProject_Add(
    snippetbased-simtestsimpl
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/SnippetBasedImpl
    BINARY_DIR ${TESTS_BINARY_DIR}
    CONFIGURE_HANDLED_BY_BUILD True
    BUILD_ALWAYS True
    CMAKE_ARGS ${DEFAULT_ARGS} -DQEMU_PATH=${QEMU_PATH} -DBUNDLE_PATH=${BUNDLE_PATH} -DIR_PATH=${protea_irgen_BINARY_DIR}/IR.yaml -DTARGET_NAME=${TARGET_NAME} -DOUTPUT_TESTS_DIR=${OUTPUT_TESTS_DIR}
    INSTALL_COMMAND "")

  add_dependencies(snippetbased-simtestsimpl protea_irgen sim)

  set(DISCOVER_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/discover_generated_tests.cmake")
  configure_file(
    "${CMAKE_SOURCE_DIR}/cmake/discover_generated_tests.cmake.in"
    "${DISCOVER_SCRIPT}"
    @ONLY
  )

  set_property(DIRECTORY APPEND PROPERTY TEST_INCLUDE_FILES "${DISCOVER_SCRIPT}")
endif()

