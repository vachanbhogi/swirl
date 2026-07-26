"""Jac policy layer for permission-gated macOS automation.

Native AppleScript execution lives at the Tauri boundary. Keeping policy and
validation in Jac avoids importing Python-flavoured helpers that are not valid
Jac 0.34.7.
"""


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
        "mail": {"create_draft", "recent_messages", "wait_for_new_message"},
        "calendar": {"create_event", "list_events"},
        "system": {"display_notification", "set_volume"},
        "terminal": {"exec_shell"},
    };
    app_key: str = app.strip().lower();
    return app_key in allowed and action.strip().lower() in allowed[app_key];
}
