import httpx
import pytest
import respx


@pytest.mark.behavior
def test_http_client_timeout_with_respx():
    """Use respx when you need a forced failure mode (hard to record reliably)."""

    with respx.mock(assert_all_called=True) as router:
        router.get("https://example.com/health").mock(side_effect=httpx.TimeoutException("timeout"))

        with pytest.raises(httpx.TimeoutException):
            httpx.get("https://example.com/health", timeout=0.01)
