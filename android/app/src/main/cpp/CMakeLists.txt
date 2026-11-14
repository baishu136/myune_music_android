cmake_minimum_required(VERSION 3.22.1)
project(myune_plugin_js C)
set(QJS ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/quickjs)
add_library(myune_plugin_js SHARED plugin_js.c
    ${QJS}/quickjs.c ${QJS}/dtoa.c ${QJS}/libregexp.c
    ${QJS}/libunicode.c ${QJS}/cutils.c)
target_include_directories(myune_plugin_js PRIVATE ${QJS})
target_compile_definitions(myune_plugin_js PRIVATE _GNU_SOURCE CONFIG_VERSION="2026-06-04")
target_compile_options(myune_plugin_js PRIVATE -O2 -fvisibility=hidden)
target_link_options(myune_plugin_js PRIVATE "-Wl,-z,max-page-size=16384")
target_link_libraries(myune_plugin_js m)
