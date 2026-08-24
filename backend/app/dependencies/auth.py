from collections.abc import Callable
from dataclasses import dataclass

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.services.security import validate_token

_bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class CurrentUser:
    id: int
    username: str
    role: str


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> CurrentUser:
    """Require a valid, unexpired ``Authorization: Bearer <token>`` header."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        _raise_unauthorized()

    try:
        claims = validate_token(credentials.credentials)
    except ValueError:
        _raise_unauthorized()

    return CurrentUser(id=claims.user_id, username=claims.username, role=claims.role)


def get_optional_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> CurrentUser | None:
    """Return the caller when a bearer token was supplied; reject invalid ones."""
    if credentials is None:
        return None
    return get_current_user(credentials)


def require_roles(*allowed_roles: str) -> Callable[..., CurrentUser]:
    """Return a dependency that authorizes one of the supplied roles."""
    def role_dependency(current_user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if current_user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have permission to perform this action.",
            )
        return current_user

    return role_dependency


def _raise_unauthorized() -> None:
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="A valid, unexpired bearer token is required.",
        headers={"WWW-Authenticate": "Bearer"},
    )
