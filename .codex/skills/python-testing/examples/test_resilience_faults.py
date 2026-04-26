import pytest


class FaultPlan:
    def __init__(self, fail_n_times=None):
        self._n = dict(fail_n_times or {})

    def maybe(self, name):
        n = self._n.get(name, 0)
        if n > 0:
            self._n[name] = n - 1
            raise TimeoutError(name)


class RealClient:
    def get(self, url):
        return "OK"


class FaultyClient:
    def __init__(self, inner, plan):
        self.inner, self.plan = inner, plan

    def get(self, url):
        self.plan.maybe("get")
        return self.inner.get(url)


def fetch_with_retries(client, url, retries=3):
    for _ in range(retries + 1):
        try:
            return client.get(url)
        except TimeoutError:
            pass
    raise TimeoutError("exhausted")


@pytest.mark.component
@pytest.mark.p0
def test_retries_then_succeeds():
    plan = FaultPlan(fail_n_times={"get": 2})
    client = FaultyClient(RealClient(), plan)
    assert fetch_with_retries(client, "http://x") == "OK"
