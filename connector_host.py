"""Narrow operating-system boundary for QuaZe's Jac connectors.

Every filesystem operation is rooted in the synthetic demo vault next to this
module. The Jac layer owns workflow semantics and evidence labels; this module
only performs bounded platform I/O and returns JSON-shaped values.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import stat
import subprocess
import tempfile
from datetime import date, datetime, time, timedelta
from typing import Dict, List, Optional, TextIO
from urllib.parse import quote


_DEMO_CALENDAR = "QuaZe Demo"
_GENERATED_BRIEF = "Tomorrow Brief.md"
_MCP_PROTOCOL_VERSION = "2025-06-18"
_MCP_REQUIRED_TOOLS = {
    "list_allowed_directories",
    "list_directory",
    "read_text_file",
}


class MCPProtocolError(RuntimeError):
    """Raised when the local filesystem MCP process violates expectations."""


class UnsafeArtifactTargetError(OSError):
    """Raised when the bounded write target cannot be opened safely."""


def _demo_vault_root() -> Path:
    module_root = Path(__file__).resolve().parent
    fixtures_root = module_root / "fixtures"
    vault_path = fixtures_root / "demo-vault"
    if fixtures_root.is_symlink() or vault_path.is_symlink():
        raise OSError(
            "The dedicated demo vault path must not contain symbolic links."
        )
    root = vault_path.resolve()
    if not root.is_dir():
        raise FileNotFoundError(
            "The dedicated demo vault is missing. Restore fixtures/demo-vault."
        )
    return root


def _resolve_demo_vault_path(relative_path: str, must_exist: bool) -> Path:
    if not relative_path or Path(relative_path).is_absolute():
        raise ValueError("Use a non-empty path relative to the dedicated demo vault.")

    root = _demo_vault_root()
    candidate = (root / relative_path).resolve(strict=must_exist)
    try:
        contained = os.path.commonpath((str(root), str(candidate))) == str(root)
    except ValueError as exc:
        raise ValueError(
            "The requested path cannot be resolved inside the dedicated demo vault."
        ) from exc
    if not contained:
        raise ValueError("The requested path escapes the dedicated demo vault.")
    return candidate


def resolve_vault_path(relative_path: str, must_exist: bool = False) -> Dict[str, object]:
    """Resolve one path without exposing any broader filesystem root."""

    try:
        path = _resolve_demo_vault_path(relative_path, must_exist)
    except (FileNotFoundError, OSError, ValueError) as exc:
        return {"success": False, "path": "", "error": str(exc)}
    return {"success": True, "path": str(path), "error": ""}


def tomorrow_window(reference_date: str = "") -> Dict[str, object]:
    """Return a local-time, half-open tomorrow window."""

    try:
        base_date = date.fromisoformat(reference_date) if reference_date else date.today()
    except ValueError:
        return {
            "success": False,
            "window_start": "",
            "window_end": "",
            "calendar_date": "",
            "error": "reference_date must use YYYY-MM-DD format.",
        }

    tomorrow = base_date + timedelta(days=1)
    local_zone = datetime.now().astimezone().tzinfo
    window_start = datetime.combine(tomorrow, time.min, tzinfo=local_zone)
    window_end = window_start + timedelta(days=1)
    return {
        "success": True,
        "window_start": window_start.isoformat(),
        "window_end": window_end.isoformat(),
        "calendar_date": tomorrow.isoformat(),
        "error": "",
    }


def direct_vault_notes() -> Dict[str, object]:
    """Read UTF-8 Markdown notes from only the dedicated demo vault."""

    try:
        root = _demo_vault_root()
        notes: List[Dict[str, object]] = []
        for discovered in sorted(root.rglob("*.md")):
            if discovered.name == _GENERATED_BRIEF:
                continue
            path = _resolve_demo_vault_path(
                str(discovered.relative_to(root)),
                must_exist=True,
            )
            if not path.is_file():
                continue
            notes.append(
                {
                    "path": str(path.relative_to(root)),
                    "title": path.stem,
                    "content": path.read_text(encoding="utf-8"),
                }
            )
        return {"success": True, "notes": notes, "error": ""}
    except (FileNotFoundError, OSError, UnicodeError, ValueError) as exc:
        return {
            "success": False,
            "notes": [],
            "error": (
                "The dedicated demo vault could not be read safely: " + str(exc)
            ),
        }


_CALENDAR_READ_SCRIPT = r"""
on joinText(itemsToJoin, delimiterText)
    set previousDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to delimiterText
    set joinedText to itemsToJoin as text
    set AppleScript's text item delimiters to previousDelimiters
    return joinedText
end joinText

on run argv
    set requestedYear to item 1 of argv as integer
    set requestedMonth to item 2 of argv as integer
    set requestedDay to item 3 of argv as integer
    set fieldSeparator to ASCII character 31
    set recordSeparator to ASCII character 30

    set windowStart to current date
    set day of windowStart to 1
    set year of windowStart to requestedYear
    set month of windowStart to requestedMonth
    set day of windowStart to requestedDay
    set time of windowStart to 0
    set windowEnd to windowStart + (1 * days)

    tell application "Calendar"
        if not (exists calendar "QuaZe Demo") then
            return "__QUAZE_MISSING_CALENDAR__"
        end if

        set demoEvents to every event of calendar "QuaZe Demo" whose start date is greater than or equal to windowStart and start date is less than windowEnd
        if (count of demoEvents) is 0 then
            return "__QUAZE_EMPTY_CALENDAR__"
        end if

        set resultRows to {}
        repeat with demoEvent in demoEvents
            set eventIdentifier to ""
            set eventTitle to ""
            set attendeeValues to {}
            try
                set eventIdentifier to uid of demoEvent
                set eventTitle to summary of demoEvent
                repeat with attendeeItem in attendees of demoEvent
                    try
                        set end of attendeeValues to email of attendeeItem
                    on error
                        try
                            set end of attendeeValues to display name of attendeeItem
                        end try
                    end try
                end repeat
            on error
                return "__QUAZE_MALFORMED_CALENDAR__"
            end try
            set attendeeText to my joinText(attendeeValues, ", ")
            set eventRow to my joinText({eventIdentifier, eventTitle, (start date of demoEvent as text), (end date of demoEvent as text), attendeeText}, fieldSeparator)
            set end of resultRows to eventRow
        end repeat
        return my joinText(resultRows, recordSeparator)
    end tell
end run
"""


def live_calendar_records(
    calendar_name: str = _DEMO_CALENDAR,
    reference_date: str = "",
) -> Dict[str, object]:
    """Read tomorrow from the one dedicated macOS Calendar, never writing."""

    if calendar_name != _DEMO_CALENDAR:
        return {
            "success": False,
            "events": [],
            "error": "Live Calendar access is restricted to the QuaZe Demo calendar.",
        }

    window = tomorrow_window(reference_date)
    if not bool(window["success"]):
        return {"success": False, "events": [], "error": str(window["error"])}

    calendar_date = str(window["calendar_date"])
    year, month, day = calendar_date.split("-")
    try:
        completed = subprocess.run(
            ["/usr/bin/osascript", "-e", _CALENDAR_READ_SCRIPT, year, month, day],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except FileNotFoundError:
        return {
            "success": False,
            "events": [],
            "error": "macOS Calendar automation is unavailable because osascript was not found.",
        }
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "events": [],
            "error": "Calendar did not respond within 15 seconds. Check Calendar permissions.",
        }
    except OSError:
        return {
            "success": False,
            "events": [],
            "error": "Calendar could not be started. Check macOS automation permissions.",
        }

    if completed.returncode != 0:
        stderr = completed.stderr.strip().lower()
        if (
            "not authorized" in stderr
            or "not permitted" in stderr
            or "-1743" in stderr
        ):
            error = (
                "Calendar permission was denied. Allow QuaZe to control Calendar "
                "in System Settings > Privacy & Security > Automation."
            )
        else:
            error = (
                "Calendar returned an error while reading QuaZe Demo. "
                "Open Calendar and confirm the dedicated calendar is available."
            )
        return {"success": False, "events": [], "error": error}

    parsed = parse_calendar_output(completed.stdout)
    if not bool(parsed["success"]):
        return parsed
    parsed["window_start"] = str(window["window_start"])
    parsed["window_end"] = str(window["window_end"])
    return parsed


def parse_calendar_output(output: str) -> Dict[str, object]:
    """Decode Calendar's record separators without stripping empty fields."""

    output = output.rstrip("\r\n")
    if output == "__QUAZE_MISSING_CALENDAR__":
        return {
            "success": False,
            "events": [],
            "error": "The dedicated QuaZe Demo calendar was not found.",
        }
    if output == "__QUAZE_EMPTY_CALENDAR__":
        return {
            "success": False,
            "events": [],
            "error": "QuaZe Demo has no events in the bounded tomorrow window.",
        }
    if output == "__QUAZE_MALFORMED_CALENDAR__" or not output:
        return {
            "success": False,
            "events": [],
            "error": "Calendar returned malformed event data for QuaZe Demo.",
        }

    events: List[Dict[str, object]] = []
    for row in output.split(chr(30)):
        fields = row.split(chr(31))
        if len(fields) != 5 or not fields[0].strip() or not fields[1].strip():
            return {
                "success": False,
                "events": [],
                "error": "Calendar returned malformed event data for QuaZe Demo.",
            }
        attendees = [
            item.strip() for item in fields[4].split(",") if item.strip()
        ]
        events.append(
            {
                "event_id": fields[0].strip(),
                "title": fields[1].strip(),
                "start_at": fields[2].strip(),
                "end_at": fields[3].strip(),
                "attendees": attendees,
                "source_ref": "calendar://QuaZe%20Demo/" + fields[0].strip(),
            }
        )

    return {"success": True, "events": events, "error": ""}


def _candidate_mcp_command() -> Optional[List[str]]:
    executable = shutil.which("mcp-server-filesystem")
    if executable:
        return [executable]

    node = shutil.which("node")
    if not node:
        return None

    module_path = Path(__file__).resolve().parent / "node_modules" / (
        "@modelcontextprotocol/server-filesystem/dist/index.js"
    )
    if module_path.is_file():
        return [node, str(module_path)]

    node_path = Path(node).resolve()
    global_path = (
        node_path.parent.parent
        / "lib"
        / "node_modules"
        / "@modelcontextprotocol"
        / "server-filesystem"
        / "dist"
        / "index.js"
    )
    if global_path.is_file():
        return [node, str(global_path)]
    return None


def discover_filesystem_mcp_command() -> Dict[str, object]:
    """Discover an already installed official filesystem MCP server."""

    command = _candidate_mcp_command()
    if command is None:
        return {
            "success": False,
            "command": [],
            "error": (
                "The official @modelcontextprotocol/server-filesystem server is "
                "not installed. Install it before selecting MCP mode."
            ),
        }
    return {"success": True, "command": command, "error": ""}


def _write_message(stdin: TextIO, message: Dict[str, object]) -> None:
    stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    stdin.flush()


def _read_response(
    stdout: TextIO,
    selector: selectors.BaseSelector,
    request_id: int,
    timeout_seconds: float = 10.0,
) -> Dict[str, object]:
    while True:
        ready = selector.select(timeout_seconds)
        if not ready:
            raise MCPProtocolError(
                "The filesystem MCP server timed out. Check its local installation."
            )
        line = stdout.readline()
        if not line:
            raise MCPProtocolError(
                "The filesystem MCP server closed before returning a response."
            )
        try:
            message = json.loads(line)
        except json.JSONDecodeError as exc:
            raise MCPProtocolError(
                "The filesystem MCP server returned malformed JSON."
            ) from exc
        if not isinstance(message, dict):
            raise MCPProtocolError(
                "The filesystem MCP server returned an invalid JSON-RPC message."
            )
        if message.get("id") != request_id:
            continue
        if "error" in message:
            error_value = message["error"]
            error_message = (
                str(error_value.get("message", "unknown MCP error"))
                if isinstance(error_value, dict)
                else "unknown MCP error"
            )
            raise MCPProtocolError(
                "The filesystem MCP server rejected a request: " + error_message
            )
        result = message.get("result")
        if not isinstance(result, dict):
            raise MCPProtocolError(
                "The filesystem MCP server returned a malformed result."
            )
        return result


def _tool_text(result: Dict[str, object]) -> str:
    if bool(result.get("isError", False)):
        raise MCPProtocolError("The filesystem MCP tool reported an error.")
    structured = result.get("structuredContent")
    if isinstance(structured, dict):
        structured_text = structured.get("content")
        if isinstance(structured_text, str):
            return structured_text
    content = result.get("content")
    if not isinstance(content, list):
        raise MCPProtocolError(
            "The filesystem MCP tool returned malformed content."
        )
    texts: List[str] = []
    for item in content:
        if isinstance(item, dict) and item.get("type") == "text":
            text_value = item.get("text")
            if isinstance(text_value, str):
                texts.append(text_value)
    if not texts:
        raise MCPProtocolError(
            "The filesystem MCP tool returned no readable text content."
        )
    return "\n".join(texts)


def _call_tool(
    stdin: TextIO,
    stdout: TextIO,
    selector: selectors.BaseSelector,
    request_id: int,
    name: str,
    arguments: Dict[str, object],
) -> Dict[str, object]:
    _write_message(
        stdin,
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        },
    )
    return _read_response(stdout, selector, request_id)


def _validate_mcp_allowed_root(allowed_text: str, expected_root: Path) -> None:
    allowed_lines = [
        line.strip()
        for line in allowed_text.splitlines()
        if line.strip() and line.strip() != "Allowed directories:"
    ]
    resolved_allowed: List[Path] = []
    for line in allowed_lines:
        try:
            resolved_allowed.append(Path(line).resolve(strict=True))
        except (FileNotFoundError, OSError):
            continue
    if resolved_allowed != [expected_root]:
        raise MCPProtocolError(
            "The filesystem MCP server did not confirm the dedicated demo vault "
            "as its only allowed directory."
        )


def mcp_vault_notes() -> Dict[str, object]:
    """Read demo notes through the official stdio filesystem MCP server."""

    command = _candidate_mcp_command()
    if command is None:
        return {
            "success": False,
            "notes": [],
            "error": (
                "The official @modelcontextprotocol/server-filesystem server is "
                "not installed. Safe direct-filesystem fallback is available."
            ),
        }

    try:
        root = _demo_vault_root()
    except (FileNotFoundError, OSError) as exc:
        return {"success": False, "notes": [], "error": str(exc)}

    process: Optional[subprocess.Popen[str]] = None
    selector: Optional[selectors.BaseSelector] = None
    try:
        process = subprocess.Popen(
            command + [str(root)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        if process.stdin is None or process.stdout is None:
            raise MCPProtocolError(
                "The filesystem MCP server did not expose stdio pipes."
            )
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)

        _write_message(
            process.stdin,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": _MCP_PROTOCOL_VERSION,
                    "capabilities": {},
                    "clientInfo": {"name": "quaze", "version": "0.1.0"},
                },
            },
        )
        _read_response(process.stdout, selector, 1)
        _write_message(
            process.stdin,
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
        )

        _write_message(
            process.stdin,
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        )
        tools_result = _read_response(process.stdout, selector, 2)
        tools_value = tools_result.get("tools")
        if not isinstance(tools_value, list):
            raise MCPProtocolError(
                "The filesystem MCP server returned a malformed tool list."
            )
        tool_names = {
            str(tool["name"])
            for tool in tools_value
            if isinstance(tool, dict) and isinstance(tool.get("name"), str)
        }
        if not _MCP_REQUIRED_TOOLS.issubset(tool_names):
            raise MCPProtocolError(
                "The filesystem MCP server is missing required read-only tools."
            )

        allowed_result = _call_tool(
            process.stdin,
            process.stdout,
            selector,
            3,
            "list_allowed_directories",
            {},
        )
        _validate_mcp_allowed_root(_tool_text(allowed_result), root)

        listing_result = _call_tool(
            process.stdin,
            process.stdout,
            selector,
            4,
            "list_directory",
            {"path": str(root)},
        )
        filenames = []
        for line in _tool_text(listing_result).splitlines():
            if not line.startswith("[FILE] "):
                continue
            name = line[len("[FILE] ") :].strip()
            if name.endswith(".md") and name != _GENERATED_BRIEF:
                filenames.append(name)

        notes: List[Dict[str, object]] = []
        next_id = 5
        for filename in sorted(filenames):
            path = _resolve_demo_vault_path(filename, must_exist=True)
            read_result = _call_tool(
                process.stdin,
                process.stdout,
                selector,
                next_id,
                "read_text_file",
                {"path": str(path)},
            )
            next_id += 1
            notes.append(
                {
                    "path": filename,
                    "title": path.stem,
                    "content": _tool_text(read_result),
                }
            )
        return {"success": True, "notes": notes, "error": ""}
    except (
        MCPProtocolError,
        OSError,
        subprocess.SubprocessError,
        ValueError,
    ) as exc:
        return {
            "success": False,
            "notes": [],
            "error": str(exc),
        }
    finally:
        if selector is not None:
            selector.close()
        if process is not None:
            if process.stdin is not None:
                process.stdin.close()
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)


def _write_target_path(relative_path: str) -> Path:
    if relative_path != _GENERATED_BRIEF:
        raise ValueError(
            "QuaZe may access only fixtures/demo-vault/Tomorrow Brief.md."
        )
    return _demo_vault_root() / _GENERATED_BRIEF


def _read_regular_file_nofollow(path: Path) -> bytes:
    if path.is_symlink():
        raise UnsafeArtifactTargetError(
            "Tomorrow Brief.md must not be a symbolic link."
        )
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        raise UnsafeArtifactTargetError(
            "Tomorrow Brief.md could not be opened without following links."
        ) from exc
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise UnsafeArtifactTargetError(
                "Tomorrow Brief.md exists but is not a regular file."
            )
        with os.fdopen(descriptor, "rb", closefd=False) as handle:
            return handle.read()
    finally:
        os.close(descriptor)


def inspect_vault_artifact(relative_path: str = _GENERATED_BRIEF) -> Dict[str, object]:
    """Read the bounded write target without following a final symlink."""

    try:
        target = _write_target_path(relative_path)
        if not os.path.lexists(target):
            return {
                "success": True,
                "exists": False,
                "content": "",
                "content_hash": "absent",
                "error": "",
                "error_code": "",
            }
        content = _read_regular_file_nofollow(target)
        return {
            "success": True,
            "exists": True,
            "content": content.decode("utf-8"),
            "content_hash": hashlib.sha256(content).hexdigest(),
            "error": "",
            "error_code": "",
        }
    except (OSError, UnicodeError, ValueError) as exc:
        return {
            "success": False,
            "exists": False,
            "content": "",
            "content_hash": "",
            "error": str(exc),
            "error_code": "unsafe_target",
        }


def save_vault_artifact(
    relative_path: str,
    content: str,
    expected_prior_hash: str = "",
) -> Dict[str, object]:
    """Write one bounded artifact after checking the approved prior hash."""

    if relative_path != _GENERATED_BRIEF:
        return {
            "success": False,
            "path": "",
            "content_hash": "",
            "created": False,
            "write_state": "",
            "error": "QuaZe may save only fixtures/demo-vault/Tomorrow Brief.md.",
            "error_code": "invalid_target",
        }

    try:
        target = _write_target_path(relative_path)
        encoded = content.encode("utf-8")
        content_hash = hashlib.sha256(encoded).hexdigest()
        target_existed = os.path.lexists(target)
        existing_hash = (
            hashlib.sha256(_read_regular_file_nofollow(target)).hexdigest()
            if target_existed
            else "absent"
        )
        if not expected_prior_hash or existing_hash != expected_prior_hash:
            return {
                "success": False,
                "path": "",
                "content_hash": "",
                "created": False,
                "write_state": "",
                "error": "The write target changed after review.",
                "error_code": "target_changed",
            }
        if existing_hash == content_hash:
            return {
                "success": True,
                "path": "fixtures/demo-vault/Tomorrow Brief.md",
                "content_hash": content_hash,
                "created": False,
                "write_state": "no_change",
                "error": "",
                "error_code": "",
            }

        temporary_path = ""
        try:
            with tempfile.NamedTemporaryFile(
                mode="wb",
                dir=str(target.parent),
                prefix=".Tomorrow Brief.",
                suffix=".tmp",
                delete=False,
            ) as temporary:
                temporary_path = temporary.name
                temporary.write(encoded)
                temporary.flush()
                os.fsync(temporary.fileno())
            current_hash = (
                hashlib.sha256(_read_regular_file_nofollow(target)).hexdigest()
                if os.path.lexists(target)
                else "absent"
            )
            if current_hash != expected_prior_hash:
                return {
                    "success": False,
                    "path": "",
                    "content_hash": "",
                    "created": False,
                    "write_state": "",
                    "error": "The write target changed after review.",
                    "error_code": "target_changed",
                }
            os.replace(temporary_path, target)
            temporary_path = ""
        finally:
            if temporary_path and os.path.exists(temporary_path):
                os.unlink(temporary_path)

        return {
            "success": True,
            "path": "fixtures/demo-vault/Tomorrow Brief.md",
            "content_hash": content_hash,
            "created": not target_existed,
            "write_state": "update" if target_existed else "create",
            "error": "",
            "error_code": "",
        }
    except UnsafeArtifactTargetError as exc:
        return {
            "success": False,
            "path": "",
            "content_hash": "",
            "created": False,
            "write_state": "",
            "error_code": "unsafe_target",
            "error": str(exc),
        }
    except (OSError, ValueError) as exc:
        return {
            "success": False,
            "path": "",
            "content_hash": "",
            "created": False,
            "write_state": "",
            "error_code": "write_failed",
            "error": (
                "Tomorrow Brief.md could not be saved inside the dedicated "
                "demo vault: " + str(exc)
            ),
        }


def open_obsidian_artifact(
    relative_path: str = _GENERATED_BRIEF,
    launch_gui: bool = False,
) -> Dict[str, object]:
    """Best-effort Obsidian launch, disabled unless explicitly requested."""

    if not launch_gui:
        return {
            "success": False,
            "opened": False,
            "error": "Obsidian launch is disabled for this run.",
        }
    try:
        target = _resolve_demo_vault_path(relative_path, must_exist=True)
    except (FileNotFoundError, OSError, ValueError) as exc:
        return {"success": False, "opened": False, "error": str(exc)}

    if not Path("/Applications/Obsidian.app").exists():
        return {
            "success": False,
            "opened": False,
            "error": "Obsidian is unavailable in /Applications.",
        }
    obsidian_uri = "obsidian://open?path=" + quote(str(target), safe="")
    try:
        completed = subprocess.run(
            ["/usr/bin/open", obsidian_uri],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except FileNotFoundError:
        return {
            "success": False,
            "opened": False,
            "error": "The macOS open command is unavailable.",
        }
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "opened": False,
            "error": "Obsidian did not open within 10 seconds.",
        }
    except OSError:
        return {
            "success": False,
            "opened": False,
            "error": "Obsidian could not be launched.",
        }
    if completed.returncode != 0:
        return {
            "success": False,
            "opened": False,
            "error": "macOS could not open the generated brief in Obsidian.",
        }
    return {"success": True, "opened": True, "error": ""}
