/* The shim beside `socket.m.ct`. A recipe only carries a call, so the shapes
   the POSIX API needs -- the `int sv[2]` out-parameter, the `const void *` /
   `size_t` casts, the `errno` global -- live here instead. Header-only: every
   accessor is `static inline`, so no `.shim.c` is needed. */
#include <errno.h>
#include <sys/socket.h>
#include <unistd.h>

static inline int ct_sock_pair(int *sv)
{
    return socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
}

static inline int ct_sock_send(int fd, const char *buf, int n)
{
    return (int)write(fd, buf, (size_t)n);
}

static inline int ct_sock_recv(int fd, char *buf, int n)
{
    return (int)read(fd, buf, (size_t)n);
}

static inline int ct_sock_errno(void)
{
    return errno;
}
