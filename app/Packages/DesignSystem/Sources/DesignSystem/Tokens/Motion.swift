// Motion.swift
//
// Animation tokens. Three durations cover the app: quick (tap feedback),
// standard (sheet transitions, cross-fades), slow (hero reveals). Curves match
// common iOS idiom — `.easeOut` for appearances, `.easeInOut` for transforms.

import SwiftUI

/// Animation tokens. Enum-as-namespace; access via `DSAnimation.quick`, etc.
///
/// Named against purpose, not just duration, so sites using a token read as
/// intent rather than a magic number. If a site needs a one-off curve, use a
/// custom `Animation` inline and note why — don't add a new token unless it's
/// reused in ≥2 places.
public enum DSAnimation {
    /// `0.15s ease-out`. Tap feedback, focus rings, chip selection.
    public static let quick: Animation = .easeOut(duration: 0.15)

    /// `0.25s ease-in-out`. Sheet dismissal, layout-change cross-fades,
    /// keypad key-press tint transitions.
    public static let standard: Animation = .easeInOut(duration: 0.25)

    /// `0.4s ease-out`. Hero reveals (autoreg banner slide-in, complete-screen
    /// summary). Reserve for one-shot, attention-drawing transitions.
    public static let slow: Animation = .easeOut(duration: 0.4)
}
