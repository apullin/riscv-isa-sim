// See LICENSE for license details.

#include "decode_macros.h"
#include "arith.h"
#include "mmu.h"
#include "softfloat.h"
#include "internals.h"
#include "specialize.h"
#include "tracer.h"
#include "p_ext_macros.h"
#include "v_ext_macros.h"
#include "debug_defines.h"
#include <assert.h>

reg_t fast_rv64i_add(processor_t*, insn_t, reg_t)
  __attribute__((aligned(64)));
reg_t fast_rv64i_csrrs(processor_t*, insn_t, reg_t)
  __attribute__((aligned(64)));
reg_t fast_rv64i_vslidedown_vx(processor_t*, insn_t, reg_t)
  __attribute__((aligned(64)));
reg_t fast_rv64i_vslideup_vx(processor_t*, insn_t, reg_t)
  __attribute__((aligned(64)));
