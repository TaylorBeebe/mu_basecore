//
// Copyright (c) 2012 - 2016, Linaro Limited
// All rights reserved.
// Copyright (c) 2015 ARM Ltd
// All rights reserved.
// SPDX-License-Identifier: BSD-2-Clause-Patent
//

// Assumptions:
//
// ARMv8-a, AArch64, unaligned accesses
//
//

#define dstin     x0
#define count     x1
#define val       x2
#define valw      w2
#define dst       x3
#define dstend    x4
#define tmp1      x5
#define tmp1w     w5
#define tmp2      x6
#define tmp2w     w6
#define zva_len   x7
#define zva_lenw  w7

  EXPORT InternalMemSetMem16
  EXPORT InternalMemSetMem32
  EXPORT InternalMemSetMem64
  EXPORT InternalMemZeroMem
  EXPORT InternalMemSetMem

  AREA |.text|, CODE, READONLY, ALIGN=4

InternalMemSetMem16
    dup     v0.8H, valw
    lsl     count, count, #1
    b       InternalMemSetMem_0

InternalMemSetMem32
    dup     v0.4S, valw
    lsl     count, count, #2
    b       InternalMemSetMem_0

InternalMemSetMem64
    dup     v0.2D, val
    lsl     count, count, #3
    b       InternalMemSetMem_0

InternalMemZeroMem
    movi    v0.16B, #0
    b       InternalMemSetMem_0

InternalMemSetMem
    dup     v0.16B, valw
InternalMemSetMem_0
    add     dstend, dstin, count
    UMOV     val, v0.D[0]

    cmp     count, 96
    b.hi    set_long
    cmp     count, 16
    b.hs    set_medium

    // Set 0..15 bytes.
    tbz     count, 3, InternalMemSetMem_1
    str     val, [dstin]
    sub     tmp2, dstend, 8
    str     val, [tmp2]
    ret
    nop
InternalMemSetMem_1
    tbz     count, 2, InternalMemSetMem_2
    str     valw, [dstin]
    sub     tmp2, dstend, 4
    str     valw, [tmp2]
    ret
InternalMemSetMem_2
    cbz     count, InternalMemSetMem_3
    strb    valw, [dstin]
    tbz     count, 1, InternalMemSetMem_3
    sub     tmp2, dstend, -2
    strh    valw, [tmp2]
InternalMemSetMem_3
    ret

    // Set 17..96 bytes.
set_medium
    str     q0, [dstin]
    tbnz    count, 6, set96
    sub     tmp2, dstend, 16
    str     q0, [tmp2]
    tbz     count, 5, set_medium_1
    str     q0, [dstin, 16]
    sub     tmp2, dstend, 32
    str     q0, [tmp2]
set_medium_1
    ret

  ALIGN 16
    // Set 64..96 bytes.  Write 64 bytes from the start and
    // 32 bytes from the end.
set96
    str     q0, [dstin, 16]
    stp     q0, q0, [dstin, 32]
    stp     q0, q0, [dstend, -32]
    ret

  ALIGN 8
    nop
set_long
    bic     dst, dstin, 15
    str     q0, [dstin]
    cmp     count, 256
    ccmp    val, 0, 0, cs
    b.eq    try_zva
no_zva
    sub     count, dstend, dst        // Count is 16 too large.
    add     dst, dst, 16
    sub     count, count, 64 + 16     // Adjust count and bias for loop.
no_zva_1
    stp     q0, q0, [dst], 64
    stp     q0, q0, [dst, -32]
tail64
    subs    count, count, 64
    b.hi    no_zva_1
2
    stp     q0, q0, [dstend, -64]
    stp     q0, q0, [dstend, -32]
    ret

    ALIGN 8
try_zva
    mrs     tmp1, dczid_el0
    tbnz    tmp1w, 4, no_zva
    and     tmp1w, tmp1w, 15
    cmp     tmp1w, 4                  // ZVA size is 64 bytes.
    b.ne    zva_128

    // Write the first and last 64 byte aligned block using stp rather
    // than using DC ZVA.  This is faster on some cores.
zva_64
    str     q0, [dst, 16]
    stp     q0, q0, [dst, 32]
    bic     dst, dst, 63
    stp     q0, q0, [dst, 64]
    stp     q0, q0, [dst, 96]
    sub     count, dstend, dst         // Count is now 128 too large.
    sub     count, count, 128+64+64    // Adjust count and bias for loop.
    add     dst, dst, 128
    nop
zva_64_1
    dc      zva, dst
    add     dst, dst, 64
    subs    count, count, 64
    b.hi    zva_64_1
    stp     q0, q0, [dst, 0]
    stp     q0, q0, [dst, 32]
    stp     q0, q0, [dstend, -64]
    stp     q0, q0, [dstend, -32]
    ret

    ALIGN 8
zva_128
    cmp     tmp1w, 5                    // ZVA size is 128 bytes.
    b.ne    zva_other

    str     q0, [dst, 16]
    stp     q0, q0, [dst, 32]
    stp     q0, q0, [dst, 64]
    stp     q0, q0, [dst, 96]
    bic     dst, dst, 127
    sub     count, dstend, dst          // Count is now 128 too large.
    sub     count, count, 128+128       // Adjust count and bias for loop.
    add     dst, dst, 128
zva_128_1
    dc      zva, dst
    add     dst, dst, 128
    subs    count, count, 128
    b.hi    zva_128_1
    stp     q0, q0, [dstend, -128]
    stp     q0, q0, [dstend, -96]
    stp     q0, q0, [dstend, -64]
    stp     q0, q0, [dstend, -32]
    ret

zva_other
    mov     tmp2w, 4
    lsl     zva_lenw, tmp2w, tmp1w
    add     tmp1, zva_len, 64           // Max alignment bytes written.
    cmp     count, tmp1
    blo     no_zva

    sub     tmp2, zva_len, 1
    add     tmp1, dst, zva_len
    add     dst, dst, 16
    subs    count, tmp1, dst            // Actual alignment bytes to write.
    bic     tmp1, tmp1, tmp2            // Aligned dc zva start address.
    beq     zva_other_2
zva_other_1
    stp     q0, q0, [dst], 64
    stp     q0, q0, [dst, -32]
    subs    count, count, 64
    b.hi    zva_other_1
zva_other_2
    mov     dst, tmp1
    sub     count, dstend, tmp1         // Remaining bytes to write.
    subs    count, count, zva_len
    b.lo    zva_other_4
zva_other_3
    dc      zva, dst
    add     dst, dst, zva_len
    subs    count, count, zva_len
    b.hs    zva_other_3
zva_other_4
    add     count, count, zva_len
    b       tail64
  END