# elfio: ELF Loader Library
CPMAddPackage(
  NAME elfio
  GITHUB_REPOSITORY serge1/ELFIO
  GIT_TAG Release_3.12
  EXCLUDE_FROM_ALL True
  SYSTEM True)

# CLI11: Command Line Input argument parser library
CPMAddPackage(
  NAME CLI11
  GITHUB_REPOSITORY CLIUtils/CLI11
  VERSION 2.5.0
  EXCLUDE_FROM_ALL True
  SYSTEM True)

# fmt: Format Library
CPMAddPackage(
  NAME fmt
  GITHUB_REPOSITORY fmtlib/fmt
  GIT_TAG 12.0.0
  EXCLUDE_FROM_ALL True
  SYSTEM True)

# Add GTest for unit testing.
if(UNIT_TESTS)
  # GoogleTest: C++ unit testing framework
  CPMAddPackage(
    NAME googletest
    GITHUB_REPOSITORY google/googletest
    GIT_TAG v1.17.0
    VERSION 1.17.0
    EXCLUDE_FROM_ALL True
    SYSTEM True
    OPTIONS
      "INSTALL_GTEST OFF"
      "gtest_force_shared_crt ON")
endif()
