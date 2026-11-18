/* Board surface the CT fixture calls: USART2 (the ST-Link VCP on the
   Discovery kit, modelled by Renode as sysbus.usart2) and SysTick. No libc. */
void uart_puts(const char *s);
void uart_putu(unsigned int v);
void systick_start(unsigned int reload);
unsigned int tick_count(void);
int button_pressed(void);
void board_idle(void);
