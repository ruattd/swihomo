#!/usr/bin/env python3

import base64
import datetime
import http.client
import json
import os
import re
import socket
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import parse_qsl, quote, urlencode, urlsplit, urlunsplit


API_BASE = "https://api.appstoreconnect.apple.com"
API_HOST = "api.appstoreconnect.apple.com"
JWT_AUDIENCE = "appstoreconnect-v1"
JWT_TTL_SECONDS = 19 * 60
HTTP_MAX_ATTEMPTS = 5
HTTP_MAX_RETRY_DELAY_SECONDS = 10
CONNECT_TIMEOUT_SECONDS = 15
READ_TIMEOUT_SECONDS = 30
COLLECTION_MAX_PAGES = 100
ASSIGN_TIMEOUT_SECONDS = 30 * 60
ASSIGN_POLL_INTERVAL_SECONDS = 20
REQUIRED_ENVIRONMENT = (
    "ASC_ISSUER_ID",
    "ASC_KEY_ID",
    "ASC_PRIVATE_KEY_PATH",
    "TESTFLIGHT_INTERNAL_GROUP_ID",
    "BUNDLE_ID",
    "MARKETING_VERSION",
    "IOS_BUILD_NUMBER",
    "MACOS_BUILD_NUMBER",
)
NEXT_BUILD_NUMBER_ENVIRONMENT = (
    "ASC_ISSUER_ID",
    "ASC_KEY_ID",
    "ASC_PRIVATE_KEY_PATH",
    "BUNDLE_ID",
)
PLATFORMS = ("IOS", "MAC_OS")
PROCESSING_STATES = ("PROCESSING", "VALID")
FAILED_STATES = ("FAILED", "INVALID")


class Failure(Exception):
    pass


class DerError(Exception):
    pass


def required_environment(names=REQUIRED_ENVIRONMENT):
    environment = {}
    for name in names:
        value = os.environ.get(name)
        if value is None or value == "":
            raise Failure(f"missing required environment variable {name}")
        environment[name] = value
    return environment


def base64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def read_der_length(data, offset, limit):
    if offset >= limit:
        raise DerError("missing DER length")

    first = data[offset]
    offset += 1
    if first & 0x80 == 0:
        length = first
    else:
        count = first & 0x7F
        if count == 0:
            raise DerError("indefinite DER length")
        if count > 4 or offset + count > limit:
            raise DerError("invalid DER length size")
        if data[offset] == 0:
            raise DerError("non-minimal DER length")
        length = int.from_bytes(data[offset:offset + count], "big")
        offset += count
        if length < 128:
            raise DerError("non-minimal DER long-form length")

    if length > limit - offset:
        raise DerError("DER length exceeds enclosing value")
    return length, offset


def read_der_integer(data, offset, limit):
    if offset >= limit or data[offset] != 0x02:
        raise DerError("expected DER INTEGER")

    length, value_start = read_der_length(data, offset + 1, limit)
    value_end = value_start + length
    value = data[value_start:value_end]
    if not value:
        raise DerError("empty DER INTEGER")
    if value[0] & 0x80:
        raise DerError("negative DER INTEGER")
    if len(value) > 1 and value[0] == 0 and value[1] & 0x80 == 0:
        raise DerError("non-minimal DER INTEGER")

    normalized = value[1:] if value[0] == 0 else value
    if len(normalized) > 32:
        raise DerError("DER INTEGER is wider than 32 bytes")
    integer = int.from_bytes(normalized, "big")
    if integer == 0:
        raise DerError("DER INTEGER is zero")
    return integer, value_end


def der_to_raw_signature(der_signature):
    data = bytes(der_signature)
    if not data or data[0] != 0x30:
        raise DerError("ECDSA signature is not a DER SEQUENCE")

    sequence_length, sequence_start = read_der_length(data, 1, len(data))
    sequence_end = sequence_start + sequence_length
    if sequence_end != len(data):
        raise DerError("DER signature has trailing data")

    r, offset = read_der_integer(data, sequence_start, sequence_end)
    s, offset = read_der_integer(data, offset, sequence_end)
    if offset != sequence_end:
        raise DerError("DER signature has extra values")
    if r >= 1 << 256 or s >= 1 << 256:
        raise DerError("ECDSA signature component is wider than 32 bytes")

    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    if len(raw) != 64:
        raise DerError("ECDSA signature is not 64 bytes")
    return raw


def build_jwt(issuer_id, key_id, private_key_path):
    if not os.path.isfile(private_key_path):
        raise Failure("ASC_PRIVATE_KEY_PATH does not point to a readable file")

    issued_at = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "aud": JWT_AUDIENCE,
        "iat": issued_at,
        "exp": issued_at + JWT_TTL_SECONDS,
    }
    encoded_header = base64url(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    encoded_payload = base64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{encoded_header}.{encoded_payload}"

    try:
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", private_key_path],
            input=signing_input.encode("ascii"),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        raise Failure("unable to use openssl to sign the App Store Connect JWT")
    if result.returncode != 0:
        raise Failure("ASC_PRIVATE_KEY_PATH does not contain a readable private key")

    try:
        encoded_signature = base64url(der_to_raw_signature(result.stdout))
    except DerError:
        raise Failure("App Store Connect JWT signing returned an invalid ECDSA signature")
    return f"{signing_input}.{encoded_signature}"


class TimeoutHTTPSConnection(http.client.HTTPSConnection):
    def connect(self):
        self.sock = socket.create_connection(
            (self.host, self.port),
            CONNECT_TIMEOUT_SECONDS,
            getattr(self, "source_address", None),
        )
        self.sock.settimeout(READ_TIMEOUT_SECONDS)
        tunnel_host = getattr(self, "_tunnel_host", None)
        if tunnel_host:
            getattr(self, "_tunnel")()
        server_hostname = tunnel_host or self.host
        context = getattr(self, "_context")
        self.sock = context.wrap_socket(self.sock, server_hostname=server_hostname)


class TimeoutHTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, req):
        return self.do_open(TimeoutHTTPSConnection, req, context=getattr(self, "_context"))


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class ApiClient:
    def __init__(self, token_provider):
        self._token_provider = token_provider
        self._opener = urllib.request.build_opener(
            NoRedirectHandler(),
            TimeoutHTTPSHandler(context=ssl.create_default_context())
        )

    def get(self, path, params=None):
        return self._request("GET", path, params=params or {})

    def post(self, path, body):
        return self._request("POST", path, body=body)

    def collection(self, path, params=None):
        items, _ = self.collection_with_included(path, params=params)
        return items

    def collection_with_included(self, path, params=None):
        response = self.get(path, params=params or {})
        items = self._resource_list(response, "data")
        included = self._resource_list(response, "included")
        next_url = (response.get("links") or {}).get("next")
        page = 1

        while next_url:
            page += 1
            if page > COLLECTION_MAX_PAGES:
                raise Failure(f"ASC collection exceeded {COLLECTION_MAX_PAGES} pages")
            response = self.get(next_url)
            items.extend(self._resource_list(response, "data"))
            included.extend(self._resource_list(response, "included"))
            next_url = (response.get("links") or {}).get("next")

        return items, included

    def _request(self, method, path, params=None, body=None):
        url = self._build_url(path, params or {})
        body_bytes = None if body is None else json.dumps(body, separators=(",", ":")).encode("utf-8")
        last_transport_error = None

        for attempt in range(HTTP_MAX_ATTEMPTS):
            request_headers = {
                "Authorization": f"Bearer {self._token_provider()}",
                "Accept": "application/json",
            }
            if body_bytes is not None:
                request_headers["Content-Type"] = "application/json"
            request = urllib.request.Request(
                url,
                data=body_bytes,
                headers=request_headers,
                method=method,
            )

            try:
                with self._opener.open(request, timeout=READ_TIMEOUT_SECONDS) as response:
                    status = response.getcode()
                    response_body = response.read()
                    retry_after_header = response.headers.get("Retry-After")
            except urllib.error.HTTPError as error:
                status = error.code
                response_body = error.read()
                retry_after_header = error.headers.get("Retry-After") if error.headers else None
            except (urllib.error.URLError, OSError, EOFError, http.client.HTTPException) as error:
                last_transport_error = error
                if attempt == HTTP_MAX_ATTEMPTS - 1:
                    raise Failure(
                        f"ASC {method} request failed after retries: {type(error).__name__}"
                    )
                time.sleep(self._retry_delay(attempt))
                continue

            if status == 429 or status >= 500:
                if attempt < HTTP_MAX_ATTEMPTS - 1:
                    retry_after = self._retry_after(retry_after_header)
                    time.sleep(self._retry_delay(attempt, retry_after))
                    continue

            if status < 200 or status >= 300:
                raise Failure(
                    f"ASC {method} request failed with HTTP {status}: "
                    f"{self._error_detail(response_body)}"
                )
            return self._parse_response(response_body)

        if last_transport_error is not None:
            raise Failure(
                f"ASC {method} request failed after retries: "
                f"{type(last_transport_error).__name__}"
            )
        raise Failure(f"ASC {method} request failed after retries")

    @staticmethod
    def _build_url(path, params):
        if not isinstance(path, str):
            raise Failure("ASC pagination link is not a URL")
        parsed = urlsplit(path)
        if parsed.scheme or parsed.netloc:
            if parsed.scheme != "https" or parsed.netloc != API_HOST:
                raise Failure("ASC pagination link has an untrusted host")
            url = path
        else:
            url = f"{API_BASE}{path}"
        if not params:
            return url
        parsed = urlsplit(url)
        existing = parse_qsl(parsed.query, keep_blank_values=True)
        query = urlencode(existing + list(params.items()))
        return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, query, parsed.fragment))

    @staticmethod
    def _resource_list(response, key):
        resources = response.get(key) or []
        if not isinstance(resources, list):
            raise Failure(f"ASC response field {key} is malformed")
        return list(resources)

    @staticmethod
    def _retry_after(retry_after_header):
        if retry_after_header is None:
            return None
        try:
            return int(retry_after_header)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _retry_delay(attempt, retry_after=None):
        if retry_after is not None:
            return max(min(retry_after, HTTP_MAX_RETRY_DELAY_SECONDS), 0)
        return min(2**attempt, HTTP_MAX_RETRY_DELAY_SECONDS)

    @staticmethod
    def _parse_response(response_body):
        if not response_body:
            return {}
        try:
            return json.loads(response_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise Failure("ASC returned invalid JSON")

    @staticmethod
    def _error_detail(response_body):
        try:
            parsed = json.loads(response_body.decode("utf-8"))
            errors = parsed.get("errors") or []
            error = errors[0] if errors else {}
            detail = error.get("detail") or error.get("title") or ""
            return re.sub(r"\s+", " ", str(detail))[:240]
        except (AttributeError, IndexError, UnicodeDecodeError, json.JSONDecodeError):
            return "unparseable error response"


def string_value(value):
    return "" if value is None else str(value)


def validate_release_metadata(environment):
    path = os.environ.get("RELEASE_METADATA_PATH")
    if not path:
        return

    try:
        with open(path, "r", encoding="utf-8") as metadata_file:
            metadata = json.load(metadata_file)
    except FileNotFoundError:
        raise Failure("release metadata file is missing")
    except json.JSONDecodeError:
        raise Failure("release metadata is not valid JSON")

    expected_build_numbers = {
        "IOS": environment["IOS_BUILD_NUMBER"],
        "MAC_OS": environment["MACOS_BUILD_NUMBER"],
    }
    if not (
        metadata.get("bundle_id") == environment["BUNDLE_ID"]
        and metadata.get("marketing_version") == environment["MARKETING_VERSION"]
        and metadata.get("build_numbers") == expected_build_numbers
        and metadata.get("platforms") == list(PLATFORMS)
    ):
        raise Failure("release metadata does not match the requested build")


def resolve_app(api, bundle_id):
    apps = api.collection("/v1/apps", params={"filter[bundleId]": bundle_id, "limit": "200"})
    if len(apps) != 1:
        raise Failure(
            f"expected exactly one App Store Connect app for bundle ID {bundle_id}, "
            f"found {len(apps)}"
        )

    app = apps[0]
    if not string_value(app.get("id")):
        raise Failure("resolved App Store Connect app has no ID")
    if app.get("type") != "apps":
        raise Failure("resolved App Store Connect resource is not an app")
    return app


def parse_cf_bundle_version(value, context):
    if re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value) is None:
        raise Failure(f"{context} is not a valid CFBundleVersion")
    components = [int(component, 10) for component in value.split(".")]
    if not 1 <= components[0] <= 9999:
        raise Failure(f"{context} first component must be between 1 and 9999")
    if any(component > 99 for component in components[1:]):
        raise Failure(f"{context} later components must be between 0 and 99")
    return components


def increment_cf_bundle_version(components, context):
    next_components = list(components)
    index = len(next_components) - 1
    while index >= 0:
        maximum = 9999 if index == 0 else 99
        if next_components[index] < maximum:
            next_components[index] += 1
            for reset_index in range(index + 1, len(next_components)):
                next_components[reset_index] = 0
            return ".".join(str(component) for component in next_components)
        next_components[index] = 0
        index -= 1
    raise Failure(f"{context} overflowed the maximum CFBundleVersion")


def pre_release_index(included):
    index = {}
    for resource_number, resource in enumerate(included, start=1):
        if not isinstance(resource, dict):
            raise Failure(f"ASC included resource {resource_number} is malformed")
        resource_type = string_value(resource.get("type"))
        resource_id = string_value(resource.get("id"))
        if not resource_type or not resource_id:
            raise Failure(f"ASC included resource {resource_number} has no type or ID")
        key = (resource_type, resource_id)
        existing = index.get(key)
        if existing is not None and existing != resource:
            raise Failure(f"ASC included resource {resource_type}/{resource_id} is duplicated")
        index[key] = resource
    return index


def pre_release_info(build, included_index, build_number):
    relationships = build.get("relationships")
    relationship = relationships.get("preReleaseVersion") if isinstance(relationships, dict) else None
    relationship_data = relationship.get("data") if isinstance(relationship, dict) else None
    if not isinstance(relationship_data, dict):
        raise Failure(f"ASC build resource {build_number} has no preReleaseVersion linkage")

    relationship_type = relationship_data.get("type")
    relationship_id = relationship_data.get("id")
    if relationship_type != "preReleaseVersions" or not relationship_id:
        raise Failure(f"ASC build resource {build_number} has malformed preReleaseVersion linkage")

    resource = included_index.get((relationship_type, relationship_id))
    if not isinstance(resource, dict):
        raise Failure(f"ASC build resource {build_number} has no included preReleaseVersion")
    attributes = resource.get("attributes")
    if not isinstance(attributes, dict):
        raise Failure(f"ASC preReleaseVersion {relationship_id} has malformed attributes")

    platform = string_value(attributes.get("platform"))
    marketing_version = string_value(attributes.get("version"))
    if not platform or not marketing_version:
        raise Failure(f"ASC preReleaseVersion {relationship_id} has incomplete identity")
    return platform, marketing_version


def next_build_numbers(api, environment):
    app = resolve_app(api, environment["BUNDLE_ID"])
    builds, included = api.collection_with_included(
        "/v1/builds",
        params={
            "filter[app]": app["id"],
            "include": "preReleaseVersion",
            "limit": "200",
        },
    )
    included_index = pre_release_index(included)
    maximums = {}

    for index, build in enumerate(builds, start=1):
        if not isinstance(build, dict):
            raise Failure(f"ASC build resource {index} is malformed")
        platform, _ = pre_release_info(build, included_index, index)
        if platform not in PLATFORMS:
            continue
        attributes = build.get("attributes")
        if not isinstance(attributes, dict):
            raise Failure(f"ASC build resource {index} has malformed attributes")
        version = string_value(attributes.get("version"))
        components = parse_cf_bundle_version(version, f"ASC build resource {index} attributes.version")

        padded = tuple(components + [0] * (3 - len(components)))
        candidate_key = (padded, len(components))
        current = maximums.get(platform)
        if current is None or candidate_key > current[0]:
            maximums[platform] = (candidate_key, components)

    build_numbers = {}
    for platform in PLATFORMS:
        current = maximums.get(platform)
        if current is None:
            build_numbers[platform] = "1"
            continue
        build_numbers[platform] = increment_cf_bundle_version(
            current[1],
            f"{platform} build number",
        )

    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        raise Failure("GITHUB_OUTPUT is required in next-build-numbers mode")
    with open(output_path, "a", encoding="utf-8") as output_file:
        output_file.write(f"ios_build_number={build_numbers['IOS']}\n")
        output_file.write(f"macos_build_number={build_numbers['MAC_OS']}\n")


def resolve_internal_group(api, group_id, app_id):
    encoded_group_id = quote(group_id, safe="")
    response = api.get(f"/v1/betaGroups/{encoded_group_id}")
    group = response.get("data")
    if not isinstance(group, dict):
        raise Failure(f"App Store Connect beta group {group_id} was not found")
    if group.get("type") != "betaGroups":
        raise Failure("resolved TestFlight group is not a beta group")
    attributes = group.get("attributes") or {}
    if attributes.get("isInternalGroup") is not True:
        raise Failure(f"TestFlight group {group_id} is not an internal group")

    app_response = api.get(f"/v1/betaGroups/{encoded_group_id}/app")
    app_relation = app_response.get("data")
    if not (
        isinstance(app_relation, dict)
        and app_relation.get("type") == "apps"
        and app_relation.get("id") == app_id
    ):
        raise Failure(f"TestFlight group {group_id} is not attached to bundle ID app {app_id}")
    return group


def expired_build(build):
    attributes = build.get("attributes") or {}
    if attributes.get("expired") is True:
        return True

    expiration_date = attributes.get("expirationDate")
    if expiration_date is None or expiration_date == "":
        return False
    try:
        parsed_date = datetime.datetime.fromisoformat(expiration_date.replace("Z", "+00:00"))
        if parsed_date.tzinfo is None:
            parsed_date = parsed_date.replace(tzinfo=datetime.timezone.utc)
        return parsed_date <= datetime.datetime.now(datetime.timezone.utc)
    except (AttributeError, TypeError, ValueError):
        return False


def exact_builds(api, app_id, marketing_version, build_numbers):
    candidates, included = api.collection_with_included(
        "/v1/builds",
        params={
            "filter[app]": app_id,
            "include": "preReleaseVersion",
            "limit": "200",
        },
    )
    included_index = pre_release_index(included)
    requested_keys = {
        (platform, marketing_version, build_numbers[platform]) for platform in PLATFORMS
    }
    matches = {}

    for index, build in enumerate(candidates, start=1):
        if not isinstance(build, dict):
            raise Failure(f"ASC build resource {index} is malformed")
        attributes = build.get("attributes")
        if not isinstance(attributes, dict):
            raise Failure(f"ASC build resource {index} has malformed attributes")
        platform, build_marketing_version = pre_release_info(build, included_index, index)
        build_number = string_value(attributes.get("version"))
        if platform in PLATFORMS:
            parse_cf_bundle_version(
                build_number,
                f"ASC build resource {index} attributes.version",
            )
        candidate_key = (platform, build_marketing_version, build_number)
        if candidate_key not in requested_keys or expired_build(build):
            continue
        if candidate_key in matches:
            raise Failure(
                f"multiple {platform} builds match version {marketing_version} "
                f"build {build_numbers[platform]}"
            )
        matches[candidate_key] = build

    return {
        platform: matches.get((platform, marketing_version, build_numbers[platform]))
        for platform in PLATFORMS
    }


def processing_state(build):
    if build is None:
        return "MISSING"
    attributes = build.get("attributes") or {}
    state = string_value(attributes.get("processingState"))
    if not state:
        raise Failure(f"matching build {string_value(build.get('id'))} has no processing state")
    return state


def preflight(api, environment):
    app = resolve_app(api, environment["BUNDLE_ID"])
    resolve_internal_group(api, environment["TESTFLIGHT_INTERNAL_GROUP_ID"], app["id"])
    builds = exact_builds(
        api,
        app["id"],
        environment["MARKETING_VERSION"],
        {
            "IOS": environment["IOS_BUILD_NUMBER"],
            "MAC_OS": environment["MACOS_BUILD_NUMBER"],
        },
    )
    upload = {}
    for platform in PLATFORMS:
        state = processing_state(builds[platform])
        if state == "MISSING":
            upload[platform] = True
        elif state in PROCESSING_STATES:
            upload[platform] = False
        elif state in FAILED_STATES:
            raise Failure(f"matching {platform} build is {state}")
        else:
            raise Failure(f"matching {platform} build has unsupported processing state {state}")

    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        raise Failure("GITHUB_OUTPUT is required in preflight mode")
    with open(output_path, "a", encoding="utf-8") as output_file:
        output_file.write(f"ios_upload={str(upload['IOS']).lower()}\n")
        output_file.write(f"macos_upload={str(upload['MAC_OS']).lower()}\n")


def assign(api, environment):
    app = resolve_app(api, environment["BUNDLE_ID"])
    group_id = environment["TESTFLIGHT_INTERNAL_GROUP_ID"]
    resolve_internal_group(api, group_id, app["id"])
    deadline = time.time() + ASSIGN_TIMEOUT_SECONDS
    last_status = None
    builds = {}

    while True:
        builds = exact_builds(
            api,
            app["id"],
            environment["MARKETING_VERSION"],
            {
                "IOS": environment["IOS_BUILD_NUMBER"],
                "MAC_OS": environment["MACOS_BUILD_NUMBER"],
            },
        )
        statuses = {platform: processing_state(builds[platform]) for platform in PLATFORMS}
        status_text = " ".join(f"{platform}={statuses[platform]}" for platform in PLATFORMS)
        if status_text != last_status:
            print(f"Waiting for exact TestFlight builds: {status_text}")
        last_status = status_text

        failed_platform = next(
            (platform for platform in PLATFORMS if statuses[platform] in FAILED_STATES),
            None,
        )
        if failed_platform:
            raise Failure(f"matching {failed_platform} build is {statuses[failed_platform]}")
        if all(statuses[platform] == "VALID" for platform in PLATFORMS):
            break
        if time.time() >= deadline:
            raise Failure("timed out waiting for exact TestFlight builds to become VALID")
        time.sleep(min(ASSIGN_POLL_INTERVAL_SECONDS, max(deadline - time.time(), 0)))

    for platform in PLATFORMS:
        build = builds[platform]
        if build is None:
            raise Failure(f"matching {platform} build disappeared before assignment")
        build_id = build.get("id")
        if not build_id:
            raise Failure(f"matching {platform} build has no ID")
        groups = api.collection(f"/v1/builds/{quote(build_id, safe='')}/betaGroups")
        associated = any(
            group.get("type") == "betaGroups" and group.get("id") == group_id
            for group in groups
        )
        if associated:
            print(f"{platform} build {build_id} is already assigned to the internal TestFlight group")
            continue

        api.post(
            f"/v1/betaGroups/{quote(group_id, safe='')}/relationships/builds",
            {"data": [{"type": "builds", "id": build_id}]},
        )
        print(f"Assigned {platform} build {build_id} to the internal TestFlight group")


def run(mode):
    if mode not in ("preflight", "assign", "next-build-numbers"):
        raise Failure(
            "usage: python3 scripts/manage_testflight_builds.py "
            "preflight|assign|next-build-numbers"
        )

    if mode == "next-build-numbers":
        environment = required_environment(NEXT_BUILD_NUMBER_ENVIRONMENT)
        api = ApiClient(
            lambda: build_jwt(
                environment["ASC_ISSUER_ID"],
                environment["ASC_KEY_ID"],
                environment["ASC_PRIVATE_KEY_PATH"],
            )
        )
        next_build_numbers(api, environment)
        return

    environment = required_environment()
    for name in ("IOS_BUILD_NUMBER", "MACOS_BUILD_NUMBER"):
        parse_cf_bundle_version(environment[name], name)

    validate_release_metadata(environment)
    api = ApiClient(
        lambda: build_jwt(
            environment["ASC_ISSUER_ID"],
            environment["ASC_KEY_ID"],
            environment["ASC_PRIVATE_KEY_PATH"],
        )
    )
    if mode == "preflight":
        preflight(api, environment)
    else:
        assign(api, environment)


def main():
    mode = sys.argv[1] if len(sys.argv) == 2 else None
    try:
        run(mode)
    except Failure as error:
        print(f"manage-testflight-builds: {error}", file=sys.stderr)
        return 1
    except Exception as error:
        print(f"manage-testflight-builds: {type(error).__name__}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
