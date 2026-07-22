import random
import unittest

from dv.golden.tensor_ref import (
    decode_packed_weights,
    integer_rms_norm,
    quantized_gemv,
    round_q8_8,
)


def pack(values: list[int], bits: int) -> int:
    result = 0
    mask = (1 << bits) - 1
    for lane, value in enumerate(values):
        result |= (value & mask) << (lane * bits)
    return result


class TensorFormatTest(unittest.TestCase):
    def test_int4_sign_extension_and_zero_point(self) -> None:
        packed = pack([-8, -1, 0, 7], 4)
        self.assertEqual(decode_packed_weights(packed, "int4", -1), [-7, 0, 1, 8])

    def test_q8_8_rounding_ties_away_from_zero(self) -> None:
        self.assertEqual(round_q8_8(128), 1)
        self.assertEqual(round_q8_8(-128), -1)
        self.assertEqual(round_q8_8(-256), -1)

    def test_saturation_and_relu(self) -> None:
        row = pack([127, 127, 127, 127], 8)
        output, saturated = quantized_gemv(
            [127] * 4, [row], ["int8"], [0], [32767], [0], activation_mode="relu"
        )
        self.assertEqual(output, [32767])
        self.assertEqual(saturated, [True])

    def test_integer_rms_norm(self) -> None:
        output, saturated = integer_rms_norm([3, 4, 0, 0], [256] * 4)
        self.assertEqual(output, [384, 512, 0, 0])
        self.assertEqual(saturated, [False] * 4)

    def test_seeded_random_formats_are_deterministic(self) -> None:
        rng = random.Random(0x5EED)
        for _ in range(250):
            activation = [rng.randint(-128, 127) for _ in range(4)]
            formats = [rng.choice(["int8", "int4"]) for _ in range(4)]
            rows = []
            for fmt in formats:
                limit = 128 if fmt == "int8" else 8
                rows.append(pack([rng.randrange(-limit, limit) for _ in range(4)], 8 if fmt == "int8" else 4))
            outputs, _ = quantized_gemv(
                activation,
                rows,
                formats,
                [rng.randint(-4, 4) for _ in range(4)],
                [rng.randint(-512, 512) for _ in range(4)],
                [rng.randint(-1000, 1000) for _ in range(4)],
                activation_mode=rng.choice(["bypass", "relu", "clamp_int8"]),
            )
            self.assertTrue(all(-32768 <= item <= 32767 for item in outputs))


if __name__ == "__main__":
    unittest.main()
