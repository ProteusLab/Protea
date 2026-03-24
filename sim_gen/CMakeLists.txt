project(protea_simgen)

set(PROTEA_SIMGEN_OUTPUT_HEADERS
  cpu_state.hh
  base_exec_engine.hh
  naive_interpreter.hh
  decoder.hh
  isa.hh
  hart.hh
)

set(PROTEA_SIMGEN_OUTPUT_SOURCES
  base_exec_engine.cc
  naive_interpreter.cc
  decoder.cc
  hart.cc
)

set(PROTEA_SIMGEN_OUTPUT_FILES
  ${PROTEA_SIMGEN_OUTPUT_HEADERS}
  ${PROTEA_SIMGEN_OUTPUT_SOURCES}
)

set(IR_YAML_FILE ${protea_irgen_BINARY_DIR}/IR.yaml)


add_custom_command(DEPENDS
  OUTPUT ${PROTEA_SIMGEN_OUTPUT_FILES}
  COMMAND ${BUNDLE_PATH} exec ruby ${CMAKE_CURRENT_SOURCE_DIR}/sim_gen.rb ${IR_YAML_FILE}
  DEPENDS ${IR_YAML_FILE}
  COMMENT "Running ${PROJECT_NAME}"
)
add_custom_target(${PROJECT_NAME} ALL DEPENDS ${PROTEA_SIMGEN_OUTPUT_FILES})
add_dependencies(${PROJECT_NAME} protea_irgen)

add_executable(sim ${PROTEA_SIMGEN_OUTPUT_SOURCES} 
  ${protea_simlib_SOURCE_DIR}/elf_loader.cc 
  ${protea_simlib_SOURCE_DIR}/base_jit.cc 
  ${protea_simlib_SOURCE_DIR}/sim.cc 
  ${protea_simlib_SOURCE_DIR}/jit_factory.cc
  ${protea_simlib_SOURCE_DIR}/memory.cc
  ${protea_simlib_SOURCE_DIR}/Target/${TARGET_NAME}/cpu_state_ext.cc)
  
target_include_directories(sim PRIVATE ${CMAKE_CURRENT_BINARY_DIR} ${protea_simlib_SOURCE_DIR})
target_link_libraries(sim elfio CLI11 fmt)
target_compile_features(sim PRIVATE cxx_std_23)
install(TARGETS sim)
