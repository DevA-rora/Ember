import Foundation

/// Hardcoded calendar context until EventKit integration is implemented.
enum CalendarFixture {
    static let seed = """
    ## Today's schedule (fixture)

    Calendar not connected — using sample data for development.

    - 08:00–08:45 — School (Period 1)
    - 12:30–13:00 — Lunch
    - 14:00–15:30 — Math class
    - 16:30–17:00 — Dentist appointment
    - 19:00–20:00 — Family dinner (fixed)

    Open work windows: before 14:00, 13:00–14:00, after 17:00 until dinner.
    """
}
