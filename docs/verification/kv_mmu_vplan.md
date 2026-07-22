# KV MMU Verification Plan

## Scope and configuration

The bounded target is `rcif_kv_mmu` with an eight-entry page table, four-entry
TLB, 16-bit virtual and physical page numbers, four physical tiers, and four
format bits. Tenant identity is not present on the Phase 3 RTL port and is
therefore checked in the independent full-chip security monitor until the
production interface carries an address-space identifier.

## Stimulus and checking

- Directed RTL: cold miss, map, TLB hit, page-walk refill, remap, full table,
  reserved bits, fault FIFO order and overflow.
- Random model: tenant, virtual page, physical tier, precision, page size,
  locality and fault injection.
- Scoreboard: `(tenant, virtual_page)` maps to exactly one current physical
  page; TLB and walker responses must agree with the map generation.
- Reset: invalidate transient responses and TLB entries; retain nothing unless
  a future retention register explicitly requests it.

## Assertions and coverage

- No response without a request; response stays stable while stalled.
- No cross-tenant lookup, refcount underflow, or reserved-bit acceptance.
- Cover hit/miss/remap/full crossed with page size, precision and physical tier.
- Negative tests in `dv/tests/full_chip/test_phase9_full_chip.py` must trip the
  cross-tenant and refcount monitors.

Signoff requires all planned bins, every assertion enabled and hit, and a
waiver for the absent RTL tenant tag. The bounded executable tests are closed;
the tenant-tag waiver remains open for a production interface revision.
