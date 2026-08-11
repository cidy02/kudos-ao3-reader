# AO3 Behavior Contract

Status: Phase 0 skeleton. Android networking and parsing must match the current
Apple behavior unless a human-approved platform difference is documented.

## Reference Files

- `kudos-ao3-reader/Services/AO3Client.swift`
- `kudos-ao3-reader/Services/AO3RequestCoordinator.swift`
- `kudos-ao3-reader/Services/RequestCoalescer.swift`
- `kudos-ao3-reader/Services/AO3AuthService.swift`
- `kudos-ao3-reader/Services/AO3WriteActions.swift`
- `kudos-ao3-reader/Models/AO3Models.swift`
- `KudosTests/AO3ClientTests.swift`
- `KudosTests/SearchFiltersTests.swift`
- `KudosTests/AO3RequestCoordinatorTests.swift`
- `KudosTests/AO3WriteActionsTests.swift`

## Request Politeness

Current Apple behavior:

- Browser-like User-Agent.
- GET requests retry only transient failures.
- HTTP 429 respects `Retry-After`.
- HTTP 5xx is retryable.
- HTTP 404 and other non-429 4xx responses are not retried.
- Parser errors are not retried.
- Auth-required errors are not retried as normal network failures.
- State-changing POSTs are never auto-retried or coalesced.

Current `AO3RequestCoordinator` default is 3 request slots. Android should match
that default unless the human explicitly approves a stricter Android policy.

Identical concurrent GETs should coalesce to one network request. POSTs must not
coalesce.

## Search URL Contract

Search path:

```text
https://archiveofourown.org/works/search
```

Known query parameters:

```text
work_search[query]
work_search[fandom_names]
work_search[character_names]
work_search[relationship_names]
work_search[freeform_names]
work_search[rating_ids]
work_search[archive_warning_ids][]
work_search[category_ids][]
work_search[crossover]
work_search[complete]
work_search[word_count]
work_search[revised_at]
work_search[language_id]
work_search[sort_column]
page
```

Empty/blank values are omitted. `page` is 1-based and current Apple search
includes `page=1`.

Word-count expression:

- from + to: `from-to`
- from only: `> from`
- to only: `< to`
- neither: omitted

## Current Search Sort Enum

Current Apple enum cases and AO3 mapping:

| Enum | `sort_column` |
|---|---|
| `relevance` | omitted |
| `dateUpdated` | `revised_at` |
| `datePosted` | `created_at` |
| `words` | `word_count` |
| `kudos` | `kudos_count` |
| `hits` | `hits` |
| `comments` | `comments_count` |
| `bookmarks` | `bookmarks_count` |

Do not add `title` or `author` as AO3 sort options unless the Apple
implementation and AO3 mapping change first.

## Account URLs

Current account-list URL patterns:

```text
/users/<username>/readings?show=to-read
/users/<username>/readings
/users/<username>/subscriptions?type=works
/users/<username>/bookmarks
/users/<username>/works
/users/<username>/collections
```

Subscriptions use `?type=works` and parse the subscriptions `<dl>` page, not
`li.work.blurb` search markup.

## Parser Contract

Android should use Jsoup and produce domain DTOs equivalent to SwiftSoup output.
Parsers should be tolerant of optional missing elements but should not silently
turn AO3 overload/capacity pages into empty results.

Initial parser functions:

- `parseSearchPage(html, page)`
- `parseWorkSummary(element)`
- `parseWorkTags(html)`
- `parseBookmarksPage(html, page)`
- `parseSubscriptionsPage(html, page)`
- `parseCSRFToken(html)`
- `parseSeriesPage(html)`
- `parseAccountUsername(html)`

## Write Safety

For kudos, comments, subscriptions, Mark for Later, and AO3 bookmarks:

- Fetch the relevant AO3 page/form first.
- Parse the current CSRF token.
- Submit exactly one user-initiated POST.
- Do not retry POST automatically.
- Detect login redirects and prompt for re-authentication.
- Do not fake success.
