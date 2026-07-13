import os
import json
import bcrypt
import jwt
from datetime import datetime, timedelta, timezone
import boto3

_secrets_client = None
_cached_jwt_secret = None


def get_jwt_secret() -> str:
    global _cached_jwt_secret
    if _cached_jwt_secret:
        return _cached_jwt_secret

    secret_arn = os.environ["JWT_SECRET_ARN"]
    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=secret_arn)
    data = json.loads(response["SecretString"])
    _cached_jwt_secret = data["jwt_secret"]
    return _cached_jwt_secret


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))


def create_access_token(user_id: str, email: str, role: str) -> str:
    expire_hours = int(os.environ.get("JWT_EXPIRATION_HOURS", "24"))
    payload = {
        "sub": user_id,
        "email": email,
        "role": role,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(hours=expire_hours),
    }
    return jwt.encode(payload, get_jwt_secret(), algorithm="HS256")


def decode_token(token: str) -> dict:
    return jwt.decode(token, get_jwt_secret(), algorithms=["HS256"])