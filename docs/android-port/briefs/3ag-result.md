# Brief 3ag result: the search filter sheet

**Landing note (Claude, 2026-10-04).** Landed as written, both passes. Gate green (1,363 tests).
Seen on the emulator: the sheet top to bottom in Light, Refine on Bookmarks and a fandom's works
in Dark, the sort and fandom pickers, Save Search, and the largest text size in Light and Dark.
Added on landing: `CrossPlatformRestoreTest.androidWritesASavedSearchsFiltersTheWayIosDoes`
(Android's own writer against a saved search that iOS wrote: the same 37 keys and values), and
the Library filter panel's Done is now iOS's accent-filled circle. Two differences from iOS are
left: the language picker opens as a second sheet where iOS slides it in inside the sheet, and
the tag picker has no "popular in this fandom" list (iOS fetches one from AO3; Android suggests
tags from the library). Not checked: a real search against AO3, since the demo never reaches it.

| Control (iOS order) | iOS filter field / availability | Android before | Android after / other side |
|---|---|---|---|
| Reset filters; Apply filters / Done | Host callbacks; Search / Refine | Both icon actions, filled Material chrome | Plain sheet header; iOS confirm treatment |
| Filters / Refine; live page match line | Mode; loaded-page counts | Both | Preserved |
| Sort by | `sort`; Search only | 8 chip choices; no Creator or Title | 10 iOS choices, whole-row picker |
| Order | `sortDirection`; Search except Best Match | Absent | Descending / Ascending |
| Rating | `rating`; both | Chips | Whole-row picker; same 5 choices |
| Match | `ratingMatch`; both when rating specific | Chips | Whole-row picker; Exact / Rating+ / Rating- |
| Include Not Rated | `includeNotRated`; both | Material switch | Subject toggle |
| Warnings | `warnings`, `excludedWarnings`; both | Three-state chips, all 6 | Three-state rows, all 6 |
| Categories | `categories`, `excludedCategories`; both | Three-state chips, all 6 | Three-state rows, all 6 |
| Crossovers | `crossover`; Search only | Chips | Whole-row picker |
| Completion | `completion`; both | Chips | Whole-row picker |
| Chapters | `chapterCount`; both | Absent (3w gap) | Any / Single Chapter Only |
| Updated | `updated`; Search only | Chips | Whole-row picker |
| After / Before | `dateFrom`, `dateTo`; Search only | Absent | Optional date bounds |
| Language | `language`; both | 19 languages + Any, chips | Searchable iOS native-name catalog |
| Fandoms | `fandom`, `excludedFandoms`; both (host may hide) | Separate include/exclude outlined fields | Whole-row picker, cycling selected tags |
| Characters | `characters`, `excludedCharacters`; both | Same | Same three-state picker |
| Relationships | `relationships`, `excludedRelationships`; both | Same | Same three-state picker |
| Additional Tags | `additionalTags`, `excludedAdditionalTags`; both | Same, heading “Additional tags” | Same three-state picker |
| Title / Creator | `title`, `creators`; Search only | Absent | Plain fields |
| Word count: slider + From / To | `wordsFrom`, `wordsTo`; both | Numeric outlined fields, no slider (3w gap) | Dual-handle slider plus plain numeric fields |
| Hits: slider + From / To | `hitsFrom`, `hitsTo`; Search only | Absent | Added |
| Kudos: slider + From / To | `kudosFrom`, `kudosTo`; Search only | Absent | Added |
| Comments: slider + From / To | `commentsFrom`, `commentsTo`; Search only | Absent | Added |
| Bookmarks: slider + From / To | `bookmarksFrom`, `bookmarksTo`; Search only | Absent | Added |
| Save Search… | Host callback; Search with onSave | Outlined bottom button | Plain action row at end |
| Close | Dismiss; Android Search only | Outlined bottom button; iOS has no row | Retained plain action row |
| Library tag suggestions; arbitrary comma-separated tag entry | Android picker data / tag fields | Available; iOS uses AO3 suggestions | Retained alongside cycling choices |

Comparison made before implementation, from the actual source in `/Users/cidy02/kudos-ios-polish` and this worktree. Implementation and verification notes follow below.

## Implementation and caller behavior

SearchFilterSheet.kt now uses the same sheet ground, gutters, header typography,
subjectPanel groups, SubjectFormRow pickers, separators, and SubjectToggle as
LibraryFilterPanel.kt and AO3CollectionsFilterPanel.kt. Notes are 12 sp / 17 sp.
The header stays outside the scrollable form. There are no Material FilterChips,
OutlinedTextFields, OutlinedButtons, or text-filled Buttons in this sheet or its
new pickers.

iOS wins where this brief's description and source differ:

- AO3FilterPanel.swift:196–208 explicitly gives the primary action an
  accent-filled circular background. Android keeps that treatment on the
  confirm icon; Reset is plain. The old rounded text Done button is absent.
- TagSelectField.swift:54–64 and 384–407 draw selected tags as tappable capsules.
  Android uses custom capsules with plus/minus icons and excluded strikethrough,
  rather than Material chips. Warning/category rows use the include background,
  Include/Exclude labels, and strikethrough in AO3FilterPanel.swift:545–579.
- FilterLanguagePicker.swift's comment says 82 languages, but the actual
  AO3Models.swift:1064–1107 catalog has 162 plus Any. The actual catalog wins.
- Fandoms is hidden on the fixed-fandom Browse host, following
  NativeBrowseView.swift:229–237. It remains on Search, general tag works,
  and account Refine.

SearchView.swift:635–651 binds filters, uses runSearch for Apply, preserves the
query on Reset, and supplies Save. Android SearchScreen.kt retains those
callbacks and its existing saved-search flow.

NativeBrowseView.swift:418–429 and 684–697 search on Apply and reload the
baseline on Reset. Android's FandomWorksScreen.kt and TagWorksScreen.kt previously
loaded through LaunchedEffect(subject, filters), so every facet tap could search.
They now load initially on subject changes, on Apply, on Reset/clear, and through
their existing pagination/retry actions. A picker tap prepares the filters.
Fandom's baseline still uses Date Updated and excludes Best Match from its menu;
its Reset enablement compares with that baseline.

AO3AccountWorksList.swift:333–350 supplies mode refine, a loaded-page source,
match/pending counts, and a dismiss-only Done. Android AccountWorksListScreen.kt
is unchanged: its Marked for Later, Bookmarks, History, and Subscriptions hosts
still filter the loaded page immediately, retain page order and the live
matching/pending line, and dismiss on Done. Refine hides Sort/Order, Crossovers,
Updated, After/Before, Title/Creator and engagement ranges. It exposes Chapters
and Word count, as iOS does. It passes no autocomplete repository; the shared
sheet additionally prevents passing one into any Refine tag picker.

The tag picker retains Android's library suggestions, arbitrary typed tags
(including comma-separated entry), and its existing AO3 autocomplete repository
when Search/Fandom supply it. Repeated taps now cycle include → exclude → clear
in both result rows and selected capsules. No new popular-tag endpoint was
introduced; Android's library suggestions remain its opening suggestions.
Existing autocomplete is debounced and cancellation-checked. No request was
dispatched during this work.

## New facets and source / URL contract

All iOS paths in this section are under /Users/cidy02/kudos-ios-polish/kudos-ao3-reader.
All parameters are emitted by Android's existing appendWorkSearchParams, shared
by buildSearchUrl and buildFandomWorksUrl.

| Facet | iOS lines followed | URL parameter / values | Refine |
|---|---|---|---|
| Creator / Title sort columns | Models/AO3Models.swift:1139–1183 | work_search[sort_column] = authors_to_sort_on / title_to_sort_on | Hidden, no local reorder |
| Order | Features/Search/AO3FilterPanel.swift:252–263; Models/AO3Models.swift:1187–1210; Services/AO3Client.swift:533–542 | work_search[sort_direction] = desc / asc, only with an explicit sort column | Hidden |
| Chapters | Features/Search/AO3FilterPanel.swift:327–333; Models/AO3Models.swift:968–985; Services/AO3Client.swift:512 | work_search[single_chapter] = 1; Any omits it | AO3SummaryFilter.swift:63–71: only 1/1 passes; 1/? fails; text without exactly two slash-separated parts stays visible |
| Title / Creator fields | Features/Search/AO3FilterPanel.swift:406–418; Services/AO3Client.swift:489–490 | work_search[title] / work_search[creators], trimmed text; separate from query | Hidden and ignored |
| Word slider | Features/Search/AO3FilterPanel.swift:422–429; Features/Search/FilterRangeSlider.swift:39–102, 153–237, 240–244 | Existing work_search[word_count]; no new parameter | Local inclusive word bounds, unknown words retained |
| Hits | Features/Search/AO3FilterPanel.swift:439–446; Services/AO3Client.swift:516 | work_search[hits] | Hidden and ignored |
| Kudos | Features/Search/AO3FilterPanel.swift:448–455; Services/AO3Client.swift:517 | work_search[kudos_count] | Hidden and ignored |
| Comments | Features/Search/AO3FilterPanel.swift:457–464; Services/AO3Client.swift:518–521 | work_search[comments_count] | Hidden and ignored |
| Bookmarks | Features/Search/AO3FilterPanel.swift:466–477; Services/AO3Client.swift:522–525 | work_search[bookmarks_count] | Hidden and ignored |
| After / Before | Features/Search/AO3FilterPanel.swift:356–369, 529–542; Services/AO3Client.swift:529–530 | work_search[date_from] / work_search[date_to], yyyy-MM-dd; null omits the parameter | Hidden and ignored |
| Full language picker | Features/Search/FilterLanguagePicker.swift:20–74; Models/AO3Models.swift:1064–1107 | Existing work_search[language_id], iOS's native-label catalog and codes | Matches summary language text, case-insensitively |

All five numeric axes use AO3Models.swift:698–709: two bounds are lower-upper,
one lower bound is > lower, one upper bound is < upper, and no bounds omit the
parameter. Default slider domains are respectively 200,000 / 1,000,000 /
50,000 / 10,000 / 10,000 (FilterRangeSlider.swift:240–244). Open edges clear
the bound. Typed values can expand the domain; ASCII digit validation and
saturating arithmetic prevent overflow. The drag domain stays fixed through
a gesture and resets on completion/cancellation. Android's native RangeSlider
handles gestures/accessibility, with a custom 4 dp track and 22 dp white thumbs.
The From/To fields retain exact typed values; Float slider precision is coarse
for exceptionally large counts, so precise entry remains available.

Optional dates use LocalDate and the native Android date picker. The selected
calendar day goes directly into the URL without an intervening UTC conversion.
Updated and both absolute bounds coexist; the iOS note explains their AND rule.

AO3SearchFilters.hasActiveFilters / isSearchable and SearchFilterHelpers'
summary labels and badge count now include the new fields. Query generation,
warning/category cycling, rating side effects and existing tag-exclusion
parameters remain on their existing paths.

The optional iOS author-works-only worksSort overlay is outside these four
Android hosts: it provides a separate Sort and filter title, nine works-index
columns, Direction, and server-side Completion with “AO3 applies this choice
to all matching works, not only the page you can see.” It is not substituted
for account Refine; that would violate this brief's no-search Refine contract.

## Preserved Android-only controls

- Close: still a dismiss row in Search/Browse; iOS has no bottom Close row.
- Library tag suggestions: still available in all four callers.
- Arbitrary comma-separated typed tag entry: now exposes each typed tag as a
  cycling result instead of separate Include/Exclude text fields.

## Saved-search codec: complete iOS filter JSON

The owner's follow-up authorizes the additive keys already written by iOS.
SearchFiltersCodec.kt now writes all 37 AO3SearchFilters CodingKeys using iOS's
exact names and encodings. Save Search works for all known facets; its temporary
disablement, explanatory note, and the test pinning that restriction were removed.
No Room schema, backup container/version, sync-folder layout, signing, or
TASKS.md changed.

Read from the read-only iOS lane:

- Models/AO3Models.swift:211–273: every stored filter and CodingKey.
  AO3SearchFilters has a custom init(from:) at 329–381 that supplies defaults for
  absent/null keys. It has no custom encode(to:); Swift synthesizes encoding from
  CodingKeys and omits nil optional dates.
- Models/AO3Models.swift:714–787, 790–803, 805–916, 918–1016, 1018–1212:
  enum values, Warning/Category custom Codable, Language's stored id and custom
  backward-compatible decoder, and sort/direction values.
- Services/KudosBackup.swift:1228–1248: KudosBackupSavedSearch stores id, name,
  dateAdded, and filters: AO3SearchFilters with synthesized Codable. It copies
  savedSearch.filters directly; no field whitelist or alternate filter DTO.
- Services/KudosBackup.swift:472–473, 515–537: encodeManifest uses
  KudosBackupContents.makeEncoder. Its custom date encoder writes ISO-8601
  internet date/time with fractional seconds (UTC, e.g.
  2024-01-31T00:30:00.123Z). outputFormatting is prettyPrinted + sortedKeys.
  No keyEncodingStrategy is set: default literal CodingKey names remain intact.
- Services/KudosBackup.swift:562–578: the backup decoder accepts fractional and
  whole-second ISO timestamps and applies clampedArchiveDate. This codec carries
  saved-filter JSON, rather than replacing Android's archive restore logic.

### Every iOS key, JSON type, and value

These are keys within savedSearch.filters, not the saved-search wrapper.
Every non-date key is encoded even at its default. Dates are omitted when nil;
iOS's decoder also accepts explicit null as nil. Empty strings are valid and
signify unset text/range inputs. Ranges are strings, never JSON numbers.

| Key | iOS JSON type | Values / default |
|---|---|---|
| query | string | Free text; default empty string |
| title | string | AO3 title text; default empty string |
| creators | string | Creator/pseud text; default empty string |
| fandom | string | Comma-separated included fandom names; default empty string |
| characters | string | Comma-separated included character names; default empty string |
| relationships | string | Comma-separated included relationship names; default empty string |
| additionalTags | string | Comma-separated included freeform names; default empty string |
| excludedFandoms | string | Comma-separated excluded fandom names; default empty string |
| excludedCharacters | string | Comma-separated excluded character names; default empty string |
| excludedRelationships | string | Comma-separated excluded relationship names; default empty string |
| excludedAdditionalTags | string | Comma-separated excluded freeform names; default empty string |
| rating | string | any (default), general, teen, mature, explicit, notRated |
| ratingMatch | string | exact (default), orHigher, orLower |
| includeNotRated | boolean | true (default) / false |
| warnings | array of strings | Set of noWarnings, chooseNotTo, violence, death, nonCon, underage; default [] |
| excludedWarnings | array of strings | Same warning case names; default [] |
| categories | array of strings | Set of ff, fm, gen, mm, multi, other; default [] |
| excludedCategories | array of strings | Same category case names; default [] |
| crossover | string | any (default), exclude, only |
| completion | string | any (default), complete, inProgress |
| chapterCount | string | any (default), singleChapter |
| wordsFrom | string | Raw lower word-count bound; default empty string |
| wordsTo | string | Raw upper word-count bound; default empty string |
| hitsFrom | string | Raw lower hits bound; default empty string |
| hitsTo | string | Raw upper hits bound; default empty string |
| kudosFrom | string | Raw lower kudos bound; default empty string |
| kudosTo | string | Raw upper kudos bound; default empty string |
| commentsFrom | string | Raw lower comments bound; default empty string |
| commentsTo | string | Raw upper comments bound; default empty string |
| bookmarksFrom | string | Raw lower bookmarks bound; default empty string |
| bookmarksTo | string | Raw upper bookmarks bound; default empty string |
| updated | string | any (default), week, month, sixMonths, year |
| dateFrom | optional ISO-8601 timestamp string | Absolute Date; fractional seconds in backup/sync JSON; omitted by encoder when nil |
| dateTo | optional ISO-8601 timestamp string | Same date encoding and optionality as dateFrom |
| language | object with string id | Current encoding {"id":"fr"}; default {"id":""}; any AO3 code in the 162-language table below, or a future/unknown id string |
| sort | string | relevance (default), creator, workTitle, dateUpdated, datePosted, words, kudos, hits, comments, bookmarks |
| sortDirection | string | descending (default), ascending |

Warning's Swift raw values are numeric-ID **strings**, but its custom encoder
writes case names: noWarnings = "16", chooseNotTo = "14", violence = "17",
death = "18", nonCon = "19", underage = "20". Category does the same:
ff = "116", fm = "22", gen = "21", mm = "23", multi = "2246", other = "24".
Both iOS and Android decode the case names and the legacy string IDs; new
Android values use case names. These are distinct from the URL's ID parameters.

Language's only stored property and only CodingKey is id. Its title is derived.
iOS currently encodes an object, accepts the intermediate id/title object,
and accepts legacy bare-code strings. Android also reads its own historic
case-name strings such as "french". Imported legacy shapes and additional
object members are preserved as supplied; new Android selections encode
the current {"id":code} shape.

### Lossless edits and tolerant decoding

The codec reads a JsonObject and decodes each field independently, replacing
the old all-or-nothing DTO decode. A malformed string, boolean, date, enum,
language, or set falls back only for that field; known set members remain usable.
The raw value survives alongside its decoded value in
AO3SearchFilters.preservedFilterValues whenever canonical encoding cannot
represent it exactly. This metadata is not written as extra JSON keys.
Ordinary copy edits in the existing SearchViewModel and sheet retain it.

On encode, unchanged decoded fields reuse their original JSON value. Unknown
future keys have no native field and therefore survive unchanged. This keeps
unknown enum/language values, malformed values, legacy representations, array
ordering, and the full precision/time of imported date timestamps. Changing a
known control writes its new canonical value; clearing a known date removes its
key. Editing warning/category selections preserves members Android cannot
recognize, while honoring removal of known members. Explicit Reset creates
fresh filters and intentionally clears the retained values.

Every current iOS key is represented by an Android field. The non-picker rating
value notRated still encodes and decodes correctly. Unsupported future filters
are retained for a decoder that understands them; Android does not invent
query behavior for unknown keys.

### Exact-match limits

- JSON value/key preservation is the contract, not byte-for-byte formatting.
  Android writes compact JSON; iOS pretty-prints and sorts object keys.
  Swift Set iteration order is unspecified; newly created Android sets are
  sorted for stable output, while imported array order is retained.
- Android's panel holds LocalDate, whereas iOS holds a Date with a time.
  Imported timestamps are retained unchanged through unrelated edits.
  A newly chosen/changed Android date is local start-of-day, encoded as a UTC
  ISO timestamp with three fractional digits. The calendar day used in AO3's
  date_from/date_to URL remains the selected local day. Android cannot recover
  an iOS time-of-day after the reader replaces that date, because its date
  control exposes no time. This is the only current domain precision mismatch.
- Unknown or malformed values are preserved even when today's decoder cannot
  apply them. A raw value is reused while that field's decoded value is unchanged.
  Missing/default fields may be added during encoding, just as iOS's synthesized
  encoder writes defaults. A full 37-key iOS object round-trips key-for-key.

## User-visible strings before → after

Group labels are now drawn uppercase by SubjectFieldLabel; their source
strings retain iOS's spelling and capitalization. Runtime tag names, numeric
values, date values, counts and user-entered text remain data.

| Before | After |
|---|---|
| Filters; Refine; Reset filters; Apply filters; Done | Unchanged |
| Sort by; Rating; Match; Include Not Rated; Warnings; Categories; Crossovers; Completion; Updated; Language; Tags; Fandoms; Characters; Relationships; Word count; From; To; Close; Save Search… | Unchanged source strings |
| Additional tags | Additional Tags |
| Exclude fandoms; Exclude characters; Exclude relationships; Exclude additional tags | Replaced by the corresponding tag picker plus Exclude state |
| + {warning/category}; − {warning/category} | {warning/category} plus Include / Exclude status and icon; excluded text struck through |
| Tap once to include, twice to exclude, third to clear. (Warnings and Categories) | Removed redundant footers; the rows identify their state |
| Comma-separated. Suggestions come from your library and AO3. Use Exclude fields for −"tag" query clauses. | Tap a tag once to include it, twice to exclude it, and a third time to clear it. |
| Crossover option: Exclude | Exclude crossovers |
| Summary: Crossover: Exclude; Crossover: Only crossovers | Exclude crossovers; Only crossovers |
| — | Order; Descending; Ascending |
| — | Creator; Title (sort options and fields); Title & creator |
| — | Chapters; Any; Single Chapter Only |
| — | After; Before |
| — | Hits; Kudos; Comments; Bookmarks (range group headings; previously only sort options) |
| — | Any (empty numeric bound); Range (slider accessibility name) |
| — | Include; Exclude; Clear (selection state/accessibility) |
| — | {n} included; {n} excluded; {n} included · {n} excluded; Any (tag-row summaries) |
| — | Included: {tag}; Excluded: {tag}; Tap to include this tag; Tap to exclude this tag; Tap to clear this tag |
| — | Selected; Results; Searching… |
| — | Search Fandoms; Search Characters; Search Relationships; Search Additional Tags |
| — | Type above to search AO3 fandoms.; Type above to search AO3 characters.; Type above to search AO3 relationships.; Type above to search AO3 additional tags. |
| — | No tags found for “{query}”. |
| — | Search 162 languages |
| — | Title: {title}; By: {creators}; Single Chapter Only (summary labels) |
| Words {from}–{to}; Words ≥ {from}; Words ≤ {to} | Unchanged; the same templates now also apply to Hits, Kudos, Comments, Bookmarks |
| — | After {yyyy-MM-dd}; Before {yyyy-MM-dd} (summary labels) |
| {matching} of the {total} {work/works} on this page {matches/match}; · {pending} not checked yet | Unchanged live Refine line and pending suffix |
| Any rating; General Audiences; Teen And Up; Mature; Explicit; Not Rated | Unchanged rating names (Not Rated controlled by the toggle) |
| Exact; Rating+; Rating- | Unchanged |
| No Archive Warnings Apply; Creator Chose Not To Use Archive Warnings; Graphic Depictions Of Violence; Major Character Death; Rape/Non-Con; Underage Sex | Unchanged |
| F/F; F/M; Gen; M/M; Multi; Other | Unchanged |
| Include; Only crossovers | Unchanged crossover options |
| All; Complete; In Progress | Unchanged completion options |
| Any time; Past week; Past month; Past 6 months; Past year | Unchanged updated options |
| Best Match; Date Updated; Date Posted; Word Count; Kudos; Hits; Comments; Bookmarks | Unchanged sort options; Creator and Title added |
| No Not Rated; Sort: {sort}; {rating}+; {rating}−; −{tag/warning/category} | Unchanged summary templates |
| — | When you change crossover status, Kudos runs a new AO3 search because each result doesn't include it. |
| — | The Updated, After, and Before choices all use the work's update date. A work appears only if it matches every date choice. |
| — | Leave either end of the slider at its starting position if you don't want a minimum or maximum. AO3 treats one-sided ranges as “more than” or “fewer than”. |

The standard Android modal drag handle, native date-picker system actions,
IME labels, and dropdown accessibility are supplied by the platform. The
language table below enumerates every language label before and after,
including unchanged Any/English/Filipino and every newly available native name.

| AO3 code | Before | After (iOS verbatim) |
|---|---|---|
| unset | Any language | Any language |
| so | — | af Soomaali |
| afr | — | Afrikaans |
| ain | — | Aynu itak \| アイヌ イタㇰ |
| akk | — | 𒀝𒅗𒁺𒌑 |
| ar | Arabic | العربية |
| amh | — | አማርኛ |
| egy | — | 𓂋𓏺𓈖 𓆎𓅓𓏏𓊖 |
| oji | — | Anishinaabemowin |
| arc | — | ܐܪܡܝܐ \| ארמיא |
| hy | — | հայերեն |
| ase | — | American Sign Language |
| ast | — | asturianu |
| azj | — | Azərbaycan dili \| آذربایجان دیلی |
| id | Indonesian | Bahasa Indonesia |
| ms | — | Bahasa Malaysia |
| bg | — | Български |
| bn | — | বাংলা |
| jv | — | Basa Jawa |
| sun | — | ᮘᮞ ᮞᮥᮔ᮪ᮓ \| Basa Sunda |
| ba | — | Башҡорт теле |
| be | — | беларуская |
| bar | — | Boarisch |
| bos | — | Bosanski |
| br | — | Brezhoneg |
| bfi | — | British Sign Language |
| bua | — | Буряад хэлэн \| ᠪᠤᠷᠢᠶᠠᠳ ᠮᠣᠩᠭᠣᠯ ᠬᠡᠯᠡ |
| ca | — | Català |
| ceb | — | Cebuano |
| cs | — | Čeština |
| chn | — | Chinuk Wawa |
| crh | — | къырымтатар тили \| qırımtatar tili |
| cy | — | Cymraeg |
| da | — | Dansk |
| de | German | Deutsch |
| div | — | ދިވެހި, |
| et | — | eesti keel |
| el | — | Ελληνικά |
| sux | — | 𒅴𒂠 |
| en | English | English |
| ang | — | Eald Englisċ |
| es | Spanish | Español |
| eo | — | Esperanto |
| eu | — | Euskara |
| fa | — | فارسی |
| fil | Filipino | Filipino |
| cha | — | Finuʼ Chamorro |
| fr | French | Français |
| frr | — | Friisk |
| fry | — | Frysk |
| fur | — | Furlan |
| ga | — | Gaeilge |
| gd | — | Gàidhlig |
| gl | — | Galego |
| got | — | 𐌲𐌿𐍄𐌹𐍃𐌺𐌰 |
| gyn | — | Creolese |
| hak | — | 中文-客家话 |
| ko | Korean | 한국어 |
| hau | — | Hausa \| هَرْشَن هَوْسَ |
| hi | Hindi | हिन्दी |
| mww | — | Hmoob dawb |
| hr | — | Hrvatski |
| haw | — | ʻŌlelo Hawaiʻi |
| ia | — | Interlingua |
| zu | — | isiZulu |
| is | — | Íslenska |
| it | Italian | Italiano |
| he | — | עברית |
| kal | — | Kalaallisut |
| xal | — | Хальмг Өөрдин келн |
| moh | — | Kanienʼkéha |
| kan | — | ಕನ್ನಡ |
| kat | — | ქართული |
| cor | — | Kernewek |
| khm | — | ភាសាខ្មែរ |
| qkz | — | Khuzdul |
| sw | — | Kiswahili |
| ht | — | kreyòl ayisyen |
| ku | — | Kurdî \| کوردی |
| kir | — | Кыргызча |
| lad | — | Ladino / לאדינו |
| fcs | — | Langue des signes québécoise |
| lv | — | Latviešu valoda |
| lb | — | Lëtzebuergesch |
| lt | — | Lietuvių kalba |
| la | — | Lingua latina |
| hu | — | Magyar |
| mk | — | македонски |
| ml | — | മലയാളം |
| mt | — | Malti |
| mnc | — | ᠮᠠᠨᠵᡠ ᡤᡳᠰᡠᠨ |
| qmd | — | Mando'a |
| mr | — | मराठी |
| mic | — | Mi'kmaq |
| enm | — | Middel Englisch |
| mik | — | Mikisúkî |
| hnj | — | Moob leeg |
| mon | — | ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ᠌ \| Монгол Кирилл үсэг |
| my | — | မြန်မာဘာသာ |
| myv | — | Эрзянь кель |
| qnv | — | Lìʼfya leNaʼvi |
| nah | — | Nāhuatl |
| nan | — | 中文-闽南话 臺語 |
| ppl | — | Nawat |
| nl | Dutch | Nederlands |
| ja | Japanese | 日本語 |
| no | — | Norsk |
| ce | — | Нохчийн мотт |
| ood | — | O'odham Ñiok |
| ota | — | لسان عثمانى |
| ps | — | پښتو |
| pdc | — | Pennsilfaanisch Deitsch |
| nds | — | Plattdüütsch |
| pl | Polish | Polski |
| ptBR | Portuguese (BR) | Português brasileiro |
| ptPT | — | Português europeu |
| fuc | — | Pulaar |
| pa | — | ਪੰਜਾਬੀ |
| kaz | — | qazaqşa \| қазақша |
| qlq | — | Uncategorized Constructed Languages |
| qya | — | Quenya |
| ro | — | Română |
| rom | — | RRomani Ćhib |
| ru | Russian | Русский |
| smi | — | Sámi |
| sah | — | саха тыла |
| sco | — | Scots |
| sq | — | Shqip |
| sjn | — | Sindarin |
| si | — | සිංහල |
| sk | — | Slovenčina |
| slv | — | Slovenščina |
| sla | — | Slověnьskъ Językъ |
| gem | — | Sprēkō Þiudiskō |
| sr | — | Српски |
| fi | — | suomi |
| sv | — | Svenska |
| ta | — | தமிழ் |
| tat | — | татар теле |
| mri | — | te reo Māori |
| tel | — | తెలుగు |
| tir | — | ትግርኛ |
| th | Thai | ไทย |
| tqx | — | Thermian |
| bod | — | བོད་སྐད་ |
| vi | Vietnamese | Tiếng Việt |
| cop | — | ϯⲙⲉⲧⲣⲉⲙⲛ̀ⲭⲏⲙⲓ |
| tlh | — | tlhIngan-Hol |
| tok | — | toki pona |
| trf | — | Trinidadian Creole |
| tsd | — | τσακώνικα |
| chr | — | ᏣᎳᎩ ᎦᏬᏂᎯᏍᏗ |
| tr | Turkish | Türkçe |
| uk | — | Українська |
| ale | — | Unangam Tunuu |
| urd | — | اُردُو |
| uig | — | ئۇيغۇر تىلى |
| vol | — | Volapük |
| wuu | — | 中文-吴语 |
| yi | — | יידיש |
| yua | — | maayaʼ tʼàan |
| yue | — | 中文-广东话 粵語 |
| zh | Chinese | 中文-普通话 國語 |

## Tests and verification

Added 25 JUnit tests, with names aligned to the iOS suites where applicable:

| Android suite / test | iOS test or contract followed |
|---|---|
| network/ao3/search/SearchURLTests.rangeExpressionCoversBothBoundsAndNeither | SearchFiltersTests.rangeExpressionCoversBothBoundsAndNeither; asserts every numeric parameter on both Search and fandom URLs |
| SearchURLTests.titleAndCreatorUseTheirOwnFieldsNotTheFreeTextQuery | SearchURLTests of the same name; also checks chapter/date/window coexistence and blank omission on both URLs |
| SearchURLTests.sortSendsColumnAndDirectionTogether | Same iOS name; covers all sort/direction combinations on both URLs and natural directions |
| SearchURLTests.absoluteDateBoundsUseAO3sISOFormat | Same iOS name; selected LocalDate day is the exact ISO day in the built URL |
| SearchURLTests.facetedChoicesUseAO3sFlagValues | Same iOS name; crossover F, complete T, single_chapter 1 |
| SearchURLTests.everyNumericFieldUsesAO3sRangeGrammar | Same iOS name; mixed one-/two-sided ranges on all five axes |
| SearchURLTests.relevanceSortSendsNeitherColumnNorDirection | Same iOS name; remembered ascending cannot escape onto relevance |
| SearchURLTests.languageCatalogUsesIOSNativeNamesAndQueryIDs | iOS's language catalog and query IDs, including every entry |
| search/SearchFiltersTests.languageSearchFiltersByNativeNameAndKeepsAnyFirst | Same iOS name; case/diacritic-insensitive native-name and code matching |
| SearchFiltersTests.rangeSliderDomainExpandsPastTheDefaultMaximum | Same iOS name; open values, ASCII-only digits and expanded ceiling |
| SearchFiltersTests.rangeSliderClampsExtremeInput | iOS rangeSliderClampsExtremeInputAndOffTrackMovement's numeric-overflow contract; native slider owns off-track gesture clamping |
| SearchFiltersTests.tagSelectionCyclesIncludeExcludeClear | iOS TagSelectField.cycle and selectionSummary; sorted, disjoint three-state strings |
| SearchFiltersTests.everyNewFacetIsSearchableAndCounted | iOS hasActiveFilters, isSearchable and reset contract |
| search/AO3SummaryFilterTest.singleChapterMeansFinishedAtOne | AO3SummaryFilterRatingTests of the same name; additionally checks stable page ordering |
| AO3SummaryFilterTest.unreadableChapterTextDoesNotHideAWork | Same iOS name; also checks sparse subscription retention before metadata arrives |
| AO3SummaryFilterTest.queryOnlyFacetsDoNotNarrowLoadedPages | iOS AO3SummaryFilter.matchesSummary's available-field boundary; native-language refine |

SearchFiltersCodecTest now contains 17 tests (9 added in this follow-up).
Its current-language encoding test now asserts the actual iOS id object, not the
older Android bare-code output. The existing legacy-language decoder test remains.

| Added codec test | What it pins |
|---|---|
| everyIOSKeyRoundTripsItsExactJSONValue | Full 37-key non-default iOS JSON is equal after decode/encode, including array order and fractional timestamps; an unrelated query edit preserves the other 36 keys |
| eachAndroidFacetUsesIOSsKeyAndRawValue | Every added Android facet writes the iOS key/raw value; nil dates are omitted; native fields round-trip |
| anUnknownFutureKeySurvivesAnAndroidEdit | Nested future JSON survives a title edit |
| oneMalformedFieldNeverLosesTheOtherFields | Replaces each of all 37 fields with a malformed object in turn; defaults only that field and preserves the complete raw object |
| unrepresentableValuesAndLegacyFacetIDsRemainLossless | Future enums/languages, legacy warning/category IDs, unreadable array members, and numeric date values remain intact, including after editing a known set member |
| changingAControlReplacesOnlyItsPreservedValue | Changed/cleared date replaces/removes that bound while preserving the other bound's exact timestamp |
| everyLegacyLanguageShapeAlsoSurvivesResaving | Current id object, intermediate id/title object, bare code, historic Android alias, and unknown id object survive re-saving |
| androidDateBoundsKeepThePickedDayAcrossTimeZones | Exact timestamps in UTC+14, UTC−5, UTC+1; calendar day survives decode; original timezone restored in finally |
| valuesThePanelDoesNotExposeStillSaveAndOnlyExplicitResetClearsThem | notRated and future keys survive an ordinary edit; Reset explicitly clears them |

The existing SearchFilterHelpersTest crossover-summary assertion now expects
the actual iOS text, “Exclude crossovers”. Existing URL, rating, include/exclude,
codec (updated for current iOS language encoding), Refine count/pending, and subscription tests remain in place.

Performed only source/static verification:

- Read all four Android callers and the real models, repositories, codec,
  row/toggle/segmented components, normalization helpers and relevant tests.
- Read the referenced iOS panel, picker/slider/tag field, model/query builder,
  Search/Browse/account hosts, summary matcher, and iOS test suites.
- Inspected the installed Material3 1.4.0 class signatures for RangeSlider,
  its thumb/track slots, RangeSliderState and SliderDefaults without Gradle.
- Compared the copied language codes/labels/order with the iOS catalog.
- Static source audit confirms all 37 iOS CodingKeys appear exactly once in the
  codec encoder and in the complete JSON fixture. Read the iOS backup wrapper,
  date/key encoder strategy and filter Codable customizations.
- No Save restriction or unsupported-filter note remains in Android source.
- git diff --check passes. No TASKS.md, schema, backup container/version, signing or
  project/build configuration changes. No stub, helper script or .orig file.
- No Gradle build, unit test execution, emulator launch, login or AO3 request.
  Compilation and runtime correctness are not claimed; Claude runs the gates.
  Work remains uncommitted on android/agent-codex-3ag in this worktree.

Claude should run Android assemble and the unit suites above, plus the existing
AO3SearchUrlBuilderTest, AO3FandomWorksUrlTest, SearchFilterHelpersTest,
SearchFiltersCodecTest, AO3SummaryFilterTest, and account-list/privacy tests.
Use the repository's normal Android verification path; no live AO3 access
is needed for any of these URL/logic tests.

## Emulator review still required

Use demo/offline data and an existing locally supplied account-page fixture;
do not sign in or contact AO3 for this review. Repeat the following in Light,
Dark, and the largest supported font size (also verify keyboard-open layouts):

1. Search: open Filters; see header actions and the sections in the table's
   order. Verify whole-row choices, rating side effects, warning/category
   include → exclude → clear, and that long labels wrap. Verify Creator/Title
   sorts start Ascending, count/date sorts start Descending, and Best Match
   hides Order. Apply and Reset retain the host's existing behavior.
2. Search ranges: drag both handles, return each to its open edge, type exact
   bounds, type beyond the initial domain, cancel a drag, and paste oversized
   input. From/To remain editable and stack at accessibility scale. Verify the
   blank bound reads Any and no keyboard hides the header permanently.
3. Search dates/languages/tags: toggle each date on/off and change its calendar
   day; read both date/crossover notes. Open Language and search native names,
   diacritic-free text and codes; see the selection checkmark. Open each Tags
   picker, cycle result rows and selected capsules, type a new tag, and confirm
   the row's included/excluded counts. Verify library suggestions remain.
4. Save/Close: save and reload each new facet and a complete imported iOS search.
   Every facet remains available to Save; the old unsupported-filter note is gone.
   Change one field and re-save: untouched imported date timestamps and unknown
   filter values must survive. Close still dismisses.
5. A fandom's works: fixed Fandoms row is hidden; Best Match is absent; baseline
   Reset is disabled. Changing a facet alone does not initiate a request;
   Apply/Reset call the existing reload path. Review pagination/retry and
   baseline clear using an injected/offline repository.
6. General tag works: sheet still opens, new facets appear, Apply reloads page
   one, Reset restores the baseline, and the existing typed page refinement,
   selection and pagination continue to work.
7. Bookmarks Refine: live matching count changes immediately with rating, tags,
   words and Chapters; Done only dismisses. Sort/Order, crossover/date and
   engagement fields are absent. Repeated picker taps and Reset perform zero
   searches; order and the existing bookmark pills stay intact.
8. Other account lists: smoke History and Marked for Later; check Subscriptions'
   unknown rows and “not checked yet” suffix, then known 1/1 versus 1/? chapter
   metadata. Existing page scope, watermarks and mature-content handling remain.
9. Dark and largest text: verify included green versus excluded red, excluded
   strikethrough, readable 12 sp / 17 sp notes, stable action hit targets,
   stacked picker values and numeric fields, wrapping capsules, native
   date dialog, nested picker dismissal, and TalkBack's state/action labels
   and live match announcement. Capture screenshots for the human UI gate.
