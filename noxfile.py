# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os

import nox

#
# Utility Functions
#


def _collect_dirs(
    start_dir,
    suffix="_test.py",
    recurse_further=False,
):
    """Recursively collects a list of dirs that contain a file matching the given suffix.
    This works by listing the contents of directories and finding
    directories that have `*_test.py` files.
    """
    # Collect all the directories that have tests in them.
    for parent, subdirs, files in os.walk(start_dir):
        if "./." in parent:
            continue  # Skip top-level dotfiles
        elif any(f for f in files if f.endswith(suffix)):
            # Don't recurse further for tests, since py.test will do that.
            if not recurse_further:
                del subdirs[:]
            # This dir has desired files in it. yield it.
            yield parent
        else:
            # Filter out dirs we don't want to recurse into
            subdirs[:] = [s for s in subdirs if s[0].isalpha()]


#
# Tests
#


FOLDERS = sorted(list(_collect_dirs(".")))


def _session_tests(session, folder):
    """Runs py.test for a particular directory."""
    session.chdir(folder)

    if os.path.exists("requirements.txt"):
        session.install("-r", "requirements.txt")

    session.run(
        "pytest",
        *(session.posargs),
        # Pytest will return 5 when no tests are collected. This can happen
        # on travis where slow and flaky tests are excluded.
        # See http://doc.pytest.org/en/latest/_modules/_pytest/main.html
        success_codes=[0, 5],
    )


@nox.session(python=["3.12"])
@nox.parametrize("folder", FOLDERS)
def test(session, folder):
    """Runs py.test for a folder using the specified version of Python."""
    session.install("-r", "requirements-test.txt")
    _session_tests(session, folder)


#
# Style
#


@nox.session
def lint(session):
    session.install("ruff")
    session.run("ruff", "format", "--check", ".")
    session.run("ruff", "check", ".")


@nox.session
def formatting(session):
    session.install("ruff")
    session.run("ruff", "format", ".")
    session.run("ruff", "check", ".", "--fix")


nox.options.sessions = ["lint", "test"]
