"""Jac policy layer for permission-gated macOS automation."""


obj MacActionPolicy {
    has app: str;
    has action: str;
    has risk: str;
    has requires_approval: bool;
    has reason: str = "";

    def to_dict() -> dict {
        return {
            "app": self.app,
            "action": self.action,
            "risk": self.risk,
            "requiresApproval": self.requires_approval,
            "reason": self.reason,
        };
    }
}


node MacActionNode {
    has app: str;
    has action: str;
    has params: dict = {};
}


walker MacControlWalker {
    has policies: list[MacActionPolicy] = [];
    has reports: list[list[MacActionPolicy]] = [];

    can begin with Root entry {
        visit [-->[?:MacActionNode]];
    }

    can inspect with MacActionNode entry {
        self.policies.append(classify_mac_action(here.app, here.action));
    }

    can finish with Root exit {
        report self.policies;
    }
}


def classify_mac_action(app: str, action: str) -> MacActionPolicy {
    app_name: str = app.strip();
    action_name: str = action.strip();
    key: str = f"{app_name.lower()}:{action_name.lower()}";

    destructive: set[str] = {
        "finder:delete", "finder:move", "finder:organize_by_extension",
        "terminal:exec_shell", "system:exec_shell",
    };
    external_side_effect: set[str] = {
        "calendar:create_event",
    };

    if key in destructive {
        return MacActionPolicy(
            app=app_name,
            action=action_name,
            risk="high",
            requires_approval=True,
            reason="This action changes files or executes an unrestricted local command.",
        );
    }
    if key in external_side_effect {
        return MacActionPolicy(
            app=app_name,
            action=action_name,
            risk="medium",
            requires_approval=True,
            reason="This action creates an externally visible side effect.",
        );
    }
    return MacActionPolicy(
        app=app_name,
        action=action_name,
        risk="low",
        requires_approval=False,
    );
}


def validate_mac_action(app: str, action: str) -> bool {
    allowed: dict[str, set[str]] = {
        "notes": {"create_note", "append_note", "search_notes"},
        "finder": {"list_files", "create_folder", "move", "organize_by_extension"},
        "mail": {"create_draft", "recent_messages"},
        "calendar": {"create_event", "list_events"},
        "system": {"display_notification", "set_volume"},
        "terminal": {"exec_shell"},
    };
    app_key: str = app.strip().lower();
    return app_key in allowed and action.strip().lower() in allowed[app_key];
}


import os;


obj MacActionResult {
    has success: bool;
    has output: dict;
    has error: str = "";
    has approval_required: bool = False;
    has risk: str = "low";

    def to_dict() -> dict {
        return {
            "success": self.success,
            "output": self.output,
            "error": self.error,
            "approvalRequired": self.approval_required,
            "risk": self.risk,
        };
    }

    @staticmethod
    def success_result(output: dict, risk: str) -> MacActionResult {
        return MacActionResult(
            success=True,
            output=output,
            error="",
            approval_required=False,
            risk=risk
        );
    }

    @staticmethod
    def failure_result(error: str, risk: str) -> MacActionResult {
        return MacActionResult(
            success=False,
            output={},
            error=error,
            approval_required=False,
            risk=risk
        );
    }

    @staticmethod
    def approval_result(reason: str, risk: str) -> MacActionResult {
        return MacActionResult(
            success=False,
            output={},
            error=reason,
            approval_required=True,
            risk=risk
        );
    }
}


def applescript_escape(value: str) -> str {
    """Escapes strings for AppleScript."""
    escaped: str = value.replace("\\", "\\\\");
    escaped = escaped.replace("\"", "\\\"");
    escaped = escaped.replace("\r", "\\r");
    escaped = escaped.replace("\n", "\\n");
    return escaped;
}


def html_escape(value: str) -> str {
    """Escapes basic HTML entities."""
    escaped: str = value.replace("&", "&amp;");
    escaped = escaped.replace("<", "&lt;");
    escaped = escaped.replace(">", "&gt;");
    escaped = escaped.replace("\"", "&quot;");
    escaped = escaped.replace("'", "&#x27;");
    escaped = escaped.replace("\n", "<br>");
    return escaped;
}


def string_param(params: dict, key: str, fallback: str) -> str {
    """Safely extracts a string parameter from a dict."""
    if key in params and isinstance(params[key], str) {
        return params[key];
    }
    return fallback;
}


def expand_home(path: str) -> str {
    """Expands ~/... paths."""
    return os.path.expanduser(path);
}


def build_create_note_script(title: str, content: str, folder: str) -> str {
    safe_title: str = applescript_escape(title);
    safe_content: str = applescript_escape(content);
    safe_folder: str = applescript_escape(folder);
    
    html_content: str = f"<h1>{html_escape(title)}</h1><p>{html_escape(content)}</p>";
    
    folder_cmd: str = "";
    if folder.strip() {
        folder_cmd = f"""
        if not (exists folder "{safe_folder}") then
            make new folder with properties {{name:"{safe_folder}"}}
        end if
        set theFolder to folder "{safe_folder}"
        """;
    } else {
        folder_cmd = "set theFolder to folder \"Notes\"";
    }
    
    return f"""
    tell application "Notes"
        {folder_cmd}
        make new note at theFolder with properties {{name:"{safe_title}", body:"{applescript_escape(html_content)}"}}
    end tell
    """;
}


def build_append_note_script(title: str, content: str) -> str {
    safe_title: str = applescript_escape(title);
    html_content: str = f"<br><p>{html_escape(content)}</p>";
    
    return f"""
    tell application "Notes"
        set targetNote to first note whose name is "{safe_title}"
        set body of targetNote to (body of targetNote) & "{applescript_escape(html_content)}"
    end tell
    """;
}


def build_search_notes_script(query: str) -> str {
    safe_query: str = applescript_escape(query);
    return f"""
    tell application "Notes"
        set foundNotes to notes whose name contains "{safe_query}" or body contains "{safe_query}"
        set noteList to {{}}
        repeat with n in foundNotes
            set end of noteList to name of n
        end repeat
        return noteList
    end tell
    """;
}


def build_notification_script(text: str, title: str, sound: str) -> str {
    safe_text: str = applescript_escape(text);
    safe_title: str = applescript_escape(title);
    safe_sound: str = applescript_escape(sound);
    sound_cmd: str = f' sound name "{safe_sound}"' if sound else "";
    return f'display notification "{safe_text}" with title "{safe_title}"{sound_cmd}';
}


def build_set_volume_script(volume: int) -> str {
    vol: int = volume;
    if vol < 0 { vol = 0; }
    if vol > 100 { vol = 100; }
    return f"set volume output volume {vol}";
}


def build_create_draft_script(recipient: str, subject: str, content: str) -> str {
    return f"""
    tell application "Mail"
        set newMessage to make new outgoing message with properties {{subject:"{applescript_escape(subject)}", content:"{applescript_escape(content)}", visible:true}}
        tell newMessage
            make new to recipient at end of to recipients with properties {{address:"{applescript_escape(recipient)}"}}
        end tell
    end tell
    """;
}


def build_recent_messages_script(limit: int) -> str {
    return f"""
    tell application "Mail"
        set recentMsgs to messages of inbox thru {limit}
        set msgList to {{}}
        repeat with m in recentMsgs
            set end of msgList to (subject of m as string)
        end repeat
        return msgList
    end tell
    """;
}


def build_create_event_script(title: str, start: str, end: str, calendar_name: str) -> str {
    cal: str = applescript_escape(calendar_name) if calendar_name else "Calendar";
    return f"""
    tell application "Calendar"
        set targetCal to calendar "{cal}"
        set startDate to date "{applescript_escape(start)}"
        set endDate to date "{applescript_escape(end)}"
        tell targetCal
            make new event with properties {{summary:"{applescript_escape(title)}", start date:startDate, end date:endDate}}
        end tell
    end tell
    """;
}


def build_list_events_script() -> str {
    return """
    tell application "Calendar"
        set today to current date
        set time of today to 0
        set tomorrow to today + (1 * days)
        set allEvents to {{}}
        repeat with cal in calendars
            set dailyEvents to (events of cal whose (start date >= today) and (start date < tomorrow))
            repeat with ev in dailyEvents
                set end of allEvents to (summary of ev as string)
            end repeat
        end repeat
        return allEvents
    end tell
    """;
}


def build_applescript(app: str, action: str, params: dict) -> str {
    """Dispatches to the correct builder based on app and action."""
    app_key: str = app.strip().lower();
    action_key: str = action.strip().lower();
    
    if app_key == "notes" {
        if action_key == "create_note" {
            return build_create_note_script(
                string_param(params, "title", "New Note"),
                string_param(params, "content", ""),
                string_param(params, "folder", "")
            );
        }
        if action_key == "append_note" {
            return build_append_note_script(
                string_param(params, "title", ""),
                string_param(params, "content", "")
            );
        }
        if action_key == "search_notes" {
            return build_search_notes_script(string_param(params, "query", ""));
        }
    }
    elif app_key == "system" {
        if action_key == "display_notification" {
            return build_notification_script(
                string_param(params, "text", ""),
                string_param(params, "title", "Notification"),
                string_param(params, "sound", "")
            );
        }
        if action_key == "set_volume" {
            vol: int = 50;
            if "volume" in params and isinstance(params["volume"], int) {
                vol = params["volume"];
            }
            return build_set_volume_script(vol);
        }
    }
    elif app_key == "mail" {
        if action_key == "create_draft" {
            return build_create_draft_script(
                string_param(params, "recipient", ""),
                string_param(params, "subject", ""),
                string_param(params, "content", "")
            );
        }
        if action_key == "recent_messages" {
            limit: int = 10;
            if "limit" in params and isinstance(params["limit"], int) {
                limit = params["limit"];
            }
            return build_recent_messages_script(limit);
        }
    }
    elif app_key == "calendar" {
        if action_key == "create_event" {
            return build_create_event_script(
                string_param(params, "title", "New Event"),
                string_param(params, "start", ""),
                string_param(params, "end", ""),
                string_param(params, "calendar", "")
            );
        }
        if action_key == "list_events" {
            return build_list_events_script();
        }
    }
    return "";
}


def validate_restricted_applescript(script: str) -> bool {
    """Validates that a raw script is safe (only Notes/notifications allowed, blocks shell escapes)."""
    s: str = script.lower();
    if "do shell script" in s {
        return False;
    }
    
    allowed_apps: list[str] = ["notes", "system events"];
    for line in script.split("\\n") {
        line = line.strip().lower();
        if line.startswith("tell application") {
            is_allowed: bool = False;
            for app in allowed_apps {
                if app in line {
                    is_allowed = True;
                    break;
                }
            }
            if not is_allowed {
                return False;
            }
        }
    }
    return True;
}
