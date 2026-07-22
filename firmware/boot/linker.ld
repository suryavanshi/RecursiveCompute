OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  SRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 256K
}

SECTIONS {
  .text : { *(.text.init) *(.text .text.*) } > SRAM
  .rodata : { *(.rodata .rodata.*) } > SRAM
  .data : {
    __global_pointer$ = . + 0x800;
    *(.sdata .sdata.*)
    *(.data .data.*)
  } > SRAM
  .bss (NOLOAD) : {
    . = ALIGN(8);
    __bss_start = .;
    *(.bss .bss.* COMMON)
    . = ALIGN(16);
    __bss_end = .;
  } > SRAM
  . = ORIGIN(SRAM) + LENGTH(SRAM);
  __stack_top = .;
}
