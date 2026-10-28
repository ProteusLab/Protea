if(NOT DEFINED BUNDLE_PATH)
  set(BUNDLE_PATH "bundle")
endif()

set(BUNDLE_STAMP ${CMAKE_BINARY_DIR}/bundle/.installed)

add_custom_command(
  OUTPUT ${BUNDLE_STAMP}
  COMMAND ${BUNDLE_PATH} config set --local path ${CMAKE_BINARY_DIR}/bundle
  COMMAND ${BUNDLE_PATH} install
  COMMAND ${CMAKE_COMMAND} -E touch ${BUNDLE_STAMP}
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMENT "Installing gems with bundler"
)

add_custom_target(bundle-install DEPENDS ${BUNDLE_STAMP})
