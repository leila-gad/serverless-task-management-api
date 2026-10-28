import json
import os
import uuid
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError


try:  # pragma: no cover
    from aws_xray_sdk.core import patch_all

    patch_all()
except Exception:  # pragma: no cover
    pass

VALID_STATUS = {"open", "done"}
MAX_TITLE_LEN = 200
CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
}


def _table():
    return boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def _response(code, body=None):
    return {
        "statusCode": code,
        "headers": CORS_HEADERS,
        "body": "" if body is None else json.dumps(body, default=str),
    }


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _user_id(event):
    claims = ((event.get("requestContext") or {}).get("authorizer") or {}).get("claims") or {}
    return claims.get("sub")


def _parse_body(event):
    raw = event.get("body")
    if not raw:
        return {}
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("JSON body must be an object")
    return data


def _validate_title(title):
    if not isinstance(title, str) or not title.strip():
        raise ValueError("'title' is required and must be a non-empty string")
    if len(title) > MAX_TITLE_LEN:
        raise ValueError(f"'title' must be at most {MAX_TITLE_LEN} characters")
    return title.strip()


def _validate_status(status):
    if status not in VALID_STATUS:
        raise ValueError("'status' must be one of: " + ", ".join(sorted(VALID_STATUS)))
    return status


def create_todo(user, body):
    item = {
        "userId": user,
        "todoId": str(uuid.uuid4()),
        "title": _validate_title(body.get("title")),
        "status": _validate_status(body.get("status", "open")),
        "createdAt": _now(),
        "updatedAt": _now(),
    }
    _table().put_item(Item=item)
    return _response(201, item)


def list_todos(user, params):
    status = (params or {}).get("status")
    if status:
        result = _table().query(
            IndexName="StatusIndex",
            KeyConditionExpression=Key("userId").eq(user) & Key("status").eq(_validate_status(status)),
        )
    else:
        result = _table().query(KeyConditionExpression=Key("userId").eq(user))
    return _response(200, result["Items"])


def get_todo(user, todo_id):
    result = _table().get_item(Key={"userId": user, "todoId": todo_id})
    if "Item" not in result:
        return _response(404, {"error": "Task not found"})
    return _response(200, result["Item"])


def update_todo(user, todo_id, body):
    names, values, sets = {}, {":u": _now()}, ["updatedAt = :u"]
    if "title" in body:
        names["#t"] = "title"
        values[":t"] = _validate_title(body["title"])
        sets.append("#t = :t")
    if "status" in body:
        names["#s"] = "status"
        values[":s"] = _validate_status(body["status"])
        sets.append("#s = :s")
    if len(sets) == 1:
        raise ValueError("Provide at least one of: title, status")
    kwargs = {
        "Key": {"userId": user, "todoId": todo_id},
        "UpdateExpression": "SET " + ", ".join(sets),
        "ConditionExpression": "attribute_exists(todoId)",
        "ExpressionAttributeValues": values,
        "ReturnValues": "ALL_NEW",
    }
    if names:
        kwargs["ExpressionAttributeNames"] = names
    result = _table().update_item(**kwargs)
    return _response(200, result["Attributes"])


def delete_todo(user, todo_id):
    _table().delete_item(
        Key={"userId": user, "todoId": todo_id},
        ConditionExpression="attribute_exists(todoId)",
    )
    return _response(204)


def lambda_handler(event, context):
    user = _user_id(event)
    if not user:
        return _response(401, {"error": "Unauthorized"})

    method = event.get("httpMethod")
    todo_id = (event.get("pathParameters") or {}).get("id")
    params = event.get("queryStringParameters")

    try:
        if method == "POST" and not todo_id:
            return create_todo(user, _parse_body(event))
        if method == "GET" and not todo_id:
            return list_todos(user, params)
        if method == "GET" and todo_id:
            return get_todo(user, todo_id)
        if method == "PUT" and todo_id:
            return update_todo(user, todo_id, _parse_body(event))
        if method == "DELETE" and todo_id:
            return delete_todo(user, todo_id)
        return _response(405, {"error": "Method not allowed"})
    except (ValueError, json.JSONDecodeError) as exc:
        return _response(400, {"error": str(exc)})
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return _response(404, {"error": "Task not found"})
        print(f"DynamoDB error: {exc}")
        return _response(500, {"error": "Internal server error"})
