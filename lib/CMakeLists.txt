project(protea_irgen)

set(NATIVE_IR_FILE ${CMAKE_CURRENT_BINARY_DIR}/IR.yaml)

if(PROTEA_USE_BUNDLER)
  set(PROTEA_RUBY_COMMAND ${BUNDLE_PATH} exec ruby)
else()
  set(PROTEA_RUBY_COMMAND
      ${CMAKE_COMMAND} -E env "RUBYLIB=${CMAKE_CURRENT_SOURCE_DIR}"
      ${Ruby_EXECUTABLE})
endif()

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
  COMMAND ${PROTEA_RUBY_COMMAND} ${CMAKE_CURRENT_SOURCE_DIR}/ir_gen.rb
          --target ${CMAKE_CURRENT_SOURCE_DIR}/Target/RISC-V
          --output ${NATIVE_IR_FILE}
  COMMENT "Generating native IR (IR.yaml)"
)

add_custom_target(native_gen DEPENDS ${NATIVE_IR_FILE})

add_custom_target(protea_irgen DEPENDS native_gen)

if(PROTEA_USE_BUNDLER)
  add_dependencies(native_gen bundle-install)
endif()

set(NATIVE_IR_FILE ${NATIVE_IR_FILE} PARENT_SCOPE)

install(FILES ${NATIVE_IR_FILE} DESTINATION share/)
