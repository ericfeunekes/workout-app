import concurrent.futures

import pytest


class Counter:
    def __init__(self):
        self.value = 0

    def upsert(self):
        # placeholder for idempotent operation under concurrency
        self.value = 1


@pytest.mark.component
def test_concurrent_upserts_idempotent():
    c = Counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        list(ex.map(lambda _: c.upsert(), range(100)))
    assert c.value == 1
