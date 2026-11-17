/* Vector table and reset path for the lm3s6965evb model. `.data` is copied from
   flash and `.bss` cleared before `main`, then `main`'s value exits through
   semihosting (board_exit). */
extern unsigned int _estack;
extern unsigned int _sidata;
extern unsigned int _sdata;
extern unsigned int _edata;
extern unsigned int _sbss;
extern unsigned int _ebss;

extern int main(void);
void board_exit(int code);

void Reset_Handler(void);
void SysTick_Handler(void);

__attribute__((naked)) void Default_Handler(void)
{
    for (;;) { }
}

__attribute__((section(".vectors"), used))
void (*const g_vectors[16])(void) = {
    (void (*)(void))&_estack,
    Reset_Handler,
    Default_Handler,   /* NMI */
    Default_Handler,   /* HardFault */
    Default_Handler,   /* MemManage */
    Default_Handler,   /* BusFault */
    Default_Handler,   /* UsageFault */
    0, 0, 0, 0,
    Default_Handler,   /* SVCall */
    0, 0,
    Default_Handler,   /* PendSV */
    SysTick_Handler,
};

void Reset_Handler(void)
{
    unsigned int *src = &_sidata;
    unsigned int *dst = &_sdata;
    while (dst < &_edata) *dst++ = *src++;
    for (dst = &_sbss; dst < &_ebss; dst++) *dst = 0;
    board_exit(main());
}
