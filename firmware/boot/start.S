/* Minimal RV64 reset entry. Platform ROM authenticates and copies the image
 * before transferring control here. */
  .section .text.init
  .globl _start
  .type _start, @function
_start:
  csrwi mie, 0
  la t0, _trap
  csrw mtvec, t0
  .option push
  .option norelax
  la gp, __global_pointer$
  .option pop
  la sp, __stack_top
  la t0, __bss_start
  la t1, __bss_end
1:
  bgeu t0, t1, 2f
  sd zero, 0(t0)
  addi t0, t0, 8
  j 1b
2:
  call rcif_platform_main
3:
  wfi
  j 3b

  .align 2
_trap:
  csrwi mie, 0
4:
  wfi
  j 4b
