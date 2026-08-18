project(protea_tests)

include(GoogleTest)

add_executable(rv64f_tests
  rv64f/rv64f_tests.cc
  ${protea_simgen_BINARY_DIR}/decoder.cc
  ${protea_simgen_BINARY_DIR}/naive_interpreter.cc
  ${protea_simgen_BINARY_DIR}/base_exec_engine.cc
  ${protea_simlib_SOURCE_DIR}/memory.cc
)

add_dependencies(rv64f_tests protea_simgen)

target_include_directories(rv64f_tests
  PRIVATE
    ${protea_simgen_BINARY_DIR}
    ${protea_simlib_SOURCE_DIR}
)

target_link_libraries(rv64f_tests
  PRIVATE
    GTest::gtest_main
    softfloat
)

target_compile_features(rv64f_tests PRIVATE cxx_std_23)

gtest_discover_tests(rv64f_tests)
