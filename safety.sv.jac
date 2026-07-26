"""Deterministic public-message sanitization for connector and runtime errors."""

import re;


glob PUBLIC_MESSAGE_LIMIT: int = 500;


def sanitize_public_message(
    value: str, fallback: str = "The connector failed. Review its availability and retry."
) -> str {
    if not value.strip() {
        return fallback;
    }
    lowered = value.lower();
    if "mcp stderr" in lowered or "raw mcp" in lowered {
        return (
            "The connector reported an internal MCP transport error. "
            "Review connector availability and retry."
        );
    }
    sanitized = re.sub(
        r"(?i)bearer\s+[a-z0-9._~+/=-]+",
        "[credential redacted]",
        value
    );
    sanitized = re.sub(
        r"(?i)(token|api[_-]?key|secret|password|credential)\s*[:=]\s*\S+",
        r"\1=[redacted]",
        sanitized
    );
    sanitized = re.sub(r"https?://\S+", "[url redacted]", sanitized);
    sanitized = re.sub(
        (
            r"(?<![A-Za-z0-9._~-])/"
            r"(?:[A-Za-z0-9._~+@=-]+/)+"
            r"[A-Za-z0-9._~+@=-]+"
        ),
        "[path redacted]",
        sanitized
    );
    sanitized = re.sub(r"[\x00-\x1f\x7f]+", " ", sanitized);
    sanitized = re.sub(r"\s+", " ", sanitized).strip();
    if not sanitized {
        return fallback;
    }
    if len(sanitized) > PUBLIC_MESSAGE_LIMIT {
        return sanitized[:PUBLIC_MESSAGE_LIMIT].rstrip() + "…";
    }
    return sanitized;
}
