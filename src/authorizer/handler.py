import os
import json
import jwt
import boto3

_cached_secret = None


def get_jwt_secret() -> str:
    global _cached_secret
    if _cached_secret:
        return _cached_secret

    secret_arn = os.environ["JWT_SECRET_ARN"]
    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=secret_arn)
    data = json.loads(response["SecretString"])
    _cached_secret = data["jwt_secret"]
    return _cached_secret


def generate_policy(principal_id: str, effect: str, method_arn: str, context: dict | None = None):
    """
    method_arn ejemplo:
    arn:aws:execute-api:us-east-1:123:abc/dev/GET/users/me

    Resource permitido: todo el stage
    arn:aws:execute-api:us-east-1:123:abc/dev/*
    """
    # arn:aws:execute-api:region:account:apiId/stage/METHOD/path...
    parts = method_arn.split(":")
    # parts[5] = "apiId/stage/METHOD/..."
    gateway_parts = parts[5].split("/")
    api_id = gateway_parts[0]
    stage = gateway_parts[1] if len(gateway_parts) > 1 else "*"
    resource = f"{parts[0]}:{parts[1]}:{parts[2]}:{parts[3]}:{parts[4]}:{api_id}/{stage}/*"

    policy = {
        "principalId": principal_id,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": effect,
                    "Resource": resource,
                }
            ],
        },
    }
    if context:
        policy["context"] = {k: str(v) for k, v in context.items() if v is not None}
    return policy


def handler(event, context):
    try:
        token = event.get("authorizationToken", "")
        if token.lower().startswith("bearer "):
            token = token[7:].strip()

        if not token:
            raise Exception("Unauthorized")

        payload = jwt.decode(token, get_jwt_secret(), algorithms=["HS256"])
        user_id = payload.get("sub")
        role = payload.get("role")
        email = payload.get("email")

        if not user_id or not role:
            raise Exception("Unauthorized")

        return generate_policy(
            principal_id=user_id,
            effect="Allow",
            method_arn=event["methodArn"],
            context={
                "userId": user_id,
                "role": role,
                "email": email or "",
            },
        )
    except Exception as e:
        print(f"Authorizer deny/unauthorized: {e}")
        raise Exception("Unauthorized")