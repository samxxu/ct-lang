/* Vector table wired to the FreeRTOS Cortex-M3 port handlers. */
extern unsigned int _estack;
extern unsigned int _sidata;
extern unsigned int _sdata;
extern unsigned int _edata;
extern unsigned int _sbss;
extern unsigned int _ebss;

extern int main(void);
void Reset_Handler(void);
void Default_Handler(void);

/* From portable/GCC/ARM_CM3/port.c */
void vPortSVCHandler(void);
void xPortPendSVHandler(void);
void xPortSysTickHandler(void);

void Default_Handler(void)
{
    for (;;) { }
}

__attribute__((section(".vectors"), used))
void (*const g_vectors[16 + 82])(void) = {
    (void (*)(void))&_estack,
    Reset_Handler,
    Default_Handler, Default_Handler, Default_Handler, Default_Handler,
    Default_Handler, 0, 0, 0, 0,
    vPortSVCHandler,
    Default_Handler, Default_Handler,
    xPortPendSVHandler,
    xPortSysTickHandler,
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
