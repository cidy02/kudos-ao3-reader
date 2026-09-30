TASK: Library filter panel gets the AO3 filter panel's shell (spec 1an; finding L3-B1-8).
Today `LibraryFilterPanel` (Features/Library/LibraryFilterPanel.swift) is shown with `.inspector(isPresented:)`
from LibrarySectionListView, HomeSectionListView, LibraryView, ReadingQueueBrowser and Collections.swift. It has
no title bar and ends with a "Reset Filters" row. `AO3FilterPanel` (Features/Search/AO3FilterPanel.swift) is the
target: a NavigationStack with inline "Filters", Reset (arrow.counterclockwise, disabled when nothing is set) as
the cancellation item, a filled confirm (`.borderedProminent` + `.prominentLabel()`, checkmark here because Library
filters apply live) as the confirmation item, presented with `.filterPanelPresentation(isPresented:)` (grep it).
Do: (1) give LibraryFilterPanel that NavigationStack + toolbar and remove the bottom Reset row; (2) switch all five
call sites from `.inspector` to `.filterPanelPresentation`. A NavigationStack inside `.inspector` merges its bar
into the host screen on iPhone — that is why the presentation must change with it. Keep macOS building (the
presentation helper may differ there; check its definition). List the files you changed.
