"""Supabase JWT authentication service."""

import os

import jwt
from jwt import PyJWKClient


_jwks_client: PyJWKClient | None = None


def _get_jwks_client() -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        project_url = os.environ["SUPABASE_PROJECT_URL"]
        jwks_url = f"{project_url}/auth/v1/.well-known/jwks.json"
        _jwks_client = PyJWKClient(jwks_url, cache_keys=True)
    return _jwks_client


async def verify_token(token: str) -> dict:
    """Validate a Supabase JWT and return the decoded payload.

    Raises jwt.exceptions.PyJWTError on invalid/expired tokens.
    """
    secret = os.environ["SUPABASE_SECRET_KEY"]

    # Try HMAC verification first (Supabase default uses the JWT secret directly)
    try:
        payload = jwt.decode(
            token,
            secret,
            algorithms=["HS256"],
            audience="authenticated",
        )
        return payload
    except jwt.exceptions.InvalidSignatureError:
        pass

    # Fallback: JWKS-based RS256 verification
    jwks_client = _get_jwks_client()
    signing_key = jwks_client.get_signing_key_from_jwt(token)
    payload = jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        audience="authenticated",
    )
    return payload
