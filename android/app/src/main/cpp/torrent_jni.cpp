#include <jni.h>
#include <android/log.h>

#define LOG_TAG "SceneBoxTorrent"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

// JNI entry points are implemented in torrent_libtorrent.cpp. This file is
// retained only for the Android native target's logging/translation unit.
extern "C" JNIEXPORT jint JNICALL
JNI_OnLoad(JavaVM* vm, void*) {
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }
    LOGI("SceneBox torrent native library loaded");
    return JNI_VERSION_1_6;
}
