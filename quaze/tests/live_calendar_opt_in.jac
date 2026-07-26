"""Opt-in QuaZe Demo Calendar check; run directly, never in the default suite."""

import from connectors { events_from_result, read_live_calendar }


with entry:__main__ {
    calendar_result = read_live_calendar();
    assert calendar_result.success , calendar_result.error;
    events = events_from_result(calendar_result);
    assert events;
    for event in events {
        assert event.source_ref.startswith("calendar://QuaZe%20Demo/");
    }
    print(calendar_result.evidence_summary);
}
