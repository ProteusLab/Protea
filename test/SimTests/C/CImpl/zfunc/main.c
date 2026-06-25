#define MAXN 1024
const char *const str = "aBaBCAcabbBAababababcbCBCcbcBABbcbBbabacbBABcb";

int strlen(const char *str) {
  int result = 0;
  while (str[result] != '\0')
    ++result;
  return result;
}

void z_function(const char *s, int n, int z[]) {
  z[0] = n;

  int l = 0;
  int r = 0;

  for (int i = 1; i < n; ++i) {
    if (i <= r) {
      int k = i - l;
      int rem = r - i + 1;
      z[i] = (z[k] < rem) ? z[k] : rem;
    } else {
      z[i] = 0;
    }

    while (i + z[i] < n && s[z[i]] == s[i + z[i]])
      ++z[i];

    if (i + z[i] - 1 > r) {
      l = i;
      r = i + z[i] - 1;
    }
  }
}

int check_z_function(const char *s, int n, int z[]) {

  if (z[0] != n)
    return 1;
  for (int i = 1; i < n; ++i) {
    int expected = 0;
    while (i + expected < n && s[expected] == s[i + expected])
      ++expected;
    if (z[i] != expected)
      return 1;
  }
  return 0;
}

int main() {
  int z[MAXN];

  z_function(str, strlen(str), z);
  return check_z_function(str, strlen(str), z);
}
