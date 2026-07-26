from typing import Dict


def resolve_vault_path(
    relative_path: str,
    must_exist: bool = ...,
) -> Dict[str, object]: ...


def tomorrow_window(reference_date: str = ...) -> Dict[str, object]: ...


def direct_vault_notes() -> Dict[str, object]: ...


def live_calendar_records(
    calendar_name: str = ...,
    reference_date: str = ...,
) -> Dict[str, object]: ...


def parse_calendar_output(output: str) -> Dict[str, object]: ...


def discover_filesystem_mcp_command() -> Dict[str, object]: ...


def mcp_vault_notes() -> Dict[str, object]: ...


def save_vault_artifact(
    relative_path: str,
    content: str,
) -> Dict[str, object]: ...


def open_obsidian_artifact(
    relative_path: str = ...,
    launch_gui: bool = ...,
) -> Dict[str, object]: ...
