/* STM32F407G-DISC1: 1 MiB flash at 0x08000000, 128 KiB SRAM at 0x20000000
   (CCM at 0x10000000 is left to the application). Renode's
   platforms/boards/stm32f4_discovery-kit.repl models the same map. */
MEMORY
{
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
}
_estack = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS
{
    .text : {
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
    } > FLASH
    _sidata = LOADADDR(.data);
    .data : { _sdata = .; *(.data*) _edata = .; } > RAM AT > FLASH
    .bss  : { _sbss = .; *(.bss*) *(COMMON) _ebss = .; } > RAM
}
