project(protea_irgen)

add_custom_command(
  OUTPUT ${PROJECT_BINARY_DIR}/IR.yaml
  DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/ir_gen.rb
  COMMAND ${BUNDLE_PATH} exec ruby ${CMAKE_CURRENT_SOURCE_DIR}/ir_gen.rb
  COMMENT "Running ${PROJECT_NAME}"
)
add_custom_target(${PROJECT_NAME} DEPENDS ${PROJECT_BINARY_DIR}/IR.yaml)
install(FILES ${PROJECT_BINARY_DIR}/IR.yaml DESTINATION share/)
