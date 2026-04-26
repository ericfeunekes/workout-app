import pytest
from hypothesis import given
from hypothesis import strategies as st


def cents(xs: list[int]) -> list[int]:
    return [x * 100 for x in xs]


@pytest.mark.property
@given(st.lists(st.integers(min_value=0, max_value=10_000)))
def test_cents_is_linear_and_nonnegative(xs):
    ys = cents(xs)
    assert sum(ys) == 100 * sum(xs)
    assert all(y >= 0 for y in ys)
