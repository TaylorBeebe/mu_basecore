//
// Copyright (c) 2016, Linaro Limited
// All rights reserved.
// SPDX-License-Identifier: BSD-2-Clause-Patent
//

  EXPORT  InternalMemCompareGuid    ; Make this symbol visible for the linker
  AREA    |.text|, CODE, ALIGN=5

InternalMemCompareGuid
  mov     x2, xzr
  ldp     x3, x4, [x0]
  cbz     x1, %F0
  ldp     x1, x2, [x1]
0
  cmp     x1, x3
  ccmp    x2, x4, #0, eq
  cset    w0, eq
  ret

  END
