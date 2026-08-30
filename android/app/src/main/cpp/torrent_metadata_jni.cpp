#include <jni.h>
#include <mutex>
#include <string>

#if __has_include(<libtorrent/session.hpp>) && __has_include(<libtorrent/torrent_info.hpp>)
#define SCENEBOX_HAS_LIBTORRENT 1
#include <libtorrent/session.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#else
#define SCENEBOX_HAS_LIBTORRENT 0
#endif

namespace {
std::mutex g_mutex;
#if SCENEBOX_HAS_LIBTORRENT
extern std::unique_ptr<lt::session> g_session;
extern lt::torrent_handle g_handle;
#endif
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_scenebox_NativeTorrentBridge_nativeMetadata(JNIEnv* env, jobject) {
#if SCENEBOX_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_handle.is_valid()) return env->NewStringUTF("{\"ready\":false}");

    auto st = g_handle.status(lt::torrent_handle::query_name | lt::torrent_handle::query_torrent_file);
    if (st.torrent_file.expired()) return env->NewStringUTF("{\"ready\":false}");

    auto ti = st.torrent_file.lock();
    if (!ti) return env->NewStringUTF("{\"ready\":false}");

    std::string json = "{\"ready\":true,\"name\":\"";
    for (char c : ti->name()) {
        if (c == '\\' || c == '"') json += '\\';
        json += c;
    }
    json += "\",\"pieceLength\":" + std::to_string(ti->piece_length());
    json += ",\"pieceCount\":" + std::to_string(ti->num_pieces());
    json += ",\"files\":[";
    auto const& fs = ti->files();
    for (lt::file_index_t i{0}; i < fs.num_files(); ++i) {
        if (i.value() != 0) json += ',';
        json += "{\"index\":" + std::to_string(i.value());
        json += ",\"path\":\"";
        for (char c : fs.file_path(i)) {
            if (c == '\\' || c == '"') json += '\\';
            json += c;
        }
        json += "\",\"offset\":" + std::to_string(fs.file_offset(i));
        json += ",\"length\":" + std::to_string(fs.file_size(i)) + "}";
    }
    json += "]}";
    return env->NewStringUTF(json.c_str());
#else
    return env->NewStringUTF("{\"ready\":false,\"reason\":\"libtorrent-not-linked\"}");
#endif
}
