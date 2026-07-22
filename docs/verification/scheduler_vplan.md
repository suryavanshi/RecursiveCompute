# Token Scheduler Verification Plan

## Maximum-Priority Latency Contract

The bounded Phase 6 scheduler guarantees that an accepted priority-3 request
retires internally within `QOS_MAX_LATENCY_CYCLES`, provided reset is not
asserted and the configured engines obey their bounded request protocols.
Completion-interface backpressure is outside this scheduling bound; the
completion FIFO decouples internal retirement from the host interface.

The default service bound for one graph is 6,400 cycles:

| Component | Conservative maximum |
| --- | ---: |
| One indirect DMA node | 774 cycles |
| Eight DMA-class nodes | 6,192 cycles |
| Eight full descriptor scans | 64 cycles |
| Scheduler load, issue, response, and retirement margin | 144 cycles |
| Total `MAX_GRAPH_CYCLES` | 6,400 cycles |

Indirect DMA is the longest bounded engine operation: up to 256 validation
cycles, 256 ECC-check cycles, 256 copy cycles, and six descriptor/response
handshake cycles. Attention is limited to 32 context tokens and tensor
execution to four rows, so both fall below the DMA allocation.

At most four requests can be pending while one graph is active. A newly
accepted maximum-priority request can therefore have one active graph and at
most three older equal-priority requests ahead of it. Including its own
service gives:

```text
QOS_MAX_LATENCY_CYCLES
  = (REQUEST_SLOTS + 1) * MAX_GRAPH_CYCLES
  = (4 + 1) * 6,400
  = 32,000 cycles
```

Lower-priority requests cannot have a finite unconditional bound because a
continuing stream of priority-3 work may bypass them. Equal-priority requests
are ordered by admission age.

## Runtime Monitors

`rcif_token_scheduler` exposes:

- `qos_bound_cycles_o`: the configured maximum-priority latency bound;
- `qos_last_request_id_o` and `qos_last_latency_o`: the most recently retired
  request and its admission-to-retirement latency;
- `qos_bound_violation_o`: a sticky violation if any graph exceeds its service
  allocation or a priority-3 request exceeds the queue-derived latency bound.

The latency counter saturates instead of wrapping. The monitor records
retirement on first entry to `FINISH`, so host completion backpressure cannot
create a false scheduler violation.

## Directed Bound Test

`dv/tests/token_step/rcif_token_scheduler_test.cpp` programs an active
low-priority graph containing seven maximum-length 256-page DMA copies, queues
a second graph at low priority, and then admits a priority-3 completion graph.
The test checks all of the following:

1. The active graph completes first because execution is non-preemptive.
2. The priority-3 graph completes second, ahead of the older queued low-priority graph.
3. External observed latency is no greater than `qos_bound_cycles_o` with the
   completion interface ready.
4. Internal admission-to-retirement latency is within the same bound.
5. The sticky service/latency violation monitor remains clear.

A second saturation case runs an active maximum-service priority-3 graph,
fills all four request slots with equal-priority maximum-service graphs, and
measures the newest request. It verifies admission-age ordering and the full
five-graph term used by the 32,000-cycle bound.

This closes the Phase 6 high-priority latency-bound exit criterion for the
bounded scheduler configuration. Formal liveness across future concurrent or
preemptive engine implementations remains a later verification task.

## Phase 9 closure additions

The full-chip monitor independently rejects issue with an unready dependency,
and `rcif_top_assertions` checks accepted/completed conservation across the
command queue. The randomized full-chip test varies reset and completion
backpressure while the directed saturation test remains the QoS proof witness.
Cross coverage includes priority with page size, precision, mask and fault.

The bounded scheduler is Phase 9 closed under the documented engine latency
and finite-backpressure assumptions. Preemptive/concurrent engines require a
new liveness proof when introduced; they are not silently covered by this plan.
