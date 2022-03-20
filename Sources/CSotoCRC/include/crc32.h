#include "../zconf.h"

unsigned long ZEXPORT soto_crc32(unsigned long crc, const unsigned char FAR *buf, uInt len);
unsigned long ZEXPORT soto_crc32_z(unsigned long crc, const unsigned char FAR *buf, z_size_t len);
