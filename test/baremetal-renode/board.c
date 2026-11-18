/* STM32F407 register glue. Addresses are the reference-manual ones Renode's
   STM32F4 platform maps: RCC, GPIOA, USART2 and the ARM SysTick block. */
typedef unsigned int u32;

#define RCC         ((volatile u32 *)0x40023800)
#define RCC_AHB1ENR (RCC[0x30 / 4])
#define RCC_APB1ENR (RCC[0x40 / 4])
#define GPIOA       ((volatile u32 *)0x40020000)
#define GPIOA_MODER (GPIOA[0x00 / 4])
#define GPIOA_IDR   (GPIOA[0x10 / 4])
#define GPIOA_AFR0  (GPIOA[0x20 / 4])
#define USART2      ((volatile u32 *)0x40004400)
#define USART_SR    (USART2[0x00 / 4])
#define USART_DR    (USART2[0x04 / 4])
#define USART_BRR   (USART2[0x08 / 4])
#define USART_CR1   (USART2[0x0C / 4])
#define SYST_CSR    (*(volatile u32 *)0xE000E010)
#define SYST_RVR    (*(volatile u32 *)0xE000E014)
#define SYST_CVR    (*(volatile u32 *)0xE000E018)

volatile u32 g_ticks;

/* PA2/PA3 in alternate-function mode 7 = USART2 TX/RX; 115200 is only
   nominal here (the model does not sample the line), but a real board
   needs it right. */
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

void uart_puts(const char *s)
{
    usart2_init();
    while (*s) uart_putc(*s++);
}

void systick_start(u32 reload)
{
    g_ticks = 0;
    SYST_RVR = reload;
    SYST_CVR = 0;
    SYST_CSR = 7;
}

u32 tick_count(void)
{
    return g_ticks;
}

void SysTick_Handler(void)
{
    g_ticks = g_ticks + 1;
}

/* Wait for the next interrupt. The idle loop would otherwise burn millions of
   instructions in the emulator (Renode's TCG is slow on some hosts). */
void board_idle(void)
{
    __asm__ volatile ("wfi");
}

/* The Discovery kit's user button is PA0: high when pressed (external
   pull-down). Renode's Button model starts released, so the probe sees 0. */
int button_pressed(void)
{
    return (GPIOA_IDR & 1u) ? 1 : 0;
}
