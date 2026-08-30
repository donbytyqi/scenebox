cmake_minimum_required(VERSION 3.22.1)
project(scenebox_torrent)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(scenebox_torrent SHARED
    torrent_jni.cpp
    torrent_libtorrent.cpp
    torrent_stream_jni.cpp
)

find_library(log-lib log)

target_link_libraries(scenebox_torrent ${log-lib})

# Android libtorrent is supplied separately for each ABI. Set
# SCENEBOX_LIBTORRENT_ROOT to a directory containing include/ and lib/ and
# expose the library as libtorrent-rasterbar.
if(DEFINED SCENEBOX_LIBTORRENT_ROOT)
    target_include_directories(scenebox_torrent PRIVATE
        "${SCENEBOX_LIBTORRENT_ROOT}/include")
    add_library(libtorrent-rasterbar STATIC IMPORTED)
    set_target_properties(libtorrent-rasterbar PROPERTIES
        IMPORTED_LOCATION
        "${SCENEBOX_LIBTORRENT_ROOT}/lib/${ANDROID_ABI}/libtorrent-rasterbar.a"
        INTERFACE_INCLUDE_DIRECTORIES
        "${SCENEBOX_LIBTORRENT_ROOT}/include")
    target_link_libraries(scenebox_torrent libtorrent-rasterbar)
    target_compile_definitions(scenebox_torrent PRIVATE SCENEBOX_ANDROID_LIBTORRENT=1)
else()
    message(WARNING "SCENEBOX_LIBTORRENT_ROOT is not configured; native torrent support will not be linked.")
endif()
