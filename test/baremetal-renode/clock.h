/* STM32F4 clock tree: HSI 16 MHz -> PLL -> 168 MHz SYSCLK, APB1 42 MHz. */
void clock_init_168(void);
unsigned int clock_hz(void);
unsigned int uart_brr(unsigned int pclk);
