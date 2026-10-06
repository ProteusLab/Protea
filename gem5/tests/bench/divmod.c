// Division and remainder: long-latency, non-pipelined units.
// volatile keeps the compiler from folding the q * d + r == n check.
static volatile int vq, vr;
static volatile unsigned vuq, vur;

int main(void)
{
    unsigned x = 987654321u;
    for (int i = 0; i < 2000; i++) {
        x = x * 1664525u + 1013904223u;
        int n = (int)x, d = (int)(x >> 13) | 1;
        if ((i & 1) == 0)
            d = -d;
        vq = n / d;
        vr = n % d;
        if (vq * d + vr != n)
            return 1;
        vuq = x / 97u;
        vur = x % 97u;
        if (vuq * 97u + vur != x)
            return 2;
    }
    return 0;
}
