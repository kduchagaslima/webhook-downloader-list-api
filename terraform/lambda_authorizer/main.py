import json
import logging

import boto3

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

cognito = boto3.client("cognito-idp")


def _extract_token(raw_header: str | None) -> str | None:
    if not raw_header:
        return None
    parts = raw_header.split()
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1]
    return raw_header


def _policy(principal_id: str, effect: str, resource: str, context: dict | None = None):
    policy = {
        "principalId": principal_id,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [{"Action": "execute-api:Invoke", "Effect": effect, "Resource": resource}],
        },
    }
    if context:
        policy["context"] = context
    return policy


def handler(event, context):
    token = _extract_token(event.get("authorizationToken"))
    method_arn = event.get("methodArn")

    if not token or not method_arn:
        return _policy("unauthorized", "Deny", method_arn or "*")

    try:
        response = cognito.get_user(AccessToken=token)
    except cognito.exceptions.NotAuthorizedException:
        logger.warning("Invalid access token")
        return _policy("unauthorized", "Deny", method_arn)
    except Exception as exc:
        logger.exception("Authorization error: %s", exc)
        return _policy("unauthorized", "Deny", method_arn)

    username = response.get("Username", "user")
    context = {"username": username}
    return _policy(username, "Allow", method_arn, context)
