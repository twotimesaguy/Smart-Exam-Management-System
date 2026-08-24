import base64
import binascii
import hashlib
import hmac
import json
import os
import secrets
import time
from dataclasses import dataclass


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 120_000)
    return f"{salt}${digest.hex()}"


def verify_password(password: str, password_hash: str) -> bool:
    salt, expected_digest = password_hash.split("$", 1)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 120_000)
    return hmac.compare_digest(digest.hex(), expected_digest)


TOKEN_TTL_SECONDS = int(os.getenv("AUTH_TOKEN_TTL_SECONDS", "28800"))

# A randomly generated fallback keeps local development usable without putting a
# predictable secret in source control. Set AUTH_TOKEN_SECRET in every deployed
# environment so tokens remain valid across process restarts and instances.
_token_secret = os.getenv("AUTH_TOKEN_SECRET") or secrets.token_urlsafe(48)


@dataclass(frozen=True)
class TokenClaims:
    user_id: int
    username: str
    role: str
    expires_at: int


def issue_token(*, user_id: int, username: str, role: str) -> str:
    """Create an HMAC-signed, expiring bearer token for one authenticated user."""
    now = int(time.time())
    payload = {
        "sub": user_id,
        "username": username,
        "role": role,
        "iat": now,
        "exp": now + TOKEN_TTL_SECONDS,
    }
    encoded_payload = _urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    )
    signature = hmac.new(
        _token_secret.encode("utf-8"), encoded_payload.encode("ascii"), hashlib.sha256
    ).digest()
    return f"v1.{encoded_payload}.{_urlsafe_b64encode(signature)}"


def validate_token(token: str) -> TokenClaims:
    """Validate signature and expiry, returning only well-formed token claims."""
    try:
        version, encoded_payload, encoded_signature = token.split(".")
        if version != "v1":
            raise ValueError("unsupported token version")
        expected_signature = hmac.new(
            _token_secret.encode("utf-8"),
            encoded_payload.encode("ascii"),
            hashlib.sha256,
        ).digest()
        provided_signature = _urlsafe_b64decode(encoded_signature)
        if not hmac.compare_digest(provided_signature, expected_signature):
            raise ValueError("invalid token signature")

        payload = json.loads(_urlsafe_b64decode(encoded_payload))
        user_id = payload["sub"]
        username = payload["username"]
        role = payload["role"]
        expires_at = payload["exp"]
        if (
            not isinstance(user_id, int)
            or not isinstance(username, str)
            or not username.strip()
            or role not in {"admin", "invigilator", "disciplinary_officer"}
            or not isinstance(expires_at, int)
            or expires_at <= int(time.time())
        ):
            raise ValueError("invalid or expired token")
    except (
        KeyError,
        TypeError,
        ValueError,
        UnicodeDecodeError,
        json.JSONDecodeError,
        binascii.Error,
    ) as error:
        raise ValueError("invalid or expired token") from error

    return TokenClaims(
        user_id=user_id,
        username=username,
        role=role,
        expires_at=expires_at,
    )


def _urlsafe_b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _urlsafe_b64decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
