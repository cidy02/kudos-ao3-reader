# Kudos — Project Philosophy

This document is the canonical source of truth for Kudos's product direction,
engineering philosophy, design principles, contributor guidance, and AI-assisted
development. When a decision is unclear, this document — and the final principle at
the bottom — should guide it.

It is referenced from [`README.md`](../README.md) and [`AGENTS.md`](../AGENTS.md);
contributors (human or AI) should read it before making non-trivial changes.

---

## How This Project Started

Kudos started with two readers who wanted a better way to enjoy AO3 on mobile
devices.

One person built features. One person tested them relentlessly. Together they
shaped the experience they wished already existed.

Many of the project's values come directly from those origins:

- Reader-first design
- Respect for AO3 and OTW
- Privacy without compromise
- Open-source development
- Practical features over trends
- Thoughtful feedback over rapid growth

As the project grows, these principles should remain unchanged.

---

## Our Mission

Kudos exists to make reading on mobile devices a little nicer.

AO3 remains the archive, community, and source of truth.

Kudos is intended to complement AO3 by providing a native, privacy-respecting,
reader-focused experience.

---

## Core Principles

### Reader First

Every feature should improve the reading experience. Reading comes first.

### Respect AO3

Respect the Organization for Transformative Works and the volunteers who make AO3
possible. We improve the reading experience. We do not attempt to replace AO3.

### Browser-Equivalent Behavior

Kudos should behave like a respectful browser session, not a crawler. The
application should never generate significantly more AO3 traffic than a user
performing the same actions in Safari.

### Local First

Use local data whenever possible. Network requests should be the exception, not the
default.

### Privacy First

Users are readers, not products. Avoid:

- Advertising
- Tracking
- Telemetry
- Behavioral profiling
- Data harvesting

### Open Source By Default

Transparency builds trust.

### Community Before Monetization

The goal is useful software, not revenue. Contributions are welcome.

---

## Design Philosophy

### Information Dense

Useful information should remain visible. A cleaner design that hides important
information is often a regression.

### Native Apple Experience

On Apple platforms, Kudos should feel like a first-class Apple application. Prefer:

- SwiftUI
- Platform conventions
- Accessibility
- Dynamic Type
- Native controls

### Consistency Matters

Maintain consistency across cards, themes, typography, navigation, and reader UI.

### Accessibility Is Not Optional

Accessibility is a core feature.

---

## Engineering Philosophy

### Simplicity Over Cleverness

Readable code beats impressive code.

### Parallel When Helpful

Independent work should not block other work. Concurrency must remain bounded and
respectful.

### Cancel Unnecessary Work

If users leave a screen, stop work they no longer need.

### Cache Intelligently

Prefer cached data immediately, and refresh when needed.

### Test What Matters

Focus testing on user-facing reliability.

---

## AI-Assisted Development

AI tools may be used to assist development. The quality of a contribution is
determined by:

- Correctness
- Maintainability
- Testing
- Documentation
- User experience

All contributions should be reviewed according to the same standards.

---

## Final Principle

Whenever a decision is unclear, ask:

> "Does this make Kudos a better reading experience while respecting AO3, respecting
> user privacy, and respecting the community that made this possible?"

If the answer is yes, you are probably moving in the right direction.
