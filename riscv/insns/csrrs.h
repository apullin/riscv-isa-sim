bool write = insn.rs1() != 0;
int csr = validate_csr(insn.csr(), write);
reg_t old;
#ifdef __clang__
if (likely(!write && STATE.prv == PRV_M && !STATE.v && STATE.csrmap_cache[csr] != nullptr)) {
  switch (csr) {
    case CSR_CYCLE:
      old = STATE.mcycle->read();
      goto csrrs_read_done;
    case CSR_INSTRET:
      old = STATE.minstret->read();
      goto csrrs_read_done;
    case CSR_TIME:
      old = STATE.time->read();
      goto csrrs_read_done;
  }
}
#endif
old = p->get_csr(csr, insn, write);
if (write) {
  p->put_csr(csr, old | RS1);
}
csrrs_read_done:
WRITE_RD(sext_xlen(old));
serialize();
