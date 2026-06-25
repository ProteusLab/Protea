# sim_gen_lira/CMakeLists.txt

project(protea_lira_sim_gen)

if(NOT LIRA_IR_FILE)
  set(LIRA_IR_FILE ${protea_irgen_BINARY_DIR}/lira.yaml)
endif()

set(OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR})

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


add_custom_command(
  OUTPUT ${PROTEA_SIMGEN_OUTPUT_FILES}
  DEPENDS ${LIRA_IR_FILE} ${CMAKE_CURRENT_SOURCE_DIR}/sim_gen.rb
  COMMAND ${CMAKE_COMMAND} -E make_directory ${OUTPUT_DIR}
  COMMAND cd ${OUTPUT_DIR} && ${BUNDLE_PATH} exec ruby ${CMAKE_CURRENT_SOURCE_DIR}/sim_gen.rb ${LIRA_IR_FILE}
  COMMENT "Generating LIRA simulator sources from ${LIRA_IR_FILE}"
)

add_custom_target(lira_sim_gen DEPENDS ${PROTEA_SIMGEN_OUTPUT_FILES})
add_dependencies(lira_sim_gen lira_gen)

add_executable(sim_lira ${PROTEA_SIMGEN_OUTPUT_SOURCES}
  ${protea_simlib_SOURCE_DIR}/elf_loader.cc
  ${protea_simlib_SOURCE_DIR}/base_jit.cc
  ${protea_simlib_SOURCE_DIR}/sim.cc
  ${protea_simlib_SOURCE_DIR}/jit_factory.cc
  ${protea_simlib_SOURCE_DIR}/memory.cc
  ${protea_simlib_SOURCE_DIR}/Target/${TARGET_NAME}/cpu_state_ext.cc
)

target_include_directories(sim_lira PRIVATE
  ${OUTPUT_DIR}
  ${protea_simlib_SOURCE_DIR}
)

target_link_libraries(sim_lira PRIVATE elfio CLI11 fmt)
target_compile_features(sim_lira PRIVATE cxx_std_23)
add_dependencies(sim_lira lira_sim_gen lira_gen)

install(TARGETS sim_lira)
