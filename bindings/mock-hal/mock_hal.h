/*
 * mock_hal.h - the fake HAL behind the Phase 12 binding demo.
 *
 * The struct is deliberately OPAQUE here: a binding mirrors the layout in CT
 * (see uart.ct), and C only allows completing an incomplete type once per
 * translation unit. Keep the two layouts in sync - that is the ABI contract.
 */
#ifndef MOCK_HAL_H
#define MOCK_HAL_H

struct mock_uart;

int mock_uart_send(struct mock_uart *u, char *buf, int len);

#endif
