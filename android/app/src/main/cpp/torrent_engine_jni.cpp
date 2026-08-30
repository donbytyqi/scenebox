#include <jni.h>
#include <android/log.h>
#include <mutex>
#include <string>

namespace {
std::mutex mutex;
std::string activeMagnet;
bool active = false;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_scenebox_NativeTorrentBridge_nativeStart(JNIEnv* env, jobject, jstring magnet) {
    if (!magnet) return JNI_FALSE;
    const char* value = env->GetStringUTFChars(magnet, nullptr);
    if (!value) return JNI_FALSE;
    {
        std::lock_guard<std::mutex> lock(mutex);
        activeMagnet = value;
        active = true;
    }
    env->ReleaseStringUTFChars(magnet, value);
    __android_log_print(ANDROID_LOG_INFO, "SceneBoxTorrent", "Torrent session started");
    return JNI_TRUE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_scenebox_NativeTorrentBridge_nativeStop(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(mutex);
    activeMagnet.clear();
    active = false;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_scenebox_NativeTorrentBridge_nativeIsActive(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(mutex);
    return active ? JNI_TRUE : JNI_FALSE;
}
