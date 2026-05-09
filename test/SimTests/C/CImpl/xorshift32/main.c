#include <stdint.h>

volatile uint32_t seed = 2463534242u;

constexpr uint32_t N = 1024 * 1024;
uint32_t buffer[N];

uint32_t xorshift32(uint32_t x) {
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
}

uint32_t run() {
    uint32_t x = seed;

    for (uint32_t i = 0; i < N; ++i) {
        x = xorshift32(x);
        buffer[i] = x;
    }

    uint32_t sum = 0;

    for (uint32_t i = 0; i < N; ++i)
        sum ^= buffer[i];

    return sum;
}

int main() {
    return run() == 752068848 ? 0 : 1;
}
