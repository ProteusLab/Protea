// Bubble sort: data-dependent branches, loads and stores.
#define N 200
static int a[N];

int main(void)
{
    unsigned x = 12345;
    for (int i = 0; i < N; i++) {
        x = x * 1103515245u + 12345u;
        a[i] = (int)(x >> 8);
    }
    for (int i = 0; i < N; i++)
        for (int j = 0; j + 1 < N - i; j++)
            if (a[j] > a[j + 1]) {
                int t = a[j];
                a[j] = a[j + 1];
                a[j + 1] = t;
            }
    for (int i = 0; i + 1 < N; i++)
        if (a[i] > a[i + 1])
            return 1;
    return 0;
}
