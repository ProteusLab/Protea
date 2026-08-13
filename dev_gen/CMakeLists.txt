project(protea_devgen)

set(DEVIR_YAML_FILE ${protea_irgen_BINARY_DIR}/devIR.yaml)

set(PROTEA_DEVGEN_DEVICES Clint ns16550 Uart8250)

foreach(dev ${PROTEA_DEVGEN_DEVICES})
  add_custom_command(
    OUTPUT ${dev}.hh
    COMMAND ${BUNDLE_PATH} exec ruby ${CMAKE_CURRENT_SOURCE_DIR}/gen.rb
            ${DEVIR_YAML_FILE} ${dev} ${CMAKE_CURRENT_BINARY_DIR}/${dev}.hh
    DEPENDS ${DEVIR_YAML_FILE}
    COMMENT "Generating device header ${dev}.hh (${PROJECT_NAME})"
  )
  add_custom_target(protea_devgen_${dev} DEPENDS ${dev}.hh)
  add_dependencies(protea_devgen_${dev} protea_devirgen)
  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/${dev}.hh DESTINATION share/)
endforeach()

add_custom_target(${PROJECT_NAME} ALL
  DEPENDS protea_devgen_Clint protea_devgen_ns16550 protea_devgen_Uart8250)
