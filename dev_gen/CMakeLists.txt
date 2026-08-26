project(protea_devgen)

set(PROTEA_DEVGEN_DEVICES Clint ns16550 Uart8250)

foreach(dev ${PROTEA_DEVGEN_DEVICES})
  string(TOLOWER "${dev}" dev_src)
  add_custom_command(
    OUTPUT ${dev}.hh
    COMMAND ${BUNDLE_PATH} exec ruby ${CMAKE_SOURCE_DIR}/exe/plod build
            ${CMAKE_SOURCE_DIR}/lib/Devices/${dev_src}.rb
            -d ${dev}
            -o ${CMAKE_CURRENT_BINARY_DIR}/${dev}.hh
    COMMENT "Generating device header ${dev}.hh (${PROJECT_NAME})"
  )
  add_custom_target(protea_devgen_${dev} DEPENDS ${dev}.hh)
  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/${dev}.hh DESTINATION share/)
endforeach()

add_custom_target(${PROJECT_NAME} ALL
  DEPENDS protea_devgen_Clint protea_devgen_ns16550 protea_devgen_Uart8250)
