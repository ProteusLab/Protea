project(protea_devgen)

file(GLOB_RECURSE PROTEA_PLOD_SOURCES CONFIGURE_DEPENDS
  "${CMAKE_SOURCE_DIR}/lib/Plod/*.rb")

set(PROTEA_DEVGEN_DEVICES Clint ns16550 Uart8250 Plic MmioVirtIO
    I8042 I82094AA I8237 I8254 I8259)

foreach(dev ${PROTEA_DEVGEN_DEVICES})
  if(dev STREQUAL "MmioVirtIO")
    set(dev_src vio_mmio)
  else()
    string(TOLOWER "${dev}" dev_src)
  endif()
  add_custom_command(
    OUTPUT ${dev}.hh
    COMMAND ${BUNDLE_PATH} exec ruby ${CMAKE_SOURCE_DIR}/exe/plod build
            ${CMAKE_SOURCE_DIR}/lib/Devices/${dev_src}.rb
            -d ${dev}
            -o ${CMAKE_CURRENT_BINARY_DIR}/${dev}.hh
    DEPENDS ${CMAKE_SOURCE_DIR}/lib/Devices/${dev_src}.rb
            ${CMAKE_SOURCE_DIR}/targets/gem5_clint.yaml
            ${CMAKE_SOURCE_DIR}/targets/gem5_uart.yaml
            ${CMAKE_SOURCE_DIR}/targets/gem5_plic.yaml
            ${CMAKE_SOURCE_DIR}/targets/gem5_vio_mmio.yaml
            ${CMAKE_SOURCE_DIR}/targets/gem5_i8042.yaml
            ${CMAKE_SOURCE_DIR}/targets/gem5_i82094aa.yaml
            ${CMAKE_SOURCE_DIR}/targets/gem5_i8237.yaml
            ${CMAKE_SOURCE_DIR}/targets/gem5_i8254.yaml
            ${CMAKE_SOURCE_DIR}/targets/gem5_i8259.yaml
            ${CMAKE_SOURCE_DIR}/lib/Plod.rb
            ${PROTEA_PLOD_SOURCES}
    COMMENT "Generating device header ${dev}.hh (${PROJECT_NAME})"
  )
  add_custom_target(protea_devgen_${dev} DEPENDS ${dev}.hh)
  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/${dev}.hh DESTINATION share/)
endforeach()

add_custom_target(${PROJECT_NAME} ALL
  DEPENDS protea_devgen_Clint protea_devgen_ns16550 protea_devgen_Uart8250
          protea_devgen_Plic protea_devgen_MmioVirtIO
          protea_devgen_I8042 protea_devgen_I82094AA protea_devgen_I8237
          protea_devgen_I8254 protea_devgen_I8259)
