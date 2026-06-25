# sim_gen/CMakeLists.txt

project(protea_native_sim_gen)

if(NOT NATIVE_IR_FILE)
  set(NATIVE_IR_FILE ${protea_irgen_BINARY_DIR}/IR.yaml)
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
  DEPENDS ${NATIVE_IR_FILE} ${CMAKE_CURRENT_SOURCE_DIR}/sim_gen.rb
  COMMAND ${CMAKE_COMMAND} -E make_directory ${OUTPUT_DIR}
  COMMAND cd ${OUTPUT_DIR} && ${BUNDLE_PATH} exec ruby ${CMAKE_CURRENT_SOURCE_DIR}/sim_gen.rb ${NATIVE_IR_FILE}
  COMMENT "Generating native simulator sources from ${NATIVE_IR_FILE}"
)

add_custom_target(native_sim_gen DEPENDS ${PROTEA_SIMGEN_OUTPUT_FILES})
add_dependencies(native_sim_gen native_gen)

add_executable(sim_native ${PROTEA_SIMGEN_OUTPUT_SOURCES}
  ${protea_simlib_SOURCE_DIR}/elf_loader.cc
  ${protea_simlib_SOURCE_DIR}/base_jit.cc
  ${protea_simlib_SOURCE_DIR}/sim.cc
  ${protea_simlib_SOURCE_DIR}/jit_factory.cc
  ${protea_simlib_SOURCE_DIR}/memory.cc
  ${protea_simlib_SOURCE_DIR}/Target/${TARGET_NAME}/cpu_state_ext.cc)

target_include_directories(sim_native PRIVATE
  ${OUTPUT_DIR}
  ${protea_simlib_SOURCE_DIR}
)

target_link_libraries(sim_native PRIVATE elfio CLI11 fmt)
target_compile_features(sim_native PRIVATE cxx_std_23)
add_dependencies(sim_native native_sim_gen)
add_dependencies(sim_native native_gen)

install(TARGETS sim_native)
