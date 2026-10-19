/*
 * mock_hal_impl.c - the fake HAL implementation (no external dependency).
 *
 * The layout below is the one the binding mirrors in uart.ct.
 */
#include "mock_hal.h"

struct mock_uart {
    int fd;
};

int mock_uart_send(struct mock_uart *u, char *buf, int len)
{
    (void)buf;
    return len + u->fd;
}
