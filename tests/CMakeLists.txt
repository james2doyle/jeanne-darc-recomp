# Tests of the game's own formats (the test runner comes from the core).
add_executable(jdarc_game_tests
    ${PSPRECORE_DIR}/tests/test_main.cpp
    spf_tests.cpp
)
target_link_libraries(jdarc_game_tests PRIVATE jdarc::game_formats nx::foundation)
target_include_directories(jdarc_game_tests PRIVATE ${PSPRECORE_DIR}/tests)
psprecore_target_defaults(jdarc_game_tests)

add_test(NAME jdarc_game_tests COMMAND jdarc_game_tests)
