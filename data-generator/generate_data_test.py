# Copyright 2021 Google, LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import datetime
from itertools import pairwise
from urllib.request import Request

import pytest

import generate_data
from util_compare_dicts import compare_dicts


@pytest.fixture
def generate_changes():
    return generate_data.make_changes(2, 604800)


@pytest.fixture
def generate_all_changesets():
    return generate_data.make_all_changesets(10, 604800)


@pytest.fixture
def generate_ind_changes(generate_all_changesets):
    for changeset in generate_all_changesets:
        yield generate_data.make_ind_changes_from_changeset(changeset)


@pytest.fixture
def generate_deployment(generate_changes):
    return generate_data.create_github_deploy_event(generate_changes["head_commit"])


@pytest.fixture
def generate_issue(generate_changes):
    return generate_data.make_github_issue(generate_changes["head_commit"])


@pytest.fixture
def make_change_request(generate_changes):
    return generate_data.make_webhook_request(
        webhook_url="http://dummy_url",
        secret="dummy_secret_string",
        event_type="push",
        data=generate_changes,
    )


@pytest.fixture
def valid_changes():
    # return an example of what valid data looks like
    return {
        "head_commit": {
            "id": "29f54bb6cdb25a67dc7a2b7dae17a1346e2e9609",
            "timestamp": datetime.datetime(2021, 2, 1, 3, 38, 39, 923909),
        },
        "before": "50b2c21f17f97e040707665a2da5288cdc766e8a",
        "commits": [
            {
                "id": "c814b7082ba2ae5d2076568baa67a6b694845e42",
                "timestamp": datetime.datetime(2021, 2, 1, 3, 38, 39, 923909),
            },
            {
                "id": "29f54bb6cdb25a67dc7a2b7dae17a1346e2e9609",
                "timestamp": datetime.datetime(2021, 1, 28, 10, 28, 32, 923935),
            },
        ],
    }


@pytest.fixture
def valid_deployment():
    return {
        "deployment_status": {
            "updated_at": datetime.datetime(2021, 1, 29, 20, 2, 25, 104205),
            "id": "14cdd47757a1ef343c4e183b457ff5cbe85a173b",
            "state": "success",
        },
        "deployment": {"sha": "189941869a9bee33fb03e1e18596ea55c4d892e2"},
    }


@pytest.fixture
def valid_issue():
    return {
        "issue": {
            "created_at": datetime.datetime(2021, 1, 30, 22, 30, 5, 76942),
            "updated_at": datetime.datetime(2021, 2, 2, 21, 20, 58, 77232),
            "closed_at": datetime.datetime(2021, 2, 2, 21, 20, 58, 77235),
            "number": 440,
            "labels": [{"name": "Incident"}],
            "body": "root cause: 2b04b6d3939608f19776193697e0e30c04d9c6b8",
        },
        "repository": {"name": "foobar"},
    }


@pytest.fixture
def valid_change_request(generate_changes):
    request = Request(
        url="http://dummy_url",
        data=generate_changes,
        headers={"Content-type": "application/json", "Mock": True},
    )
    request.add_header("X-github-event", "push")
    request.add_header(
        "X-hub-signature", "sha1=73a9ef6ce9bda2b769807691ddacfe3caf50f4e0"
    )
    request.add_header("User-agent", "GitHub-Hookshot/mock")

    return request


def test_changes(generate_changes, valid_changes):
    assert compare_dicts(generate_changes, valid_changes) == "pass", compare_dicts


def test_deployment(valid_deployment, generate_deployment):
    assert compare_dicts(generate_deployment, valid_deployment) == "pass", compare_dicts


def test_issue(valid_issue, generate_issue):
    assert compare_dicts(generate_issue, valid_issue) == "pass", compare_dicts


def test_request(valid_change_request, make_change_request):
    assert (
        compare_dicts(make_change_request.headers, valid_change_request.headers)
        == "pass"
    ), compare_dicts


def test_all_changesets_linked_with_before_attribute(generate_all_changesets):
    all_changesets = generate_all_changesets
    for change, next_change in pairwise(all_changesets):
        checkout_sha = change.get("checkout_sha")
        head_commit = change.get("head_commit", {}).get("id")
        current_sha = checkout_sha or head_commit
        next_sha = next_change["before"]
        assert next_sha == current_sha


def test_ind_change_from_changeset_linked_with_before_attribute(
    generate_all_changesets,
):
    for changeset in generate_all_changesets:
        ind_changes = generate_data.make_ind_changes_from_changeset(changeset)

        for change, next_change in pairwise(ind_changes):
            checkout_sha = change.get("checkout_sha")
            head_commit = change.get("head_commit", {}).get("id")
            current_sha = checkout_sha or head_commit
            next_sha = next_change["before"]
            assert next_sha == current_sha
