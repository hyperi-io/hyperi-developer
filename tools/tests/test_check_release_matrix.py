"""Tests for the supported-release matrix drift check."""

import importlib.util
from pathlib import Path

import pytest

MODULE = Path(__file__).resolve().parents[1] / "check_release_matrix.py"

MATRIX = [
    {"image": "docker.io/library/ubuntu:26.04", "distro": "Ubuntu", "release": "26.04", "rank": "n"},
    {"image": "docker.io/library/ubuntu:24.04", "distro": "Ubuntu", "release": "24.04", "rank": "n-1"},
    {"image": "docker.io/library/fedora:44", "distro": "Fedora", "release": "44", "rank": "n"},
    {"image": "docker.io/library/fedora:43", "distro": "Fedora", "release": "43", "rank": "n-1"},
]

MOLECULE = {"platforms": [{"image": e["image"]} for e in MATRIX]}
DEFAULTS = {"min_fedora_version": 43, "min_ubuntu_version": "24.04"}

# The shape of the real pre_tasks gate, closing quote and bracket included --
# the first regex written for this missed those and matched nothing.
GATE = (
    "(ansible_facts['distribution'] == 'Fedora' and "
    "ansible_facts['distribution_major_version']|int < 43) or\n"
    "(ansible_facts['distribution'] == 'Ubuntu' and "
    "ansible_facts['distribution_version'] is version('24.04', '<'))\n"
)


def load_module():
    spec = importlib.util.spec_from_file_location("check_release_matrix", MODULE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def check():
    return load_module()


def test_a_consistent_matrix_is_clean(check):
    assert check.compare(MATRIX, MOLECULE, DEFAULTS, GATE) == []


def test_the_gate_minimums_are_read_from_the_real_syntax(check):
    """The gate is a Jinja expression, so it is matched as text."""
    assert check.gate_minimums(GATE) == {"Fedora": "43", "Ubuntu": "24.04"}


def test_the_playbook_gate_drift_that_actually_happened(check):
    """Fedora 42 kept passing this gate after the role default was fixed."""
    stale = GATE.replace("int < 43", "int < 42")
    problems = check.compare(MATRIX, MOLECULE, DEFAULTS, stale)
    assert len(problems) == 1
    assert "admits Fedora 42" in problems[0]


def test_ubuntu_gate_drift_is_caught(check):
    stale = GATE.replace("'24.04', '<'", "'22.04', '<'")
    problems = check.compare(MATRIX, MOLECULE, DEFAULTS, stale)
    assert len(problems) == 1
    assert "admits Ubuntu 22.04" in problems[0]


def test_a_gate_whose_shape_changed_is_reported_not_ignored(check):
    """A silently unmatchable pattern would make this check vacuous."""
    problems = check.compare(MATRIX, MOLECULE, DEFAULTS, "when: some_other_gate")
    assert len(problems) == 2
    assert all("no" in p and "comparison to check" in p for p in problems)


def test_the_gate_is_skipped_when_no_text_is_given(check):
    """compare() is used by the unit tests without a playbook."""
    assert check.compare(MATRIX, MOLECULE, DEFAULTS) == []


UPDATE_TEST = 'DEFAULT_IMAGES=(\n    "ubuntu:26.04"\n    "ubuntu:24.04"\n    "fedora:44"\n    "fedora:43"\n)\n'


def test_the_update_test_image_list_is_read(check):
    assert check.update_test_images(UPDATE_TEST) == [
        "ubuntu:26.04",
        "ubuntu:24.04",
        "fedora:44",
        "fedora:43",
    ]


def test_the_registry_prefix_does_not_count_as_drift(check):
    """The matrix qualifies images, the bash array does not."""
    assert check.compare(MATRIX, MOLECULE, DEFAULTS, GATE, UPDATE_TEST) == []


def test_an_unswept_release_is_caught(check):
    stale = UPDATE_TEST.replace('    "fedora:43"\n', "")
    problems = check.compare(MATRIX, MOLECULE, DEFAULTS, GATE, stale)
    assert len(problems) == 1
    assert "not swept" in problems[0]


def test_sweeping_an_undeclared_release_is_caught(check):
    stale = UPDATE_TEST.replace('    "fedora:43"\n', '    "fedora:42"\n')
    problems = check.compare(MATRIX, MOLECULE, DEFAULTS, GATE, stale)
    assert len(problems) == 2
    assert any("sweeps fedora:42" in p for p in problems)
    assert any("not swept by" in p for p in problems)


def test_an_unreadable_image_array_is_reported(check):
    problems = check.compare(MATRIX, MOLECULE, DEFAULTS, GATE, "IMAGES=(a b)")
    assert len(problems) == 1
    assert "unreadable" in problems[0]


def test_an_untested_release_is_caught(check):
    """The duplication this exists for: vars.yml gains a release, molecule does not."""
    molecule = {"platforms": [{"image": e["image"]} for e in MATRIX[:3]]}
    problems = check.compare(MATRIX, molecule, DEFAULTS)
    assert len(problems) == 1
    assert "fedora:43" in problems[0]
    assert "not tested" in problems[0]


def test_testing_an_undeclared_release_is_caught(check):
    """Drift the other way: a platform nobody declared as supported."""
    molecule = {"platforms": MOLECULE["platforms"] + [{"image": "docker.io/library/fedora:42"}]}
    problems = check.compare(MATRIX, molecule, DEFAULTS)
    assert len(problems) == 1
    assert "fedora:42" in problems[0]
    assert "absent from molecule_matrix" in problems[0]


def test_the_fedora_drift_that_actually_happened(check):
    """min_fedora_version sat at 42 while the matrix said n-1 was 43, two months
    after 42 went EOL."""
    problems = check.compare(MATRIX, MOLECULE, {**DEFAULTS, "min_fedora_version": 42})
    assert len(problems) == 1
    assert "min_fedora_version" in problems[0]
    assert "'42'" in problems[0]
    assert "'43'" in problems[0]


def test_ubuntu_minimum_drift_is_caught(check):
    problems = check.compare(MATRIX, MOLECULE, {**DEFAULTS, "min_ubuntu_version": "22.04"})
    assert len(problems) == 1
    assert "min_ubuntu_version" in problems[0]


def test_an_int_minimum_matches_a_string_release(check):
    """Fedora's minimum is an int in defaults and a string in the matrix."""
    assert check.compare(MATRIX, MOLECULE, {**DEFAULTS, "min_fedora_version": 43}) == []


def test_a_matrix_missing_an_n_minus_one_slot_is_caught(check):
    """Without an n-1 entry there is nothing for the OS gate to mirror."""
    matrix = [e for e in MATRIX if not (e["distro"] == "Fedora" and e["rank"] == "n-1")]
    molecule = {"platforms": [{"image": e["image"]} for e in matrix]}
    problems = check.compare(matrix, molecule, DEFAULTS)
    assert any("no Fedora n-1 entry" in p for p in problems)
