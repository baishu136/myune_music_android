#ifndef MYUNE_SHARED_AUDIO_BUFFER_H
#define MYUNE_SHARED_AUDIO_BUFFER_H
#include <stdint.h>

// Music needs scheduling margin; explicit low-latency/exclusive requests stay intact.
static inline int32_t myune_buffer_floor(int32_t rate, int shared, int ordinary) {
    return shared && ordinary && rate >= 8000 && rate <= 384000 ? rate / 5 : 0;
}
static inline int32_t myune_buffer_size(int32_t floor, int32_t capacity, int32_t current) {
    int32_t target = floor < capacity ? floor : capacity;
    return target > current ? target : current;
}
#endif
