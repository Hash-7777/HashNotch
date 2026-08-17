// HashNotch — your notch, made useful.
// Copyright (C) 2026 Seif Hashish
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import AppKit

// Run as an agent app: no Dock icon, no main window, no menu-bar item — just
// the notch overlay. `.accessory` keeps it out of the Dock and app switcher.
// The program starts on the main thread, so we assume main-actor isolation to
// wire up the app delegate and run the loop.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
