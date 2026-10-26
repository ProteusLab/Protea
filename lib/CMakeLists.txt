project(protea_irgen)

set(NATIVE_IR_FILE ${CMAKE_CURRENT_BINARY_DIR}/IR.yaml)

add_custom_command(
  OUTPUT ${NATIVE_IR_FILE}
  DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/ir_gen.rb
          ${CMAKE_CURRENT_SOURCE_DIR}/ADL/base.rb
          ${CMAKE_CURRENT_SOURCE_DIR}/ADL/builder.rb
          ${CMAKE_CURRENT_SOURCE_DIR}/ADL/scope.rb
          ${CMAKE_CURRENT_SOURCE_DIR}/ADL/var.rb
          ${CMAKE_CURRENT_SOURCE_DIR}/ADL/value.rb
          ${CMAKE_CURRENT_SOURCE_DIR}/Utility/type.rb
          ${CMAKE_CURRENT_SOURCE_DIR}/Target/RISC-V/encoding.rb
          ${CMAKE_CURRENT_SOURCE_DIR}/Target/RISC-V/32I.rb
          ${CMAKE_CURRENT_SOURCE_DIR}/Target/RISC-V/32M.rb
  COMMAND ${BUNDLE_PATH} exec ruby ${CMAKE_CURRENT_SOURCE_DIR}/ir_gen.rb
          --target ${CMAKE_CURRENT_SOURCE_DIR}/Target/RISC-V
          --output ${NATIVE_IR_FILE}
  COMMENT "Generating native IR (IR.yaml)"
)

add_custom_target(native_gen DEPENDS ${NATIVE_IR_FILE})

add_custom_target(protea_irgen DEPENDS native_gen)

set(NATIVE_IR_FILE ${NATIVE_IR_FILE} PARENT_SCOPE)

install(FILES ${NATIVE_IR_FILE} DESTINATION share/)
