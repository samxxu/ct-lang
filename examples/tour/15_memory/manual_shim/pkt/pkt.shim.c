#include "pkt.shim.h"

#include <stdio.h>
#include <stdlib.h>

static int g_live = 0;

struct Packet *pkt_open(int id, int len)
{
    struct Packet *p = malloc(sizeof(struct Packet));
    p->id = id;
    p->len = len;
    p->payload = malloc(len);      /* 结构体之外还有一块内存 */
    p->payload[0] = 'x';
    g_live = g_live + 1;
    printf("open %d len %d\n", id, len);
    return p;
}

struct Packet *pkt_peek(struct Packet *p)
{
    printf("peek %d\n", p->id);
    return p;
}

void pkt_free(struct Packet *p)
{
    printf("free %d payload %c\n", p->id, p->payload[0]);
    free(p->payload);              /* 先拆内部缓冲，再释放结构体本身 */
    free(p);
    g_live = g_live - 1;
}

int pkt_live(void)
{
    return g_live;
}
