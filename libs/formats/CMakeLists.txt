# Jeanne d'Arc's own file formats (documented as they are reverse-engineered).
add_library(jdarc_game_formats STATIC
    src/formats/spf.cpp
)
add_library(jdarc::game_formats ALIAS jdarc_game_formats)

target_include_directories(jdarc_game_formats PUBLIC include)
target_link_libraries(jdarc_game_formats PUBLIC psprecore::formats)
psprecore_target_defaults(jdarc_game_formats)
