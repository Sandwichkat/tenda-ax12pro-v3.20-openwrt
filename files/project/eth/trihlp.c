// trihlp: call Triductor kernel HAL functions via /dev/tri_hlp ioctl.
//
// ABI decoded from tri_basic.ko tri_hlp_ioctl_impl:
//   ioctl(fd, any_cmd, buf) where buf is a user buffer laid out as:
//     off   0: u32 len        (bytes of args that follow)
//     off   4: char funcname[120]  (registered hcall_* name, NUL-terminated)
//     off 124: u32 len1       (tri_hlp_exhead_s)
//     off 128: u32 len2
//     off 132: u8 args[len]
//   kernel copies 136+len bytes from user, finds funcname, calls
//   handler(data=buf+124, size=len, &outlen) and copies the buffer back.
//
// Usage: trihlp <funcname> [hex_or_dec_words...]
//   e.g. trihlp hcall_tri_kernel_hal_port_eth_status_get 5
// Prints: ret=0x........  then the returned args as hex words.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define ARGS_OFF 132

int main(int argc, char **argv)
{
    unsigned char buf[136 + 64];
    int i, n, fd;
    uint32_t len;
    unsigned long ret;

    if (argc < 2) {
        fprintf(stderr, "usage: %s <funcname> [words...]\n", argv[0]);
        return 2;
    }
    memset(buf, 0, sizeof(buf));
    n = argc - 2;
    len = n * 4;
    if (len > 64) {
        fprintf(stderr, "too many args\n");
        return 2;
    }
    *(uint32_t *)&buf[0] = len;
    strncpy((char *)&buf[4], argv[1], 118);
    /* buf[124..131] = exhead (0,0) already zero */
    for (i = 0; i < n; i++)
        *(uint32_t *)&buf[ARGS_OFF + i * 4] = (uint32_t)strtoul(argv[2 + i], NULL, 0);

    fd = open("/dev/tri_hlp", O_RDWR);
    if (fd < 0) {
        perror("open /dev/tri_hlp");
        return 1;
    }
    ret = ioctl(fd, 0, buf);
    printf("ret=0x%lx\n", ret);
    printf("out:");
    for (i = 0; i < ((int)(len/4) > 8 ? (int)(len/4) : 8); i++)
        printf(" %08x", *(uint32_t *)&buf[ARGS_OFF + i * 4]);
    printf("\n");
    close(fd);
    return 0;
}
