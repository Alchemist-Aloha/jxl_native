cmake_minimum_required(VERSION 3.21)
project(jxl_native C CXX)

set(LIBJXL_SOURCE_DIR "" CACHE PATH "Path to a libjxl checkout with submodules")
if(NOT EXISTS "${LIBJXL_SOURCE_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "Set LIBJXL_SOURCE_DIR to a libjxl checkout")
endif()

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# Decoder-only static libjxl; everything else is off.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
foreach(feature TOOLS DEVTOOLS DOXYGEN MANPAGES BENCHMARK EXAMPLES JNI SJPEG
        OPENEXR TCMALLOC FUZZERS VIEWERS PLUGINS COVERAGE)
  set(JPEGXL_ENABLE_${feature} OFF CACHE BOOL "" FORCE)
endforeach()
set(JPEGXL_BUNDLE_LIBPNG OFF CACHE BOOL "" FORCE)
set(JPEGXL_ENABLE_SKCMS ON CACHE BOOL "" FORCE)

add_subdirectory("${LIBJXL_SOURCE_DIR}" libjxl-build EXCLUDE_FROM_ALL)

add_library(jxl_native SHARED ../src/jxl_shim.c)
target_link_libraries(jxl_native PRIVATE jxl_dec jxl_threads)
set_target_properties(jxl_native PROPERTIES
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
  LINKER_LANGUAGE CXX
  OUTPUT_NAME jxl_native
)

if(APPLE)
  set_target_properties(jxl_native PROPERTIES
    BUILD_WITH_INSTALL_RPATH YES
    INSTALL_NAME_DIR "@rpath"
  )
  target_link_options(jxl_native PRIVATE
    "LINKER:-dead_strip"
    "LINKER:-headerpad_max_install_names"
  )
elseif(ANDROID)
  target_link_options(jxl_native PRIVATE
    "LINKER:--gc-sections" "LINKER:--exclude-libs,ALL")
elseif(UNIX)
  # Self-contained: no libstdc++/libgcc_s requirement on the host.
  target_link_options(jxl_native PRIVATE
    "LINKER:--gc-sections" "LINKER:--exclude-libs,ALL"
    -static-libstdc++ -static-libgcc)
endif()

if(CMAKE_C_COMPILER_ID MATCHES "AppleClang|Clang|GNU")
  target_compile_options(jxl_native PRIVATE -ffunction-sections -fdata-sections)
endif()
