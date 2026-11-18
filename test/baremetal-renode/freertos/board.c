/* USART2 on the STM32F4 Discovery model; SysTick belongs to FreeRTOS here. */
typedef unsigned int u32;

#define RCC         ((volatile u32 *)0x40023800)
#define RCC_AHB1ENR (RCC[0x30 / 4])
#define RCC_APB1ENR (RCC[0x40 / 4])
#define GPIOA       ((volatile u32 *)0x40020000)
#define GPIOA_MODER (GPIOA[0x00 / 4])
#define GPIOA_AFR0  (GPIOA[0x20 / 4])
#define USART2      ((volatile u32 *)0x40004400)
#define USART_SR    (USART2[0x00 / 4])
#define USART_DR    (USART2[0x04 / 4])
#define USART_BRR   (USART2[0x08 / 4])
#define USART_CR1   (USART2[0x0C / 4])

static void usart2_init(void)
{
    RCC_AHB1ENR |= 1u;
    RCC_APB1ENR |= 1u << 17;
    GPIOA_MODER = (GPIOA_MODER & ~((3u << 4) | (3u << 6))) | (2u << 4) | (2u << 6);
    GPIOA_AFR0 = (GPIOA_AFR0 & ~((0xFu << 8) | (0xFu << 12)))
               | (7u << 8) | (7u << 12);
    USART_BRR = 0x008B;
    USART_CR1 = (1u << 13) | (1u << 3) | (1u << 2);
}

void uart_putc(char c)
{
    while ((USART_SR & (1u << 7)) == 0) { }
    USART_DR = (u32)(unsigned char)c;
}

void uart_putu(unsigned int v)
{
    char buf[12];
    int i = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v > 0 && i < (int)sizeof(buf)) { buf[i++] = (char)('0' + (v % 10u)); v = v / 10u; }
    while (i > 0) uart_putc(buf[--i]);
}

void uart_puts(const char *s)
{
    usart2_init();
    while (*s) uart_putc(*s++);
}
