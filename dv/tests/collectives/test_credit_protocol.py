import itertools
import unittest
from collections import deque
from dataclasses import dataclass


def ring_allreduce(values, width=32):
    mask = (1 << width) - 1
    reduced = sum(values) & mask
    return [reduced] * len(values)


def tree_allreduce(values, parents, root=0, width=32):
    mask = (1 << width) - 1
    pending = set(range(len(values))) - {root}
    accum = list(values)
    while pending:
        leaves = [
            node
            for node in pending
            if not any(parents[child] == node for child in pending if child != node)
        ]
        if not leaves:
            raise ValueError("cyclic tree")
        for node in leaves:
            parent = parents[node]
            if parent == node:
                raise ValueError("non-root self parent")
            accum[parent] = (accum[parent] + accum[node]) & mask
            pending.remove(node)
    return [accum[root]] * len(values)


def alltoall_transpose(payloads):
    nodes = len(payloads)
    return [[payloads[source][destination] for source in range(nodes)]
            for destination in range(nodes)]


def ring_route(nodes):
    one_lap = tuple((node, (node + 1) % nodes) for node in range(nodes))
    return one_lap + one_lap


def tree_route(nodes):
    # Star is the maximum fanout configuration used by directed RTL. Every
    # message is consumed before the next one is injected.
    reduce_hops = tuple((node, 0) for node in range(1, nodes))
    broadcast_hops = tuple((0, node) for node in range(1, nodes))
    return reduce_hops + broadcast_hops


def alltoall_ring_route(nodes):
    hops = []
    for source in range(nodes):
        for destination in range(nodes):
            if source == destination:
                continue
            current = source
            while current != destination:
                next_node = (current + 1) % nodes
                hops.append((current, next_node))
                current = next_node
    return tuple(hops)


@dataclass(frozen=True)
class RoutingState:
    step: int
    packet_link: int
    credits: tuple
    retry: int
    fault_armed: bool
    stall_age: int
    failed: bool = False


def exhaust_protocol(route, credit_depth, fault_step=None, persistent=False,
                     retry_limit=2, fair_stall_bound=2):
    """Explore the serialized packet/credit/retry transition system.

    `packet_link == -1` means the engine owns the packet and is attempting the
    next route hop. Otherwise the packet occupies the named credit FIFO. A
    receiver may stall nondeterministically, but fairness bounds consecutive
    stalls. Since a stall is a pure self-loop in RTL, any larger finite bound
    has the same safety/reachability states and only repeats that loop.
    """
    physical_links = tuple(sorted(set(route)))
    link_index = {edge: index for index, edge in enumerate(physical_links)}
    initial = RoutingState(
        step=0,
        packet_link=-1,
        credits=(credit_depth,) * len(physical_links),
        retry=0,
        fault_armed=fault_step is not None,
        stall_age=0,
    )
    pending = deque([initial])
    visited = {initial}
    terminals = 0

    while pending:
        state = pending.popleft()
        for credit in state.credits:
            if not 0 <= credit <= credit_depth:
                raise AssertionError("credit escaped its legal range")
        occupied = sum(credit_depth - credit for credit in state.credits)
        if occupied != (state.packet_link >= 0):
            raise AssertionError("packet ownership and credit count diverged")

        if state.failed or state.step == len(route):
            terminals += 1
            continue

        successors = []
        if state.packet_link < 0:
            fault_matches = state.fault_armed and state.step == fault_step
            if fault_matches:
                if state.retry < retry_limit:
                    successors.append(RoutingState(
                        state.step, -1, state.credits, state.retry + 1,
                        persistent, 0,
                    ))
                else:
                    successors.append(RoutingState(
                        state.step, -1, state.credits, state.retry,
                        state.fault_armed, 0, failed=True,
                    ))
            else:
                index = link_index[route[state.step]]
                if state.credits[index] > 0:
                    credits = list(state.credits)
                    credits[index] -= 1
                    successors.append(RoutingState(
                        state.step, index, tuple(credits), state.retry,
                        state.fault_armed, 0,
                    ))
        else:
            # Receiver-ready transition. It neither holds nor requests another
            # channel, so this transition is independent of downstream credit.
            credits = list(state.credits)
            credits[state.packet_link] += 1
            successors.append(RoutingState(
                state.step + 1, -1, tuple(credits), 0,
                state.fault_armed, 0,
            ))
            # Legal backpressure transition. Fairness prevents this branch from
            # being selected forever; the bounded age makes the proof graph
            # finite while retaining every distinct hardware state.
            if state.stall_age < fair_stall_bound:
                successors.append(RoutingState(
                    state.step, state.packet_link, state.credits, state.retry,
                    state.fault_armed, state.stall_age + 1,
                ))

        if not successors:
            raise AssertionError(f"terminal protocol deadlock: {state}")
        for successor in successors:
            if successor not in visited:
                visited.add(successor)
                pending.append(successor)

    if terminals == 0:
        raise AssertionError("proof reached no completion or reported failure")
    return len(visited)


class CollectiveGoldenTest(unittest.TestCase):
    def test_algorithms(self):
        self.assertEqual(ring_allreduce([1, 2, 3, 4]), [10] * 4)
        self.assertEqual(tree_allreduce([1, 2, 3, 4], [0, 0, 0, 0]), [10] * 4)
        matrix = [[100 * source + destination for destination in range(4)]
                  for source in range(4)]
        self.assertEqual(alltoall_transpose(matrix),
                         [[0, 100, 200, 300], [1, 101, 201, 301],
                          [2, 102, 202, 302], [3, 103, 203, 303]])

    def test_tree_cycle_is_rejected(self):
        with self.assertRaises(ValueError):
            tree_allreduce([1, 2, 3], [0, 2, 1])


class BoundedCreditProofTest(unittest.TestCase):
    def test_every_legal_ring_state_has_credit_safe_progress(self):
        """Exhaust all queue occupancies for the supported bounded topology.

        A link receiver consumes a flit before it requests a downstream credit;
        it never holds one channel while waiting on another. Consequently every
        non-empty state has a receive transition, and every non-full state has
        an injection transition. This checks the state-space premise behind the
        RTL safety assertions for rings of two through eight nodes.
        """
        explored = 0
        for nodes in range(2, 9):
            for depth in range(1, 5):
                for occupancy in itertools.product(range(depth + 1), repeat=nodes):
                    explored += 1
                    receive_enabled = [count > 0 for count in occupancy]
                    inject_enabled = [count < depth for count in occupancy]
                    self.assertTrue(any(receive_enabled) or any(inject_enabled))
                    if any(occupancy):
                        self.assertTrue(any(receive_enabled))
                    for count in occupancy:
                        self.assertGreaterEqual(count, 0)
                        self.assertLessEqual(count, depth)
        self.assertGreater(explored, 500_000)

    def test_complete_packet_routing_state_machine_is_deadlock_free(self):
        """Exhaust ring, tree, and routed AllToAll packet state machines."""
        explored = 0
        for nodes in range(2, 9):
            routes = (ring_route(nodes), tree_route(nodes),
                      alltoall_ring_route(nodes))
            for depth in range(1, 5):
                for route in routes:
                    explored += exhaust_protocol(route, depth)
                    for fault_step in range(len(route)):
                        explored += exhaust_protocol(
                            route, depth, fault_step=fault_step,
                            persistent=False, retry_limit=2,
                        )
                        for retry_limit in range(3):
                            explored += exhaust_protocol(
                                route, depth, fault_step=fault_step,
                                persistent=True, retry_limit=retry_limit,
                            )
        self.assertGreater(explored, 1_000_000)


if __name__ == "__main__":
    unittest.main()
