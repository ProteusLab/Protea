project(protea_irgen)

add_custom_command(
  OUTPUT IR.yaml
  COMMAND ${BUNDLE_PATH} exec ruby ${CMAKE_CURRENT_SOURCE_DIR}/ir_gen.rb
  COMMENT "Running ${PROJECT_NAME}"
)
add_custom_target(${PROJECT_NAME} DEPENDS IR.yaml)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/IR.yaml DESTINATION share/)

add_custom_command(
  OUTPUT devIR.yaml
  COMMAND ${BUNDLE_PATH} exec ruby ${CMAKE_SOURCE_DIR}/exe/plod ir
          ${CMAKE_SOURCE_DIR}/lib/Devices/clint.rb
          ${CMAKE_SOURCE_DIR}/lib/Devices/ns16550.rb
          ${CMAKE_SOURCE_DIR}/lib/Devices/uart8250.rb
          -o ${CMAKE_CURRENT_BINARY_DIR}/devIR.yaml
  COMMENT "Running ${PROJECT_NAME} (devices)"
)
add_custom_target(protea_devirgen DEPENDS devIR.yaml)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/devIR.yaml DESTINATION share/)
