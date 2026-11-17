cmake_minimum_required(VERSION 3.14)
project(CompilerWorkspace C)

set(CMAKE_C_STANDARD 11)

include(FetchContent)
include(ExternalProject)

find_program(MAKE_COMMAND NAMES make gmake)

# Helper macro for building local static libraries via Makefiles.
macro(add_static_makefile_lib LIB_NAME REPO_URL GIT_TAG BUILD_TARGET LIB_PATH INCLUDE_DIRS)
    FetchContent_Declare(
        ${LIB_NAME}
        GIT_REPOSITORY ${REPO_URL}
        GIT_TAG        ${GIT_TAG}
    )

    FetchContent_GetProperties(${LIB_NAME})
    if(NOT ${LIB_NAME}_POPULATED)
        FetchContent_Populate(${LIB_NAME})

        ExternalProject_Add(
            ${LIB_NAME}_build
            SOURCE_DIR ${${LIB_NAME}_SOURCE_DIR}
            CONFIGURE_COMMAND ""
            BUILD_COMMAND ${MAKE_COMMAND} ${BUILD_TARGET} "CFLAGS=-g -O0 -fPIC"
            INSTALL_COMMAND ""
            BUILD_IN_SOURCE TRUE
        )
    endif()

    add_library(${LIB_NAME} STATIC IMPORTED)
    set_target_properties(${LIB_NAME} PROPERTIES
        IMPORTED_LOCATION "${${LIB_NAME}_SOURCE_DIR}/${LIB_PATH}"
        INTERFACE_INCLUDE_DIRECTORIES "${INCLUDE_DIRS}"
    )
    add_dependencies(${LIB_NAME} ${LIB_NAME}_build)
endmacro()

# 1. Fetch Janet source repository
FetchContent_Declare(
    janet
    GIT_REPOSITORY https://github.com/janet-lang/janet.git
    GIT_TAG        v1.36.0
)
FetchContent_MakeAvailable(janet)

# Create amalgamated janet.c
execute_process(
    COMMAND ${MAKE_COMMAND} build/c/janet.c
    WORKING_DIRECTORY ${janet_SOURCE_DIR}
)

add_library(janet STATIC
    ${janet_SOURCE_DIR}/build/c/janet.c
)

target_include_directories(janet PUBLIC
    ${janet_SOURCE_DIR}/src/include
    ${janet_SOURCE_DIR}/src/conf
)

set_property(TARGET janet PROPERTY POSITION_INDEPENDENT_CODE ON)

# Janet LISP
#add_static_makefile_lib(
#    janet
#    "https://github.com/janet-lang/janet.git"
#    "v1.36.0"
#    "build/c/janet.c"
#    "build/c/janet.a"
#    "${janet_SOURCE_DIR}/src/include;${janet_SOURCE_DIR}/src/conf"
#)

# Libvterm
# Note requires libtool to be installed to build.
# sudo apt install libtool libtool-bin.
add_static_makefile_lib(
    vterm
    "https://github.com/neovim/libvterm.git"
    "v0.3.3"
    ""
    ".libs/libvterm.a"
    "${vterm_SOURCE_DIR}/include"
)
