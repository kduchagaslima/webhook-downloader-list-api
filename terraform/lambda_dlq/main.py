import base64
import json
import logging
import os
import re
import unicodedata
import urllib.request
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, urlparse

import boto3

s3 = boto3.client("s3")
sqs = boto3.client("sqs")
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


def _object_key_from_url(url: str, message_id: str | None = None) -> str:
    parsed = urlparse(url)
    filename = os.path.basename(parsed.path) or "downloaded-file"
    if "." not in filename:
        token_filename = _filename_from_token(url)
        if token_filename:
            filename = token_filename
        else:
            filename = f"{filename}.bin"
    if message_id:
        stem, ext = os.path.splitext(filename)
        if ext:
            filename = f"{stem}-{message_id}{ext}"
        else:
            filename = f"{filename}-{message_id}"
    return filename


def _slugify(value: str) -> str:
    value = value.strip().lower()
    value = unicodedata.normalize("NFKD", value)
    value = value.encode("ascii", "ignore").decode("ascii")
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-") or "unknown"


def _date_prefix(payload: dict) -> str:
    raw = payload.get("periodicidade")
    if raw:
        try:
            dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
            return dt.date().isoformat()
        except ValueError:
            pass
    return datetime.now(timezone.utc).date().isoformat()


def _process_payload(payload: dict, message_id: str | None, bucket: str) -> None:
    url = payload.get("url")
    if not url:
        raise ValueError("Message must include 'url' in JSON or raw body.")

    key = payload.get("key")
    if not key:
        date_prefix = _date_prefix(payload)
        macro = _slugify(payload.get("macroProcesso", "unknown"))
        filename = _object_key_from_url(url, message_id)
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


def _parse_body(body: str) -> dict:
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return {"url": body}


def handler(event, context):
    bucket = os.environ.get("BUCKET_NAME")
    if not bucket:
        raise RuntimeError("BUCKET_NAME env var is required")

    dlq_url = os.environ.get("DLQ_URL")
    if not dlq_url:
        raise RuntimeError("DLQ_URL env var is required")

    max_messages = int(event.get("max_messages", 10))
    if max_messages < 1:
        max_messages = 1
    if max_messages > 10:
        max_messages = 10

    wait_seconds = int(event.get("wait_seconds", 0))
    if wait_seconds < 0:
        wait_seconds = 0
    if wait_seconds > 20:
        wait_seconds = 20

    response = sqs.receive_message(
        QueueUrl=dlq_url,
        MaxNumberOfMessages=max_messages,
        WaitTimeSeconds=wait_seconds,
    )

    messages = response.get("Messages", [])
    if not messages:
        logger.info("No messages available in DLQ.")
        return {"processed": 0, "errors": 0}

    processed = 0
    errors = 0
    for message in messages:
        body = message.get("Body", "")
        message_id = message.get("MessageId")
        receipt_handle = message.get("ReceiptHandle")
        logger.info("Processing DLQ message: %s", message_id)

        try:
            payload = _parse_body(body)
            _process_payload(payload, message_id, bucket)
        except Exception:
            logger.exception("Failed to process DLQ message: %s", message_id)
            errors += 1
            continue

        if receipt_handle:
            sqs.delete_message(QueueUrl=dlq_url, ReceiptHandle=receipt_handle)
        processed += 1

    return {"processed": processed, "errors": errors}
