cmake_minimum_required(VERSION 3.25)

# ccache when installed: same commands, warm rebuilds (reconfigure once to take effect).
find_program(JDARC_CCACHE ccache)
if(JDARC_CCACHE)
  set(CMAKE_C_COMPILER_LAUNCHER ${JDARC_CCACHE})
  set(CMAKE_CXX_COMPILER_LAUNCHER ${JDARC_CCACHE})
endif()

project(JDARCRECOMP
    VERSION 0.1.0
    DESCRIPTION "Native port of Jeanne d'Arc (PSP) via static recompilation"
    LANGUAGES C CXX)

# The recompiler and runtime (psprecore): libraries, front end, tools and their tests.
add_subdirectory(psprecore)

add_subdirectory(libs/formats)

if(PSPRECORE_BUILD_TESTS)
    enable_testing()  # here too, so ctest from the build root runs psprecore's tests and the game's
    add_subdirectory(tests)
endif()

if(PSPRECORE_BUILD_TOOLS)
    add_subdirectory(tools/jdcook)

    # Edited textures (assets/textures, laid out by a future unpack tool) are packed into the cooked media by every
    # build (psptex pack compares the pictures' pixels with the originals, so it is quick). assets/textures-hd
    # (psptex match, e.g. from another project's texture pack) fills in where a picture in assets/textures is
    # unedited, then assets/textures-ai (AI-enhanced, for everything without a hand-made version).
    set(JDARC_COOKED_DIR "${PROJECT_SOURCE_DIR}/data/cooked" CACHE PATH "cooked media the game loads")
    set(_jdarc_textures "${PROJECT_SOURCE_DIR}/assets/textures")
    if(EXISTS "${_jdarc_textures}/index.tsv")
        add_custom_target(jdarc_textures ALL
            COMMAND psptex pack "${_jdarc_textures}" "${JDARC_COOKED_DIR}"
                    --layer "${PROJECT_SOURCE_DIR}/assets/textures-hd"
                    --layer "${PROJECT_SOURCE_DIR}/assets/textures-ai"
                    --originals "${PROJECT_SOURCE_DIR}/data/collected-textures"
            DEPENDS psptex
            COMMENT "Packing edited textures (assets/textures, textures-hd, textures-ai -> cooked/textures)"
            VERBATIM)
    endif()
endif()

# The game needs code generated from the user's own BOOT.BIN (psprecomp -> data/generated); src/decomp holds
# hand-written replacements for recompiled functions (GAME_FUNC, run psprecomp with --overrides src/decomp).
# The jdarc target needs the full frontend (Vulkan SDK with slangc); machines without it configure with
# -DPSPRECORE_BUILD_GAME=OFF to still build the formats, tools and tests.
set(JDARC_GENERATED_DIR "${PROJECT_SOURCE_DIR}/data/generated" CACHE PATH "psprecomp output directory")
if(PSPRECORE_BUILD_GAME)
    file(GLOB _jdarc_game_sources CONFIGURE_DEPENDS "${PROJECT_SOURCE_DIR}/src/*.cpp")
    psprecore_add_game(jdarc
        GENERATED_DIR "${JDARC_GENERATED_DIR}"
        OVERRIDES_DIR "${PROJECT_SOURCE_DIR}/src/decomp"
        SOURCES ${_jdarc_game_sources})
    if(TARGET jdarc)
        target_link_libraries(jdarc PRIVATE jdarc::game_formats)
        if(ANDROID)
            # Custom GPU drivers (Turnip) via libadrenotools (BSD-2-Clause, vendored in third_party/):
            # the loader links into the frontend, the hook .so files ship beside libmain.so (jniLibs ->
            # nativeLibraryDir, where adrenotools expects them).
            set(BUILD_SHARED_LIBS OFF)
            add_subdirectory(third_party/adrenotools)
            target_link_libraries(psprecore_frontend PUBLIC adrenotools)
            target_compile_definitions(psprecore_frontend PUBLIC JDARC_HAVE_ADRENOTOOLS=1)
            add_custom_command(TARGET jdarc POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}/jniLibs/arm64-v8a"
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    $<TARGET_FILE:jdarc>
                    $<TARGET_FILE:main_hook> $<TARGET_FILE:file_redirect_hook>
                    $<TARGET_FILE:gsl_alloc_hook> $<TARGET_FILE:hook_impl>
                    "${CMAKE_BINARY_DIR}/jniLibs/arm64-v8a"
                COMMENT "Staging libmain and adrenotools hook libraries for the APK")
        endif()
    endif()
endif()
