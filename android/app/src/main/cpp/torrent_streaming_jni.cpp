#include <jni.h>
#include <mutex>

#if __has_include(<libtorrent/torrent_handle.hpp>) && __has_include(<libtorrent/torrent_status.hpp>)
#define SCENEBOX_HAS_LIBTORRENT 1
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#else
#define SCENEBOX_HAS_LIBTORRENT 0
#endif

namespace {
std::mutex g_mutex;
#if SCENEBOX_HAS_LIBTORRENT
extern lt::torrent_handle g_handle;
#endif
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_scenebox_NativeTorrentBridge_nativeStats(JNIEnv* env, jobject) {
#if SCENEBOX_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_handle.is_valid()) return env->NewStringUTF("{\"active\":false}");
    const auto status = g_handle.status();
    const auto progress = status.progress;
    const auto rate = status.download_rate;
    const auto peers = status.num_peers;
    const auto seeds = status.num_seeds;
    char json[256];
    snprintf(json, sizeof(json),
        "{\"active\":true,\"progress\":%.6f,\"downloadRate\":%d,\"peers\":%d,\"seeds\":%d}",
        progress, rate, peers, seeds);
    return env->NewStringUTF(json);
#else
    return env->NewStringUTF("{\"active\":false,\"reason\":\"libtorrent-not-linked\"}");
#endif
}
