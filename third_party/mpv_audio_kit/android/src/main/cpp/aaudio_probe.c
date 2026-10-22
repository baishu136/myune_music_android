// Myune-owned forwarding bridge for the pinned libmpv AAudio backend.
// Never touches PCM or wraps its data callback; callback lookups are warmed at load.
#include <aaudio/AAudio.h>
#include <jni.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <time.h>
#include <android/log.h>
#include "shared_audio_buffer.h"

static pthread_once_t once = PTHREAD_ONCE_INIT;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static void *system_library;
static int64_t (*frames_written)(AAudioStream*);
static aaudio_result_t (*stream_timestamp)(AAudioStream*,clockid_t,int64_t*,int64_t*);
static const char *(*result_text)(aaudio_result_t);
static AAudioStream *streams[16];
static int untracked_streams;
static int64_t revision;
static int32_t last_error;
static JavaVM *jvm;
static jclass callback_class;
static jmethodID callback_method;
struct builder_config {
    AAudioStreamBuilder *builder;
    int32_t rate, capacity, sharing, performance;
};
static struct builder_config builders[16];
static struct builder_config builder_info(AAudioStreamBuilder *b) {
    struct builder_config value = {0};
    pthread_mutex_lock(&lock);
    for (int i = 0; i < 16; i++) if (builders[i].builder == b) value = builders[i];
    pthread_mutex_unlock(&lock);
    return value;
}
static void load_system(void) {
    system_library = dlopen("libaaudio.so", RTLD_NOW | RTLD_LOCAL);
    if (!system_library) return;
    frames_written = dlsym(system_library,"AAudioStream_getFramesWritten");
    stream_timestamp = dlsym(system_library,"AAudioStream_getTimestamp");
    result_text = dlsym(system_library,"AAudio_convertResultToText");
}
static void *resolve(const char *name) { pthread_once(&once, load_system); return system_library ? dlsym(system_library, name) : 0; }
static void changed(void) {
    JNIEnv *env = 0;
    int attached = 0;
    pthread_mutex_lock(&lock);
    JavaVM *vm = jvm;
    pthread_mutex_unlock(&lock);
    if (!vm) return;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
        if ((*vm)->AttachCurrentThread(vm, &env, 0) != JNI_OK) return;
        attached = 1;
    }
    pthread_mutex_lock(&lock);
    jclass cls = callback_class ? (*env)->NewLocalRef(env, callback_class) : 0;
    jmethodID method = callback_method;
    pthread_mutex_unlock(&lock);
    if (cls && method) {
        (*env)->CallStaticVoidMethod(env, cls, method);
        if ((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env);
        (*env)->DeleteLocalRef(env, cls);
    }
    if (attached) (*vm)->DetachCurrentThread(vm);
}

#define RET(name, type, args, call, failure) \
 __attribute__((visibility("default"))) type name args { \
   type (*fn) args = (type (*) args)resolve(#name); return fn ? fn call : failure; }
#define VOID(name, args, call) \
 __attribute__((visibility("default"))) void name args { \
   void (*fn) args = (void (*) args)resolve(#name); if (fn) fn call; }

__attribute__((visibility("default"))) aaudio_result_t AAudio_createStreamBuilder(AAudioStreamBuilder **b) {
    aaudio_result_t (*fn)(AAudioStreamBuilder**) = resolve("AAudio_createStreamBuilder");
    aaudio_result_t result = fn ? fn(b) : AAUDIO_ERROR_UNAVAILABLE;
    if (result == AAUDIO_OK && b && *b) {
        pthread_mutex_lock(&lock);
        for (int i = 0; i < 16; i++) if (!builders[i].builder) {
            builders[i] = (struct builder_config){*b, 0, 0, AAUDIO_SHARING_MODE_SHARED, AAUDIO_PERFORMANCE_MODE_NONE};
            break;
        }
        pthread_mutex_unlock(&lock);
    }
    return result;
}
#define BUILDER_SET(name, type, field) \
 __attribute__((visibility("default"))) void name(AAudioStreamBuilder *b, type v) { \
    pthread_mutex_lock(&lock); \
    for (int i = 0; i < 16; i++) if (builders[i].builder == b) builders[i].field = v; \
    pthread_mutex_unlock(&lock); \
    void (*fn)(AAudioStreamBuilder*,type) = resolve(#name); if (fn) fn(b,v); }
VOID(AAudioStreamBuilder_setDeviceId, (AAudioStreamBuilder *b, int32_t v), (b,v))
BUILDER_SET(AAudioStreamBuilder_setSampleRate, int32_t, rate)
VOID(AAudioStreamBuilder_setChannelCount, (AAudioStreamBuilder *b, int32_t v), (b,v))
VOID(AAudioStreamBuilder_setSamplesPerFrame, (AAudioStreamBuilder *b, int32_t v), (b,v))
VOID(AAudioStreamBuilder_setFormat, (AAudioStreamBuilder *b, aaudio_format_t v), (b,v))
BUILDER_SET(AAudioStreamBuilder_setSharingMode, aaudio_sharing_mode_t, sharing)
VOID(AAudioStreamBuilder_setDirection, (AAudioStreamBuilder *b, aaudio_direction_t v), (b,v))
BUILDER_SET(AAudioStreamBuilder_setBufferCapacityInFrames, int32_t, capacity)
BUILDER_SET(AAudioStreamBuilder_setPerformanceMode, aaudio_performance_mode_t, performance)
VOID(AAudioStreamBuilder_setDataCallback, (AAudioStreamBuilder *b, AAudioStream_dataCallback cb, void *ctx), (b,cb,ctx))
VOID(AAudioStreamBuilder_setFramesPerDataCallback, (AAudioStreamBuilder *b, int32_t v), (b,v))
VOID(AAudioStreamBuilder_setErrorCallback, (AAudioStreamBuilder *b, AAudioStream_errorCallback cb, void *ctx), (b,cb,ctx))
VOID(AAudioStreamBuilder_setUsage, (AAudioStreamBuilder *b, aaudio_usage_t v), (b,v))
VOID(AAudioStreamBuilder_setContentType, (AAudioStreamBuilder *b, aaudio_content_type_t v), (b,v))
VOID(AAudioStreamBuilder_setSessionId, (AAudioStreamBuilder *b, aaudio_session_id_t v), (b,v))
VOID(AAudioStreamBuilder_setChannelMask, (AAudioStreamBuilder *b, aaudio_channel_mask_t v), (b,v))
__attribute__((visibility("default"))) aaudio_result_t AAudioStreamBuilder_delete(AAudioStreamBuilder *b) {
    pthread_mutex_lock(&lock);
    for (int i = 0; i < 16; i++) if (builders[i].builder == b) builders[i].builder = 0;
    pthread_mutex_unlock(&lock);
    aaudio_result_t (*fn)(AAudioStreamBuilder*) = resolve("AAudioStreamBuilder_delete");
    return fn ? fn(b) : AAUDIO_ERROR_UNAVAILABLE;
}

__attribute__((visibility("default"))) aaudio_result_t AAudioStreamBuilder_openStream(AAudioStreamBuilder *b, AAudioStream **out) {
    struct builder_config config = builder_info(b);
    int32_t floor = myune_buffer_floor(config.rate,
        config.sharing == AAUDIO_SHARING_MODE_SHARED,
        config.performance == AAUDIO_PERFORMANCE_MODE_NONE);
    if (config.builder && config.capacity == AAUDIO_UNSPECIFIED && floor > 0) {
        void (*capacity)(AAudioStreamBuilder*,int32_t) = resolve("AAudioStreamBuilder_setBufferCapacityInFrames");
        if (capacity) capacity(b, floor);
    }
    aaudio_result_t (*fn)(AAudioStreamBuilder*, AAudioStream**) = resolve("AAudioStreamBuilder_openStream");
    aaudio_result_t result = fn ? fn(b,out) : AAUDIO_ERROR_UNAVAILABLE;
    if (result == AAUDIO_OK && out && *out && config.builder && config.capacity == AAUDIO_UNSPECIFIED && floor > 0) {
        int32_t (*rate)(AAudioStream*) = resolve("AAudioStream_getSampleRate");
        int32_t (*capacity)(AAudioStream*) = resolve("AAudioStream_getBufferCapacityInFrames");
        int32_t (*size)(AAudioStream*) = resolve("AAudioStream_getBufferSizeInFrames");
        aaudio_result_t (*resize)(AAudioStream*,int32_t) = resolve("AAudioStream_setBufferSizeInFrames");
        if (rate && capacity && size && resize) {
            int32_t previous = size(*out);
            int32_t target = myune_buffer_size(myune_buffer_floor(rate(*out), 1, 1), capacity(*out), previous);
            if (target > previous) resize(*out, target);
            __android_log_print(ANDROID_LOG_INFO, "MyuneAudio", "shared buffer rate=%d capacity=%d size=%d previous=%d", rate(*out), capacity(*out), size(*out), previous);
        }
    }
    pthread_mutex_lock(&lock);
    last_error = result;
    if (result == AAUDIO_OK && out && *out) {
        int tracked = 0;
        for (int i = 0; i < 16; i++) if (!streams[i]) { streams[i] = *out; tracked = 1; break; }
        if (!tracked) untracked_streams++;
    }
    revision++;
    pthread_mutex_unlock(&lock);
    changed();
    return result;
}
__attribute__((visibility("default"))) aaudio_result_t AAudioStream_close(AAudioStream *s) {
    pthread_mutex_lock(&lock);
    int found = 0;
    for (int i = 0; i < 16; i++) if (streams[i] == s) { streams[i] = 0; found = 1; }
    if (!found && untracked_streams > 0) untracked_streams--;
    revision++;
    pthread_mutex_unlock(&lock);
    int32_t (*xruns)(AAudioStream*) = resolve("AAudioStream_getXRunCount");
    if (xruns) __android_log_print(ANDROID_LOG_INFO, "MyuneAudio", "closing stream xruns=%d", xruns(s));
    aaudio_result_t (*fn)(AAudioStream*) = resolve("AAudioStream_close");
    aaudio_result_t result = fn ? fn(s) : AAUDIO_ERROR_UNAVAILABLE;
    changed();
    return result;
}

#define CONTROL(name) RET(name, aaudio_result_t, (AAudioStream *s), (s), AAUDIO_ERROR_UNAVAILABLE)
CONTROL(AAudioStream_requestStart)
CONTROL(AAudioStream_requestPause)
CONTROL(AAudioStream_requestFlush)
CONTROL(AAudioStream_requestStop)
#define GET(name,type) RET(name,type,(AAudioStream *s),(s),0)
GET(AAudioStream_getState,aaudio_stream_state_t)
GET(AAudioStream_getBufferSizeInFrames,int32_t)
GET(AAudioStream_getFramesPerBurst,int32_t)
GET(AAudioStream_getBufferCapacityInFrames,int32_t)
GET(AAudioStream_getFramesPerDataCallback,int32_t)
GET(AAudioStream_getXRunCount,int32_t)
GET(AAudioStream_getSampleRate,int32_t)
GET(AAudioStream_getChannelCount,int32_t)
GET(AAudioStream_getSamplesPerFrame,int32_t)
GET(AAudioStream_getDeviceId,int32_t)
GET(AAudioStream_getFormat,aaudio_format_t)
GET(AAudioStream_getSharingMode,aaudio_sharing_mode_t)
GET(AAudioStream_getPerformanceMode,aaudio_performance_mode_t)
GET(AAudioStream_getDirection,aaudio_direction_t)
__attribute__((visibility("default"))) int64_t AAudioStream_getFramesWritten(AAudioStream *s) {
    return frames_written ? frames_written(s) : 0;
}
GET(AAudioStream_getFramesRead,int64_t)
RET(AAudioStream_waitForStateChange,aaudio_result_t,(AAudioStream *s,aaudio_stream_state_t state,aaudio_stream_state_t *next,int64_t timeout),(s,state,next,timeout),AAUDIO_ERROR_UNAVAILABLE)
RET(AAudioStream_read,aaudio_result_t,(AAudioStream *s,void *data,int32_t count,int64_t timeout),(s,data,count,timeout),AAUDIO_ERROR_UNAVAILABLE)
RET(AAudioStream_write,aaudio_result_t,(AAudioStream *s,const void *data,int32_t count,int64_t timeout),(s,data,count,timeout),AAUDIO_ERROR_UNAVAILABLE)
RET(AAudioStream_setBufferSizeInFrames,aaudio_result_t,(AAudioStream *s,int32_t count),(s,count),AAUDIO_ERROR_UNAVAILABLE)
__attribute__((visibility("default"))) aaudio_result_t AAudioStream_getTimestamp(AAudioStream *s,clockid_t clock,int64_t *frame,int64_t *ns) {
    return stream_timestamp ? stream_timestamp(s,clock,frame,ns) : AAUDIO_ERROR_UNAVAILABLE;
}
__attribute__((visibility("default"))) const char *AAudio_convertResultToText(aaudio_result_t v) {
    return result_text ? result_text(v) : "AAudio unavailable";
}
RET(AAudio_convertStreamStateToText,const char*,(aaudio_stream_state_t v),(v),"unknown")

JNIEXPORT void JNICALL Java_com_myune_music_AudioOutputManager_nativeInitialize(JNIEnv *env,jclass cls) {
    pthread_mutex_lock(&lock);
    (*env)->GetJavaVM(env,&jvm);
    if (callback_class) (*env)->DeleteGlobalRef(env,callback_class);
    callback_class = (*env)->NewGlobalRef(env,cls);
    callback_method = (*env)->GetStaticMethodID(env,cls,"onNativeChanged","()V");
    pthread_mutex_unlock(&lock);
}
JNIEXPORT void JNICALL Java_com_myune_music_AudioOutputManager_nativeDetach(JNIEnv *env,jclass cls) {
    (void)cls;
    pthread_mutex_lock(&lock);
    if (callback_class) (*env)->DeleteGlobalRef(env,callback_class);
    callback_class = 0; callback_method = 0;
    pthread_mutex_unlock(&lock);
}
static int32_t query32(AAudioStream *s, const char *name) {
    int32_t (*fn)(AAudioStream*) = resolve(name);
    return fn ? fn(s) : 0;
}
JNIEXPORT jlongArray JNICALL Java_com_myune_music_AudioOutputManager_nativeSnapshot(JNIEnv *env,jclass cls) {
    (void)cls;
    jlong v[18] = {0};
    pthread_mutex_lock(&lock);
    v[0] = revision; v[17] = last_error;
    v[1] = untracked_streams;
    AAudioStream *s = 0;
    for (int i = 0; i < 16; i++) if (streams[i]) { s = streams[i]; v[1]++; }
    if (s) {
        v[2] = query32(s,"AAudioStream_getDeviceId");
        v[3] = query32(s,"AAudioStream_getSampleRate"); v[4] = query32(s,"AAudioStream_getFormat");
        v[5] = query32(s,"AAudioStream_getChannelCount"); v[6] = query32(s,"AAudioStream_getSharingMode");
        v[7] = query32(s,"AAudioStream_getState");
        int64_t (*written)(AAudioStream*) = resolve("AAudioStream_getFramesWritten");
        if (written) v[8] = written(s);
        int64_t frame = 0, ns = 0;
        aaudio_result_t (*timestamp)(AAudioStream*,clockid_t,int64_t*,int64_t*) = resolve("AAudioStream_getTimestamp");
        if (timestamp && timestamp(s,CLOCK_MONOTONIC,&frame,&ns) == AAUDIO_OK) { v[9] = frame; v[10] = ns; }
        struct timespec now; clock_gettime(CLOCK_MONOTONIC,&now);
        v[11] = (int64_t)now.tv_sec * 1000000000 + now.tv_nsec;
        const char *extra[] = {"AAudioStream_getHardwareSampleRate","AAudioStream_getHardwareFormat","AAudioStream_getHardwareChannelCount"};
        for (int i = 0; i < 3; i++) {
            int32_t (*fn)(AAudioStream*) = resolve(extra[i]);
            if (fn) v[12+i] = fn(s);
        }
        v[15] = query32(s,"AAudioStream_getXRunCount");
        v[16] = query32(s,"AAudioStream_getBufferSizeInFrames");
    }
    pthread_mutex_unlock(&lock);
    jlongArray out = (*env)->NewLongArray(env,18);
    if (out) (*env)->SetLongArrayRegion(env,out,0,18,v);
    return out;
}
