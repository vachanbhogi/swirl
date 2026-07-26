-- Create only QuaZe's dedicated synthetic Calendar data.
-- The runtime Calendar connector remains read-only.

on eventExists(targetCalendar, eventTitle, eventStart)
    tell application "Calendar"
        set windowEnd to eventStart + (1 * minutes)
        set matches to every event of targetCalendar whose summary is eventTitle and start date is greater than or equal to eventStart and start date is less than windowEnd
        return (count of matches) > 0
    end tell
end eventExists

tell application "Calendar"
    if not (exists calendar "QuaZe Demo") then
        set demoCalendar to make new calendar with properties {name:"QuaZe Demo"}
    else
        set demoCalendar to calendar "QuaZe Demo"
    end if

    set tomorrowStart to current date
    set tomorrowStart to tomorrowStart + (1 * days)
    set time of tomorrowStart to 0

    set apexStart to tomorrowStart + (9 * hours) + (30 * minutes)
    set apexEnd to apexStart + (45 * minutes)
    if not my eventExists(demoCalendar, "Apex design review", apexStart) then
        tell demoCalendar
            make new event with properties {summary:"Apex design review", start date:apexStart, end date:apexEnd, description:"Synthetic QuaZe demo meeting. No personal data."}
        end tell
    end if

    set mayaStart to tomorrowStart + (14 * hours)
    set mayaEnd to mayaStart + (45 * minutes)
    if not my eventExists(demoCalendar, "Maya onboarding", mayaStart) then
        tell demoCalendar
            make new event with properties {summary:"Maya onboarding", start date:mayaStart, end date:mayaEnd, description:"Synthetic QuaZe demo meeting. No personal data."}
        end tell
    end if

    return "QuaZe Demo is ready with tomorrow's synthetic meetings."
end tell
