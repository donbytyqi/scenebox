#include <jni.h>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#if __has_include(<libtorrent/session.hpp>) && __has_include(<libtorrent/magnet_uri.hpp>)
#define SCENEBOX_HAS_LIBTORRENT 1
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/torrent_handle.hpp>
#else
#define SCENEBOX_HAS_LIBTORRENT 0
#endif

namespace {
std::mutex g_mutex;
#if SCENEBOX_HAS_LIBTORRENT
std::unique_ptr<lt::session> g_session;
lt::torrent_handle g_handle;
#endif
bool g_active = false;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_scenebox_NativeTorrentBridge_nativeStart(JNIEnv* env, jobject, jstring magnet) {
    if (!magnet) return JNI_FALSE;
    const char* raw = env->GetStringUTFChars(magnet, nullptr);
    if (!raw) return JNI_FALSE;

    std::lock_guard<std::mutex> lock(g_mutex);
#if SCENEBOX_HAS_LIBTORRENT
    try {
        lt::add_torrent_params params = lt::parse_magnet_uri(raw);
        params.save_path = "/data/data/com.scenebox/files/torrents";
        g_session = std::make_unique<lt::session>();
        g_handle = g_session->add_torrent(params);
        g_active = g_handle.is_valid();
    } catch (...) {
        g_active = false;
    }
#else
    g_active = false;
#endif

    env->ReleaseStringUTFChars(magnet, raw);
    return g_active ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_scenebox_NativeTorrentBridge_nativeStop(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(g_mutex);
#if SCENEBOX_HAS_LIBTORRENT
    if (g_handle.is_valid()) g_handle.pause();
    g_handle = {};
    g_session.reset();
#endif
    g_active = false;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_scenebox_NativeTorrentBridge_nativeIsActive(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_active ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_scenebox_TorrentPieceBridge_nativeHasPiece(JNIEnv*, jobject, jint piece) {
#if SCENEBOX_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_handle.is_valid() && piece >= 0 && g_handle.have_piece(piece) ? JNI_TRUE : JNI_FALSE;
#else
    return JNI_FALSE;
#endif
}

extern "C" JNIEXPORT void JNICALL
Java_com_scenebox_TorrentPieceBridge_nativeSetPriority(JNIEnv*, jobject, jint piece, jint priority) {
#if SCENEBOX_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_handle.is_valid() && piece >= 0) {
        g_handle.piece_priority(piece, static_cast<int>(priority));
    }
#endif
}

extern "C" JNIEXPORT void JNICALL
Java_com_scenebox_TorrentPieceBridge_nativeSetDeadline(JNIEnv*, jobject, jint piece, jint deadlineMs) {
#if SCENEBOX_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_handle.is_valid() && piece >= 0) {
        g_handle.set_piece_deadline(piece, deadlineMs, lt::torrent_handle::alert_when_available);
    }
#endif
}

extern "C" JNIEXPORT void JNICALL
Java_com_scenebox_TorrentPieceBridge_nativeClearDeadline(JNIEnv*, jobject, jint piece) {
#if SCENEBOX_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_handle.is_valid() && piece >= 0) {
        g_handle.reset_piece_deadline(piece);
    }
#endif
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_scenebox_TorrentPieceBridge_nativeReadPiece(JNIEnv* env, jobject, jint piece) {
#if SCENEBOX_HAS_LIBTORRENT
    if (piece < 0) return nullptr;

    std::unique_lock<std::mutex> lock(g_mutex);
    if (!g_handle.is_valid() || !g_session) return nullptr;

    g_handle.set_piece_deadline(piece, 0, lt::torrent_handle::alert_when_available);
    g_handle.read_piece(piece);

    for (;;) {
        auto* session = g_session.get();
        lock.unlock();
        session->wait_for_alert(5000);
        lock.lock();

        if (!g_session || !g_handle.is_valid()) return nullptr;

        std::vector<lt::alert*> alerts;
        g_session->pop_alerts(&alerts);
        for (lt::alert* alert : alerts) {
            if (auto* ready = lt::alert_cast<lt::read_piece_alert>(alert)) {
                if (ready->piece != piece || !ready->buffer || ready->size <= 0) continue;

                jbyteArray output = env->NewByteArray(ready->size);
                if (!output) return nullptr;
                env->SetByteArrayRegion(
                    output, 0, ready->size,
                    reinterpret_cast<const jbyte*>(ready->buffer.get()));
                return output;
            }
        }
    }
#else
    return nullptr;
#endif
}
