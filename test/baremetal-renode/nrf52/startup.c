/* Vector table and reset path for nRF52840 (Cortex-M4F, 48 IRQs). */
extern unsigned int _estack;
extern unsigned int _sidata;
extern unsigned int _sdata;
extern unsigned int _edata;
extern unsigned int _sbss;
extern unsigned int _ebss;

extern int main(void);
void Reset_Handler(void);

void Default_Handler(void)
{
    for (;;) { }
}

__attribute__((section(".vectors"), used))
void (*const g_vectors[16 + 48])(void) = {
    (void (*)(void))&_estack,
    Reset_Handler,
    Default_Handler, Default_Handler, Default_Handler, Default_Handler,
    Default_Handler, 0, 0, 0, 0,
    Default_Handler, 0, 0,
    Default_Handler, 0,
};

void Reset_Handler(void)
{
    unsigned int *src = &_sidata;
    unsigned int *dst = &_sdata;
    while (dst < &_edata) *dst++ = *src++;
    for (dst = &_sbss; dst < &_ebss; dst++) *dst = 0;
    (void)main();
    for (;;) { }
}
