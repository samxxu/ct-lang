/* Board glue for the QEMU `lm3s6965evb` model (Cortex-M3, 256K flash / 64K RAM).
   UART0 sits at 0x4000C000; SysTick is the standard ARM block. No libc: the
   only exit is ARM semihosting, so a probe sees a real exit code. */
typedef unsigned int u32;

#define UART0 ((volatile u32 *)0x4000C000)
#define UART_FR (UART0[0x18 / 4])
#define UART_DR (UART0[0])
#define SYST_CSR (*(volatile u32 *)0xE000E010)
#define SYST_RVR (*(volatile u32 *)0xE000E014)
#define SYST_CVR (*(volatile u32 *)0xE000E018)

volatile u32 g_ticks;

void uart_putc(char c)
{
    while (UART_FR & (1u << 5)) { }   /* TXFF */
    UART_DR = (u32)(unsigned char)c;
}

void uart_puts(const char *s)
{
    while (*s) uart_putc(*s++);
}

/* CLKSOURCE=1 (processor clock), TICKINT=1, ENABLE=1. */
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

/* SYS_EXIT_EXTENDED (0x20): a two-word block gives QEMU the real exit code,
   so the probe can tell "finished" from "hung" without a timeout heuristic. */
void board_exit(int code)
{
    u32 block[2];
    register u32 r0 __asm__("r0") = 0x20;
    register u32 r1 __asm__("r1");

    block[0] = 0x20026;                            /* ADP_Stopped_ApplicationExit */
    block[1] = (u32)code;
    r1 = (u32)block;
    __asm__ volatile ("bkpt 0xAB" : : "r"(r0), "r"(r1) : "memory");
}
