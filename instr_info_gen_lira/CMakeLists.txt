# instr_info_gen_lira/CMakeLists.txt

project(protea_lira_instr_info_gen)

if(NOT LIRA_IR_FILE)
  set(LIRA_IR_FILE ${protea_irgen_BINARY_DIR}/lira.yaml)
endif()

set(OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR})

set(PROTEA_INSTRINFO_OUTPUT_HEADER ${OUTPUT_DIR}/instr_info.hh)

set(PROTEA_INSTRINFO_GENERATOR_SOURCES
  ${CMAKE_CURRENT_SOURCE_DIR}/instr_info_gen.rb
  ${CMAKE_CURRENT_SOURCE_DIR}/header_gen.rb
  ${CMAKE_SOURCE_DIR}/lib/lira/classify.rb
)

add_custom_command(
  OUTPUT ${PROTEA_INSTRINFO_OUTPUT_HEADER}
  DEPENDS ${LIRA_IR_FILE} ${PROTEA_INSTRINFO_GENERATOR_SOURCES}
  COMMAND ${CMAKE_COMMAND} -E make_directory ${OUTPUT_DIR}
  COMMAND cd ${OUTPUT_DIR} && ${BUNDLE_PATH} exec ruby ${CMAKE_CURRENT_SOURCE_DIR}/instr_info_gen.rb ${LIRA_IR_FILE}
  COMMENT "Generating LIRA instruction info header from ${LIRA_IR_FILE}"
)

add_custom_target(lira_instr_info_gen DEPENDS ${PROTEA_INSTRINFO_OUTPUT_HEADER})
add_dependencies(lira_instr_info_gen lira_gen)

# --- Generated instruction info library ---------------------------------------
# Header-only: a single constexpr table, so an INTERFACE target suffices.
add_library(lira_instr_info INTERFACE)
add_library(protea::instr_info ALIAS lira_instr_info)

target_include_directories(lira_instr_info INTERFACE ${OUTPUT_DIR})
target_compile_features(lira_instr_info INTERFACE cxx_std_23)
add_dependencies(lira_instr_info lira_instr_info_gen lira_gen)

# --- Compile-time smoke test ---------------------------------------------------
# Also the target that forces the generated header through a real compile.
add_executable(instr_info_smoke ${CMAKE_CURRENT_SOURCE_DIR}/smoke.cc)
target_link_libraries(instr_info_smoke PRIVATE lira_instr_info)
target_compile_features(instr_info_smoke PRIVATE cxx_std_23)

install(FILES ${PROTEA_INSTRINFO_OUTPUT_HEADER} DESTINATION include/lira_instr_info)
