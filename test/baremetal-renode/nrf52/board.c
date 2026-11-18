/* nRF52840 UART0 register glue (tasks/events style, no SDK). */
typedef unsigned int u32;

#define UART0 ((volatile u32 *)0x40002000)
#define TASKS_STARTTX (UART0[0x008 / 4])
#define EVENTS_TXDRDY (UART0[0x11C / 4])
#define ENABLE        (UART0[0x500 / 4])
#define PSELTXD       (UART0[0x50C / 4])
#define TXD           (UART0[0x51C / 4])
#define BAUDRATE      (UART0[0x524 / 4])

static void uart0_init(void)
{
    PSELTXD = 6;                 /* any pin; the model does not route it */
    BAUDRATE = 0x01D7E000u;      /* 115200 */
    ENABLE = 4;
    TASKS_STARTTX = 1;
}

void uart_putc(char c)
{
    int i;
    TXD = (u32)(unsigned char)c;
    /* TXDRDY marks the byte as taken; bounded so a missing event in the model
       cannot hang the probe. */
    for (i = 0; i < 200000; i++) {
        if (EVENTS_TXDRDY != 0) break;
    }
    EVENTS_TXDRDY = 0;
}

void uart_puts(const char *s)
{
    uart0_init();
    while (*s) uart_putc(*s++);
}
