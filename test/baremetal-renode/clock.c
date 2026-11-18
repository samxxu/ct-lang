/* RCC bring-up for the STM32F407. The values below are the reference-manual
   standard: 16 MHz HSI / M=16 * N=336 / P=2 = 168 MHz SYSCLK; APB1 /2 = 42 MHz.
   Renode's STM32F4 platform does not model the RCC, so the frequency is kept in
   a shadow and the registers are still written (a real board locks the PLL). */
typedef unsigned int u32;

#define RCC         ((volatile u32 *)0x40023800)
#define RCC_CR      (RCC[0x00 / 4])
#define RCC_PLLCFGR (RCC[0x04 / 4])
#define RCC_CFGR    (RCC[0x08 / 4])

#define PLL_M 16u
#define PLL_N 336u
#define PLL_P 0u   /* encoding: 0 -> /2 */
#define PLL_Q 7u

#define PCLK1_HZ 42000000u
#define BAUD 115200u

static u32 g_hz;

void clock_init_168(void)
{
    /* PLLCFGR: M, N, P, Q, source = HSI (bit 22 = 0). */
    RCC_PLLCFGR = (PLL_M & 0x3Fu)
                | ((PLL_N & 0x1FFu) << 6)
                | ((PLL_P & 0x3u) << 16)
                | ((PLL_Q & 0xFu) << 24);
    /* CFGR: AHB /1, APB1 /2 (bits 12:10 = 100), APB2 /1, SYSCLK = PLL. */
    RCC_CFGR = (0x4u << 10) | 0x2u;
    RCC_CR = RCC_CR | (1u << 24); /* PLLON */
    g_hz = 168000000u;
}

unsigned int clock_hz(void)
{
    return g_hz;
}

/* USARTDIV = pclk / (16 * baud); the BRR register is that value with four
   fractional bits, i.e. numerically round(pclk / baud). */
unsigned int uart_brr(unsigned int pclk)
{
    return (pclk + BAUD / 2u) / BAUD;
}
