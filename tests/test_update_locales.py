"""Locale updater contracts: no model/network calls or real locale writes."""

import importlib.util
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace

import pytest

spec = importlib.util.spec_from_file_location(
    "update_locales", Path(__file__).resolve().parents[1] / "update_locales.py"
)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


def arguments(**overrides):
    defaults = dict(backend=None, base_url=None, model=None, parallel=None,
                    full=False, dry_run=False, context="")
    return SimpleNamespace(**(defaults | overrides))


def config(backend="codex"):
    return updater.configure(dict(updater.DEFAULT_CONFIG), arguments(backend=backend))


@pytest.mark.parametrize("saved,backend,model", [
    ({}, "codex", None),
    ({"model": "sonnet"}, "codex", None),
    ({"api_format": "claude-code", "model": "sonnet"}, "claude-code", "sonnet"),
    ({"base_url": "https://example.test/v1", "model": "api-model"}, "openai", "api-model"),
    ({"base_url": "https://api.anthropic.com", "model": "api-model"}, "anthropic", "api-model"),
])
def test_default_and_legacy_config(tmp_path, monkeypatch, saved, backend, model):
    path = tmp_path / "config.json"
    path.write_text(json.dumps(saved))
    monkeypatch.setattr(updater, "CONFIG_FILE", path)
    loaded = updater.load_config()
    resolved = updater.configure(loaded, arguments())
    assert (resolved["backend"], resolved["model"]) == (backend, model)
    selected = updater.configure(loaded, arguments(backend="codex"))
    assert selected["model"] is None
    selected = updater.configure(loaded, arguments(backend="codex", model="override"))
    assert selected["model"] == "override"
    if saved == {"model": "sonnet"}:
        assert updater.configure(loaded, arguments(backend="claude-code"))["model"] == "sonnet"


def test_backend_specific_models_and_cli_precedence():
    saved = dict(updater.DEFAULT_CONFIG, backend="claude-code",
                 models={"codex": "codex-model", "claude-code": "sonnet"})
    assert updater.configure(saved, arguments(backend="codex"))["model"] == "codex-model"
    assert updater.configure(saved, arguments(backend="codex", model="override"))["model"] == "override"


@pytest.mark.parametrize("changes", [
    {"parallel": 0}, {"chunk_size": -1}, {"timeout_seconds": "10"},
    {"backend": "unknown"}, {"backend": "openai"},
])
def test_bad_config_rejected(changes):
    with pytest.raises(ValueError):
        updater.configure(dict(updater.DEFAULT_CONFIG, **changes), arguments())


@pytest.mark.parametrize("backend", ["codex", "claude-code"])
def test_cli_structured_output_contract(tmp_path, monkeypatch, backend):
    entries = {"gui/name": {"english": "Name"}}
    answer = {"gui/name": "Nom"}
    monkeypatch.setenv("OPENAI_API_KEY", "unused-api-key")
    monkeypatch.setenv("CODEX_API_KEY", "unused-api-key")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "unused-api-key")

    def run(command, **kwargs):
        assert Path(kwargs["cwd"]) != updater.PROJECT_ROOT
        assert json.loads(kwargs["input"].split("\n\n")[-1])["entries"] == entries
        assert "--model" not in command
        if backend == "codex":
            assert command[:2] == ["codex", "exec"]
            assert command[-1] == "-"
            assert command[command.index("--sandbox") + 1] == "read-only"
            assert "OPENAI_API_KEY" not in kwargs["env"]
            assert "CODEX_API_KEY" not in kwargs["env"]
            schema = json.loads(Path(command[command.index("--output-schema") + 1]).read_text())
            Path(command[command.index("--output-last-message") + 1]).write_text(json.dumps(answer))
            stdout = "event stream should not be parsed"
        else:
            assert command[:2] == ["claude", "-p"]
            assert command[command.index("--tools") + 1] == ""
            assert "ANTHROPIC_API_KEY" not in kwargs["env"]
            schema = json.loads(command[command.index("--json-schema") + 1])
            stdout = json.dumps({"subtype": "success", "is_error": False,
                                 "result": "Do not parse this", "structured_output": answer})
        assert schema["required"] == list(entries)
        assert schema["additionalProperties"] is False
        return subprocess.CompletedProcess(command, 0, stdout, "")

    monkeypatch.setattr(updater.subprocess, "run", run)
    assert updater.request_translations(config(backend), "Translate", entries, {}) == answer


@pytest.mark.parametrize("backend", ["codex", "claude-code"])
@pytest.mark.parametrize("failure", ["exit", "timeout", "missing"])
def test_operational_cli_failure_is_not_retried(monkeypatch, backend, failure):
    calls = []

    def run(command, **kwargs):
        calls.append(command)
        if failure == "timeout":
            raise subprocess.TimeoutExpired(command, 600)
        if failure == "missing":
            raise FileNotFoundError(command[0])
        if backend == "codex":
            # A valid-looking file must not hide a failed process.
            Path(command[command.index("--output-last-message") + 1]).write_text('{"gui/name":"Nom"}')
        return subprocess.CompletedProcess(command, 1, "", "login required")

    monkeypatch.setattr(updater.subprocess, "run", run)
    with pytest.raises(RuntimeError):
        updater.translate_entries(config(backend), "French", {"gui/name": {"english": "Name"}}, {}, "")
    assert len(calls) == 1


def test_claude_error_envelope_fails_even_with_zero_exit(monkeypatch):
    monkeypatch.setattr(updater.subprocess, "run", lambda *a, **kw:
                        subprocess.CompletedProcess(a, 0, '{"is_error":true,"subtype":"error_max_turns"}', ""))
    with pytest.raises(RuntimeError, match="error_max_turns"):
        updater.call_cli(config("claude-code"), "", "", {})


@pytest.mark.parametrize("response", [
    "[]", "null", "not json", '{"gui/name":"Nom","extra":"No"}',
    '{"gui/name":"Nom","gui/name":"Autre"}',
    '{"gui/name":{"translation":"Nom"}}', '{}', '{"gui/name":""}',
])
def test_bad_output_retries_then_fails(monkeypatch, response):
    calls = []

    def model(*args):
        calls.append(args)
        return response, None

    monkeypatch.setattr(updater, "call_model", model)
    with pytest.raises(RuntimeError, match="after retries"):
        updater.translate_entries(config(), "French", {"gui/name": {"english": "Name"}}, {}, "")
    assert len(calls) == 4
    assert "Correct these validation errors" in calls[-1][1]


def test_retry_only_invalid_entries(monkeypatch):
    requests = []

    def model(cfg, system, user, schema):
        entries = json.loads(user)["entries"]
        requests.append(list(entries))
        if len(requests) == 1:
            return '{"gui/name":"Nom","gui/count":"Compteur"}', None
        return '{"gui/count":"Compteur __1__"}', None

    monkeypatch.setattr(updater, "call_model", model)
    entries = {"gui/name": {"english": "Name"}, "gui/count": {"english": "Count __1__"}}
    assert updater.translate_entries(config(), "French", entries, {}, "") == {
        "gui/name": "Nom", "gui/count": "Compteur __1__"
    }
    assert requests == [["gui/name", "gui/count"], ["gui/count"]]


@pytest.mark.parametrize("source,translated,problem", [
    ("__1__ __1__", "__1__", "placeholders"),
    ("__1__ __2__", "__2__ __1__", None),
    ("[color=red]Red[/color]", "[color=green]Rouge[/color]", "rich-text"),
    ("[color=red]Red[/color]", "[color=red]Rouge", "rich-text"),
    (r"First\nSecond", "Premier", "newlines"),
    (r"First\nSecond", r"Premier\nSecond", None),
    ("Name", "Nom\x00", "control"),
    ("https://example.test/a", "https://example.test/b", "URLs"),
])
def test_format_validation(source, translated, problem):
    result = updater.validate_translation("gui/key", source, translated)
    if problem is None:
        assert result is None
    else:
        assert problem in result


@pytest.fixture
def language_file(tmp_path, monkeypatch):
    monkeypatch.setattr(updater, "PROJECT_ROOT", tmp_path)
    monkeypatch.setattr(updater, "english_at_last_sync", lambda path: {"gui/name": "Name"})
    path = tmp_path / "locale/fr/locale.cfg"
    path.parent.mkdir(parents=True)
    path.write_text(f"# {updater.DISCLAIMER_EN}\n\n[gui]\nname=Nom\nobsolete=Ancien\n")
    return path


def test_failed_translation_preserves_entire_file(language_file, monkeypatch):
    original = language_file.read_bytes()
    monkeypatch.setattr(updater, "call_model", lambda *a: ('{"gui/count":"Compteur"}', None))
    english = "[gui]\nname=Name\ncount=Count __1__\n"
    with pytest.raises(RuntimeError):
        updater.process_language(config(), "fr", arguments(), english, updater.parse_locale(english))
    assert language_file.read_bytes() == original  # Includes obsolete key.


def test_new_language_failure_creates_no_file(tmp_path, monkeypatch):
    monkeypatch.setattr(updater, "PROJECT_ROOT", tmp_path)
    monkeypatch.setattr(updater, "call_model", lambda *a: ('{}', None))
    english = "[gui]\nname=Name\n"
    with pytest.raises(RuntimeError):
        updater.process_language(config(), "fr", arguments(), english, updater.parse_locale(english))
    assert not (tmp_path / "locale/fr/locale.cfg").exists()


def test_removal_only_needs_no_model(language_file, monkeypatch):
    def unexpected(*args):
        pytest.fail("Removal-only updates must not invoke a model")

    monkeypatch.setattr(updater, "call_model", unexpected)
    english = "[gui]\nname=Name\n"
    result = updater.process_language(config(), "fr", arguments(), english, updater.parse_locale(english))
    assert result["status"] == "ok"
    assert updater.parse_locale(language_file.read_text()) == {"gui/name": "Nom"}


def test_advisories_do_not_rewrite_or_retry_translations(language_file, monkeypatch):
    calls = []

    def model(*args):
        calls.append(args)
        return '{"gui/label":"Nom","gui/other-name":"Appellation"}', None

    monkeypatch.setattr(updater, "call_model", model)
    english = "[gui]\nname=Name\nlabel=Label\nother-name=Name\n"
    result = updater.process_language(config(), "fr", arguments(), english, updater.parse_locale(english))
    assert result["status"] == "ok-with-advisories"
    assert len(result["warnings"]) == 1
    assert result["warnings"][0].startswith("Identical English text has different translations:")
    assert len(calls) == 1
    assert updater.parse_locale(language_file.read_text()) == {
        "gui/name": "Nom", "gui/label": "Nom", "gui/other-name": "Appellation"
    }


def test_atomic_replace_failure_keeps_original(language_file, monkeypatch):
    original = language_file.read_bytes()

    def fail(*args):
        raise OSError("replace failed")

    monkeypatch.setattr(updater.os, "replace", fail)
    with pytest.raises(OSError):
        updater.write_locale_atomically(language_file, "replacement")
    assert language_file.read_bytes() == original
    assert list(language_file.parent.iterdir()) == [language_file]


def test_main_failure_exit_preserves_file(language_file, monkeypatch):
    reference = language_file.parents[1] / "en/locale.cfg"
    reference.parent.mkdir()
    reference.write_text("[gui]\nname=Name\ncount=Count __1__\n")
    monkeypatch.setattr(updater, "REFERENCE_FILE", reference)
    monkeypatch.setattr(updater, "load_config", lambda: dict(updater.DEFAULT_CONFIG))
    monkeypatch.setattr(updater.sys, "argv", ["update-locales.sh", "fr"])
    monkeypatch.setattr(updater, "call_model", lambda *a: ('{}', None))
    original = language_file.read_bytes()
    with pytest.raises(SystemExit) as exc:
        updater.main()
    assert exc.value.code == 1
    assert language_file.read_bytes() == original


@pytest.mark.parametrize("backend", ["openai", "anthropic"])
def test_direct_api_compatibility(monkeypatch, backend):
    cfg = updater.configure(dict(updater.DEFAULT_CONFIG), arguments(
        backend=backend, base_url="https://example.test", model="api-model"
    ))

    def post(cfg, url, headers, body):
        assert body["model"] == "api-model"
        if backend == "anthropic":
            assert url.endswith("/v1/messages")
            return {"content": [{"text": '{"gui/name":"Nom"}'}], "stop_reason": "end_turn"}
        assert url.endswith("/chat/completions")
        return {"choices": [{"message": {"content": '```json\n{"gui/name":"Nom"}\n```'},
                             "finish_reason": "stop"}]}

    monkeypatch.setattr(updater, "post_json", post)
    assert updater.translate_entries(cfg, "French", {"gui/name": {"english": "Name"}}, {}, "") == {
        "gui/name": "Nom"
    }


def test_truncated_batch_splits_and_preserves_all_entries(monkeypatch):
    calls = []

    def model(cfg, system, user, schema):
        entries = json.loads(user)["entries"]
        calls.append(list(entries))
        if len(entries) > 1:
            return '{"gui/name":', "length"
        return json.dumps({key: "Nom" for key in entries}), "stop"

    monkeypatch.setattr(updater, "call_model", model)
    entries = {"gui/name": {"english": "Name"}, "gui/label": {"english": "Label"}}
    assert updater.translate_entries(config(), "French", entries, {}, "") == {
        "gui/name": "Nom", "gui/label": "Nom"
    }
    assert calls == [["gui/name", "gui/label"], ["gui/name"], ["gui/label"]]


def test_duplicate_claude_structured_keys_rejected(monkeypatch):
    response = '{"subtype":"success","structured_output":{"gui/name":"Nom","gui/name":"Autre"}}'
    monkeypatch.setattr(updater.subprocess, "run", lambda *a, **kw:
                        subprocess.CompletedProcess(a, 0, response, ""))
    with pytest.raises(ValueError, match="Duplicate"):
        updater.call_cli(config("claude-code"), "", "", {})


def test_unicode_line_separator_rejected():
    assert "control" in updater.validate_translation("gui/name", "Name", "Nom\u2028name=Injected")


def test_example_config_is_usable(monkeypatch):
    monkeypatch.setattr(updater, "CONFIG_FILE", updater.PROJECT_ROOT / "locale-config.example.json")
    cfg = updater.configure(updater.load_config(), arguments())
    assert cfg["backend"] == "codex"
    assert cfg["model"] is None
