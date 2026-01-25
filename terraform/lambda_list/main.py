import json
import logging
import os
import time

import base64

import boto3

s3 = boto3.client("s3")
ssm = boto3.client("ssm")
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

_PRIVATE_KEY_PEM = None


def _load_private_key_pem() -> str:
    global _PRIVATE_KEY_PEM
    if _PRIVATE_KEY_PEM:
        return _PRIVATE_KEY_PEM
    param_name = os.environ["CF_PRIVATE_KEY_PARAM"]
    response = ssm.get_parameter(Name=param_name, WithDecryption=True)
    _PRIVATE_KEY_PEM = response["Parameter"]["Value"]
    return _PRIVATE_KEY_PEM


def _rsa_signer(message: bytes) -> bytes:
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding
    except ImportError as exc:
        raise RuntimeError(
            "cryptography package is required to sign CloudFront cookies"
        ) from exc

    private_key = serialization.load_pem_private_key(
        _load_private_key_pem().encode("utf-8"),
        password=None,
    )
    return private_key.sign(message, padding.PKCS1v15(), hashes.SHA1())


def _build_prefix(product: str, date_value: str | None) -> str:
    template = os.environ.get("S3_PREFIX_TEMPLATE", "{product}/{date}")
    safe_date = date_value or ""
    formatted = template.format(product=product, date=safe_date).strip("/")
    if not formatted:
        return ""
    return f"{formatted}/"


def _list_objects(bucket: str, prefix: str) -> list[str]:
    paginator = s3.get_paginator("list_objects_v2")
    keys = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            keys.append(obj["Key"])
    return keys


def _build_cookies(domain: str, prefix: str, ttl_seconds: int) -> dict[str, str]:
    key_pair_id = os.environ["CF_KEY_PAIR_ID"]
    expires = int(time.time()) + ttl_seconds
    resource = f"https://{domain}/{prefix}*"
    policy = json.dumps(
        {
            "Statement": [
                {
                    "Resource": resource,
                    "Condition": {"DateLessThan": {"AWS:EpochTime": expires}},
                }
            ]
        }
    )
    policy_bytes = policy.encode("utf-8")
    signature = _rsa_signer(policy_bytes)
    return {
        "CloudFront-Policy": _url_safe_b64(policy_bytes),
        "CloudFront-Signature": _url_safe_b64(signature),
        "CloudFront-Key-Pair-Id": key_pair_id,
    }


def _url_safe_b64(value: bytes) -> str:
    encoded = base64.b64encode(value).decode("utf-8")
    return encoded.replace("+", "-").replace("=", "_").replace("/", "~")


def _extract_product(event: dict) -> str | None:
    path_params = event.get("pathParameters") or {}
    query_params = event.get("queryStringParameters") or {}
    return path_params.get("tipo") or query_params.get("tipo")


def handler(event, context):
    bucket = os.environ["BUCKET_NAME"]
    domain = os.environ["CF_DOMAIN"]
    ttl_seconds = int(os.environ.get("COOKIE_TTL_SECONDS", "900"))

    product = _extract_product(event)
    if not product:
        return {"statusCode": 400, "body": json.dumps({"error": "Missing tipo"})}

    query_params = event.get("queryStringParameters") or {}
    date_value = query_params.get("data")
    prefix = _build_prefix(product, date_value)

    keys = _list_objects(bucket, prefix)
    cookies = _build_cookies(domain, prefix, ttl_seconds)
    cookie_headers = [
        f"{name}={value}; Path=/; Secure; HttpOnly"
        for name, value in cookies.items()
    ]

    response_body = {
        "cloudfront_url": f"https://{domain}/",
        "prefix": prefix,
        "files": [{"key": key, "url": f"https://{domain}/{key}"} for key in keys],
        "cookies": cookies,
    }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "multiValueHeaders": {"Set-Cookie": cookie_headers},
        "body": json.dumps(response_body),
    }
