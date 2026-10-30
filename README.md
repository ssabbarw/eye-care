# Eye Care

A lightweight macOS menu bar app that reminds you to take breaks, rest your eyes, stretch and exercise.

## Features

- **Schedules**
  - Every X minutes, counted from when you start it.
  - At fixed times of day, on chosen weekdays.
- **Alert styles**, each with an optional chime (14 system sounds):
  - Banner in the top-right corner with Done / Snooze. It auto-hides or stays until dismissed.
  - Native macOS notification with Done / Snooze actions.
  - Full-screen break on every display with a countdown and a suggested exercise. Skipping can be turned off.
- **Menu bar**: countdown to the next reminder, Take a Break Now, Pause (15 min to indefinitely), Restart All Timers.
- **General**: launch at login, active hours, snooze length, restart timers after the Mac wakes from sleep.
- Built-in suggestions for eye rest, stretching, exercise, posture and hydration.

## Requirements

macOS 13 or later, with Xcode or the Swift command-line tools.

## Build

```bash
./build.sh            # builds build/Eye Care.app
./build.sh --run      # builds and launches it
./build.sh --install  # builds, copies to /Applications and launches it
```

The app is ad-hoc signed. On another Mac, right-click it and choose **Open** the first time.

## Code layout

| File | Purpose |
| --- | --- |
| `Sources/EyeCare/EyeCareApp.swift` | App entry point, menu bar menu, settings window |
| `Sources/EyeCare/ReminderStore.swift` | Scheduling, pause/snooze, saving settings |
| `Sources/EyeCare/AlertPresenter.swift` | Banners, full-screen break windows, chime |
| `Sources/EyeCare/AlertViews.swift` | Banner and break screen views |
| `Sources/EyeCare/NotificationManager.swift` | Native macOS notifications |
| `Sources/EyeCare/SettingsView.swift` | Settings UI |
| `Sources/EyeCare/Models.swift`, `Exercises.swift` | Data model and exercise suggestions |
| `scripts/make-icon.swift` | Generates the app icon |
