// CRC-32: shifts, xors, unpredictable branches, table loads.
#define LEN 2048
static unsigned char buf[LEN];
static unsigned table[256];

static unsigned crc_bitwise(void)
{
    unsigned crc = 0xffffffffu;
    for (int i = 0; i < LEN; i++) {
        crc ^= buf[i];
        for (int k = 0; k < 8; k++)
            crc = (crc & 1) ? (crc >> 1) ^ 0xedb88320u : crc >> 1;
    }
    return ~crc;
}

static unsigned crc_table(void)
{
    unsigned crc = 0xffffffffu;
    for (int i = 0; i < LEN; i++)
        crc = table[(crc ^ buf[i]) & 0xff] ^ (crc >> 8);
    return ~crc;
}

int main(void)
{
    for (int i = 0; i < LEN; i++)
        buf[i] = (unsigned char)(i * 31 + (i >> 3));
    for (unsigned n = 0; n < 256; n++) {
        unsigned c = n;
        for (int k = 0; k < 8; k++)
            c = (c & 1) ? (c >> 1) ^ 0xedb88320u : c >> 1;
        table[n] = c;
    }
    return crc_bitwise() == crc_table() ? 0 : 1;
}
