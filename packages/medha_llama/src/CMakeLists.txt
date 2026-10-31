# Builds libmedha_llama: Medha's C shim statically linked with llama.cpp.
# Used by the Android build (externalNativeBuild) and for desktop compile
# checks. iOS links a prebuilt llama.xcframework instead (see ios/).

cmake_minimum_required(VERSION 3.14)
project(medha_llama_library VERSION 0.1.0 LANGUAGES C CXX)

set(MEDHA_LLAMA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../native/llama.cpp"
    CACHE PATH "Path to the pinned llama.cpp checkout")

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)

add_subdirectory("${MEDHA_LLAMA_DIR}" llama_build EXCLUDE_FROM_ALL)

add_library(medha_llama SHARED medha_llama.c)
set_target_properties(medha_llama PROPERTIES
    C_STANDARD 11
    C_VISIBILITY_PRESET hidden
    OUTPUT_NAME "medha_llama")
target_link_libraries(medha_llama PRIVATE llama)

if (ANDROID)
    # Support 16 KB page sizes (required for new Play Store uploads).
    target_link_options(medha_llama PRIVATE "-Wl,-z,max-page-size=16384")
endif()
