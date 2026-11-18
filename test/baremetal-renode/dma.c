/* DMA1 Stream6 is USART2_TX on the STM32F4 (channel 4). This programs the
   descriptor and reads it back; it deliberately leaves EN clear so no bytes
   are moved (the real transfer is hardware-gated, see the issue). */
typedef unsigned int u32;

#define RCC_AHB1ENR (*(volatile u32 *)0x40023830)
#define DMA1        ((volatile u32 *)0x40026000)
#define S6CR        (DMA1[0xA0 / 4])
#define S6NDTR      (DMA1[0xA4 / 4])
#define S6PAR       (DMA1[0xA8 / 4])
#define S6M0AR      (DMA1[0xAC / 4])
#define S6FCR       (DMA1[0xB4 / 4])
#define USART2_DR   0x40004404u

int dma_setup_tx(const void *buf, unsigned int len)
{
    RCC_AHB1ENR = RCC_AHB1ENR | (1u << 21);
    S6CR = 0;
    S6NDTR = len;
    S6PAR = USART2_DR;
    S6M0AR = (u32)buf;
    S6FCR = 0;
    /* DIR = memory->peripheral, MINC = memory increment, CHSEL = 4. */
    S6CR = (1u << 4) | (1u << 10) | (4u << 25);
    if (S6PAR != USART2_DR) return 0;
    if (S6M0AR != (u32)buf) return 0;
    if (S6NDTR != len) return 0;
    if ((S6CR & ((1u << 4) | (1u << 10))) != ((1u << 4) | (1u << 10))) return 0;
    return 1;
}
