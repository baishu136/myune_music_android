#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "quickjs.h"

// Called only by the isolated service's single worker. No libc JS modules,
// file/network bindings, native module loader or shared player memory.
static JSRuntime *runtime;
static JSContext *context;
static JSValue bridge;
static int64_t deadline, wall_deadline, remaining;
static int interrupted;
static int64_t now_ns(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000LL + t.tv_nsec;
}
static int interrupt(JSRuntime *rt, void *opaque) {
    struct timespec t;
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t);
    int64_t cpu = (int64_t)t.tv_sec * 1000000000LL + t.tv_nsec;
    if (cpu >= deadline || now_ns() >= wall_deadline) interrupted = 1;
    return interrupted;
}
static void clear(void) {
    if (context) {
        JS_FreeValue(context, bridge);
        JS_FreeContext(context);
    }
    if (runtime) JS_FreeRuntime(runtime);
    context = NULL; runtime = NULL;
}
static char *utf8(JNIEnv *env, jbyteArray bytes) {
    jsize n = (*env)->GetArrayLength(env, bytes);
    if (n > 262144) return NULL;
    char *s = malloc((size_t)n + 1);
    if (!s) return NULL;
    (*env)->GetByteArrayRegion(env, bytes, 0, n, (jbyte *)s);
    s[n] = 0;
    return s;
}
static jbyteArray output(JNIEnv *env, const char *s, size_t n) {
    if (n > 196608) {
        s = "{\"done\":true,\"error\":\"output limit\",\"calls\":[]}";
        n = strlen(s);
    }
    jbyteArray b = (*env)->NewByteArray(env, n);
    if (b) (*env)->SetByteArrayRegion(env, b, 0, n, (const jbyte *)s);
    return b;
}
static jbyteArray failure(JNIEnv *env, const char *fallback) {
    const char *message = interrupted ? "execution time limit" : fallback;
    JSValue exception = JS_UNDEFINED;
    const char *detail = NULL;
    if (context && !interrupted) {
        exception = JS_GetException(context);
        detail = JS_ToCString(context, exception);
        if (detail) message = detail;
    }
    // Escape bytes without allocating inside a possibly exhausted JS heap.
    char text[4096] = "{\"done\":true,\"calls\":[],\"error\":\"";
    size_t n = strlen(text);
    for (size_t i = 0; message[i] && i < 1000 && n < sizeof(text)-10; i++) {
        unsigned char c = message[i];
        if (c < 32) text[n++] = ' ';
        else {
            if (c == '\\' || c == '"') text[n++] = '\\';
            text[n++] = c;
        }
    }
    text[n++] = '"'; text[n++] = '}'; text[n] = 0;
    if (detail) JS_FreeCString(context, detail);
    if (context) JS_FreeValue(context, exception);
    jbyteArray result = output(env, text, n);
    clear();
    return result;
}
JNIEXPORT jbyteArray JNICALL
Java_com_myune_music_PluginScriptService_nativeRun(JNIEnv *env, jobject self,
        jint op, jbyteArray code, jbyteArray boot, jbyteArray input) {
    if (op == 2) {
        clear();
        const char *done = "{\"done\":true,\"calls\":[]}";
        return output(env, done, strlen(done));
    }
    // Scheduling waits are not script execution. Bound CPU and wall time
    // separately so cold-start contention doesn't consume the CPU allowance.
    struct timespec cpu_time;
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpu_time);
    int64_t started = (int64_t)cpu_time.tv_sec * 1000000000LL + cpu_time.tv_nsec;
    wall_deadline = now_ns() + 1500000000LL;
    interrupted = 0;
    if (op == 0) {
        clear();
        remaining = 500000000LL;
        runtime = JS_NewRuntime();
        if (!runtime) return failure(env, "runtime allocation failed");
        JS_SetMemoryLimit(runtime, 12 * 1024 * 1024);
        JS_SetMaxStackSize(runtime, 256 * 1024);
        JS_SetInterruptHandler(runtime, interrupt, NULL);
        context = JS_NewContext(runtime);
        bridge = JS_UNDEFINED;
        if (!context) return failure(env, "context allocation failed");
        deadline = started + remaining;
        char *bootstrap = utf8(env, boot), *source = utf8(env, code);
        if (!bootstrap || !source) {
            free(bootstrap); free(source);
            return failure(env, "source limit");
        }
        bridge = JS_Eval(context, bootstrap, strlen(bootstrap), "sdk.js", JS_EVAL_TYPE_GLOBAL);
        free(bootstrap);
        if (JS_IsException(bridge)) {
            free(source); bridge = JS_UNDEFINED;
            return failure(env, "SDK initialization failed");
        }
        JSValue evaluated = JS_Eval(context, source, strlen(source), "plugin.js", JS_EVAL_TYPE_GLOBAL);
        free(source);
        if (JS_IsException(evaluated)) return failure(env, "script initialization failed");
        JS_FreeValue(context, evaluated);
    } else {
        if (!context) return failure(env, "runtime not active");
        deadline = started + remaining;
    }
    char *data = utf8(env, input);
    if (!data) return failure(env, "input limit");
    JSValue arg = JS_ParseJSON(context, data, strlen(data), "input.json");
    free(data);
    if (JS_IsException(arg)) return failure(env, "invalid input");
    JSValue fn = JS_GetPropertyStr(context, bridge, op == 0 ? "start" : "accept");
    JSValue result = JS_Call(context, fn, JS_UNDEFINED, 1, &arg);
    JS_FreeValue(context, fn); JS_FreeValue(context, arg);
    if (JS_IsException(result)) return failure(env, "script failed");
    JS_FreeValue(context, result);
    JSContext *job_context;
    int jobs = 0;
    while (JS_IsJobPending(runtime)) {
        if (++jobs > 2048 || interrupt(runtime, NULL)) return failure(env, "execution limit");
        if (JS_ExecutePendingJob(runtime, &job_context) < 0) return failure(env, "async job failed");
    }
    fn = JS_GetPropertyStr(context, bridge, "take");
    result = JS_Call(context, fn, JS_UNDEFINED, 0, NULL);
    JS_FreeValue(context, fn);
    if (JS_IsException(result)) return failure(env, "invalid result");
    size_t n;
    const char *text = JS_ToCStringLen(context, &n, result);
    if (!text) return failure(env, "result allocation failed");
    jbyteArray reply = output(env, text, n);
    JS_FreeCString(context, text); JS_FreeValue(context, result);
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpu_time);
    remaining -= (int64_t)cpu_time.tv_sec * 1000000000LL + cpu_time.tv_nsec - started;
    return reply;
}
