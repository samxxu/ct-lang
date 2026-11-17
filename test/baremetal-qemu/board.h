/* Declarations the CT fixture calls: a UART and a SysTick counter, implemented
   in board.c against the lm3s6965evb memory map. No libc. */
void uart_puts(const char *s);
void systick_start(unsigned int reload);
unsigned int tick_count(void);
void board_exit(int code);
