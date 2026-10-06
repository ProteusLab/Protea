// Recursion: calls and returns (return address stack).
__attribute__((noinline)) static int fib(int n)
{
    return n < 2 ? n : fib(n - 1) + fib(n - 2);
}

int main(void)
{
    return fib(18) == 2584 ? 0 : 1;
}
