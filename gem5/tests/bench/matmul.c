// Integer matrix multiplication: mul latency, regular memory access.
#define N 16
static int a[N][N], b[N][N], c[N][N], bt[N][N];

int main(void)
{
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            a[i][j] = i * 7 + j * 3 - 50;
            b[i][j] = i * 5 - j * 11 + 13;
            bt[j][i] = b[i][j];
        }
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            int s = 0;
            for (int k = 0; k < N; k++)
                s += a[i][k] * b[k][j];
            c[i][j] = s;
        }
    // Cross-check with the transposed operand.
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            int s = 0;
            for (int k = 0; k < N; k++)
                s += a[i][k] * bt[j][k];
            if (s != c[i][j])
                return 1;
        }
    return 0;
}
