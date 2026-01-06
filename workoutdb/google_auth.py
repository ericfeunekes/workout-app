from __future__ import annotations

import os
import stat
import sys
from pathlib import Path
from typing import List

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow


def get_credentials(
    client_secret_path: Path,
    token_path: Path,
    scopes: List[str],
) -> Credentials:
    required_scopes = list(dict.fromkeys(scopes or []))
    creds = None
    existing_scopes: list[str] = []
    if token_path.exists():
        creds = Credentials.from_authorized_user_file(token_path)
        existing_scopes = list(creds.scopes or [])

    combined_scopes = list(dict.fromkeys([*existing_scopes, *required_scopes]))
    missing_scopes = sorted(set(required_scopes) - set(existing_scopes))

    if not creds or not creds.valid or missing_scopes:
        if creds and creds.expired and creds.refresh_token and not missing_scopes:
            try:
                creds.refresh(Request())
            except Exception as exc:  # noqa: BLE001
                raise RuntimeError(
                    "Google auth refresh failed. Delete the token and re-auth using "
                    "WORKOUT_APP_AUTH_MODE=console|browser."
                ) from exc
        else:
            auth_mode = os.getenv("WORKOUT_APP_AUTH_MODE", "").lower()
            if auth_mode == "":
                auth_mode = "console" if sys.stdin.isatty() else "noninteractive"
            if auth_mode == "noninteractive":
                raise RuntimeError(
                    "Google auth required. Run `workoutdb auth google` or set "
                    "WORKOUT_APP_AUTH_MODE=console|browser."
                )
            flow = InstalledAppFlow.from_client_secrets_file(
                client_secret_path, combined_scopes or required_scopes
            )
            if auth_mode == "console":
                if not flow.redirect_uri:
                    flow.redirect_uri = "http://localhost"
                auth_url, _ = flow.authorization_url(prompt="consent", access_type="offline")
                print(f"Please visit this URL to authorize this application: {auth_url}")
                code = input("Enter the authorization code: ").strip()
                flow.fetch_token(code=code)
                creds = flow.credentials
            elif auth_mode == "browser":
                creds = flow.run_local_server(port=0, open_browser=False)
            else:
                raise RuntimeError(
                    f"Unknown WORKOUT_APP_AUTH_MODE={auth_mode!r}. "
                    "Use console, browser, or noninteractive."
                )
        if not creds or not creds.valid:
            raise RuntimeError("Google auth failed; no valid credentials available.")
        token_path.parent.mkdir(parents=True, exist_ok=True)
        token_path.write_text(creds.to_json())
        try:
            token_path.parent.chmod(stat.S_IRWXU)
            token_path.chmod(stat.S_IRUSR | stat.S_IWUSR)
        except OSError:
            pass
    return creds
