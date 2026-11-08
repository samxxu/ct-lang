#ifndef PKT_SHIM_H
#define PKT_SHIM_H

/* 由 .shim.c 实现的数据包：payload 是隐藏缓冲区，只有 pkt_free 知道怎么拆。 */
struct Packet {
    int id;
    int len;
    char *payload;
};

/* 返回所有权：调用方必须用 pkt_free 归还（不能只 free 结构体）。 */
struct Packet *pkt_open(int id, int len);

/* 借用视图：返回的指针归原数据包所有，调用方不能释放。 */
struct Packet *pkt_peek(struct Packet *p);

void pkt_free(struct Packet *p);
int pkt_live(void);

#endif
