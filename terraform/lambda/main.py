import json
import logging
import os
import re
import urllib.request
import base64
import unicodedata
from urllib.error import HTTPError, URLError
from datetime import datetime, timezone
from urllib.parse import parse_qs, quote, urlparse

import boto3

s3 = boto3.client("s3")
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def _filename_from_token(url: str) -> str | None:
    parsed = urlparse(url)
    token = parse_qs(parsed.query).get("token", [None])[0]
    if not token:
        return None

    parts = token.split(".")
    if len(parts) < 2:
        return None

    payload = parts[1]
    padding = "=" * (-len(payload) % 4)
    try:
        decoded = base64.urlsafe_b64decode(payload + padding)
        claims = json.loads(decoded)
    except (ValueError, json.JSONDecodeError):
        return None

    nested_url = claims.get("URL") or claims.get("url")
    if not isinstance(nested_url, str):
        return None

    nested_parsed = urlparse(nested_url)
    return os.path.basename(nested_parsed.path) or None


def _object_key_from_url(url: str) -> str:
    parsed = urlparse(url)
    filename = os.path.basename(parsed.path) or "downloaded-file"
    if "." not in filename:
        token_filename = _filename_from_token(url)
        if token_filename:
            filename = token_filename
        else:
            filename = f"{filename}.bin"
    return _normalize_filename(filename)


def _slugify(value: str) -> str:
    value = value.strip().lower()
    value = unicodedata.normalize("NFKD", value)
    value = value.encode("ascii", "ignore").decode("ascii")
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-") or "unknown"


def _normalize_filename(filename: str) -> str:
    stem, ext = os.path.splitext(filename)
    stem = _slugify(stem)
    ext = ext.lower()
    return f"{stem}{ext}"


def _date_prefix(payload: dict) -> str:
    raw = payload.get("periodicidade")
    if raw:
        try:
            dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
            return dt.date().isoformat()
        except ValueError:
            pass
    return datetime.now(timezone.utc).date().isoformat()


def handler(event, context):
    bucket = os.environ.get("BUCKET_NAME")
    if not bucket:
        raise RuntimeError("BUCKET_NAME env var is required")

    for record in event.get("Records", []):
        body = record.get("body", "")
        logger.info("SQS message body: %s", body)
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = {"url": body}

        url = payload.get("url")
        if not url:
            raise ValueError("Message must include 'url' in JSON or raw body.")

        key = payload.get("key")
        if not key:
            date_prefix = _date_prefix(payload)
            macro = _slugify(payload.get("macroProcesso", "unknown"))
            filename = _object_key_from_url(url)
            key = f"{date_prefix}/{macro}/{filename}"
        safe_url = quote(url, safe=":/?&=%")
        if safe_url != url:
            logger.info("Encoded URL for download.")

        request = urllib.request.Request(
            safe_url,
            headers={"User-Agent": "webhook-downloader/1.0"},
        )
        try:
            with urllib.request.urlopen(request) as response:
                data = response.read()
        except HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            logger.error("Download failed: status=%s body=%s", exc.code, error_body)
            raise
        except URLError as exc:
            logger.error("Download failed: %s", exc)
            raise

        s3.put_object(Bucket=bucket, Key=key, Body=data)

    return {"statusCode": 200}
