import Foundation

/// Hardcoded session memory until Firestore `users/{uid}/memory/current` is implemented.
enum SessionMemoryFixture {
    static let seed = """
    ## Session memory (last 6 weeks)

    - Slipped on "Ember iOS app" three times when starting after 9pm; evening sessions rarely stick.
    - Prep checklist (clean desk, water, phone away) reliably helps transitions.
    - User prefers button taps over typing when reporting low energy or feeling numb.
    - Last session: chose Eisenhower urgent task "Firebase setup" over suggested "chat UI polish."
    - Math homework tends to get deferred until the day before it's due — flag when a school deadline is within 48 hours.
    - Short Pomodoro blocks (15 min) work better than open-ended "work until done."
    """
}
