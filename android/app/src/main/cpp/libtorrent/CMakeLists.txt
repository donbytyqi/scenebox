# Libtorrent dependency boundary for SceneBox Android.
#
# This file intentionally does not download or vendor a third-party library.
# Provide a prebuilt Android libtorrent target through the parent build, or
# replace this file with an ExternalProject/fetch-content setup after pinning
# and auditing the exact upstream version used by the application.

if (NOT TARGET libtorrent)
    message(STATUS "SceneBox: libtorrent target not supplied; JNI torrent engine will build in stub mode")
endif()
