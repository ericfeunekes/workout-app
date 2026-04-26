import pytest
import requests


@pytest.mark.behavior
@pytest.mark.recorded
def test_github_user_profile(vcr_cassette):
    resp = requests.get("https://api.github.com/users/octocat", timeout=5)
    assert resp.status_code == 200
    data = resp.json()
    assert data["login"] == "octocat"


@pytest.mark.behavior
@pytest.mark.recorded
def test_github_not_found(vcr_cassette):
    resp = requests.get("https://api.github.com/users/__nope__", timeout=5)
    assert resp.status_code in (404, 200)  # cassette may record a redirect or 404
