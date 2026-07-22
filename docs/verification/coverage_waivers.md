# Phase 9 Coverage Waivers and Signoff Gates

No functional cross-coverage bin is waived in the bounded implementation.

| ID | Exclusion or gate | Reason | Closure condition |
| --- | --- | --- | --- |
| COV-001 | Uninstantiated optional tensor/collective logic in top-level line coverage | Phase 2 top still uses the scheduler stub integration path | Integrate production token scheduler and collective ports, then reapply the 90% line gate to the expanded denominator |
| SEC-001 | Tenant isolation is model-checked, not an RTL-port assertion | Current KV command has no tenant/ASID field | Add ASID to descriptor, TLB and walker and bind the assertion to RTL |
| SEC-002 | Collective partition containment is model-checked | Current bounded header has no partition tag | Add authenticated partition id and topology enforcement in RTL |
| GLS-001 | SDF gate simulation, X-prop and scan reset | No synthesized netlist or cell/memory timing library is present | Run reset and critical-flow suite on the released netlist and libraries |
| CDC-001 | Production CDC/RDC report | Bounded top has one clock and one reset domain | Run structural CDC/RDC after PHY, control CPU and memory clocks are integrated |

These are not tapeout waivers. They are open gates that prevent a claim of
physical tapeout signoff while allowing the repository's bounded Phase 9
verification implementation to remain reproducible.
