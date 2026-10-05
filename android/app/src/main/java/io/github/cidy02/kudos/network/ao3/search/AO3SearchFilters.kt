package io.github.cidy02.kudos.network.ao3.search

import java.time.LocalDate
import kotlinx.serialization.json.JsonElement

data class AO3SearchFilters(
    val query: String = "",
    val fandom: String = "",
    val characters: String = "",
    val relationships: String = "",
    val additionalTags: String = "",
    val excludedFandoms: String = "",
    val excludedCharacters: String = "",
    val excludedRelationships: String = "",
    val excludedAdditionalTags: String = "",
    val rating: AO3Rating = AO3Rating.ANY,
    val ratingMatch: AO3RatingMatch = AO3RatingMatch.EXACT,
    val includeNotRated: Boolean = true,
    val warnings: Set<AO3Warning> = emptySet(),
    val excludedWarnings: Set<AO3Warning> = emptySet(),
    val categories: Set<AO3Category> = emptySet(),
    val excludedCategories: Set<AO3Category> = emptySet(),
    val crossover: AO3Crossover = AO3Crossover.ANY,
    val completion: AO3Completion = AO3Completion.ANY,
    val wordsFrom: String = "",
    val wordsTo: String = "",
    val updated: AO3Updated = AO3Updated.ANY,
    val language: AO3Language = AO3Language.ANY,
    val sort: AO3SearchSort = AO3SearchSort.RELEVANCE,
    val sortDirection: AO3SortDirection = AO3SortDirection.DESCENDING,
    val chapterCount: AO3ChapterCount = AO3ChapterCount.ANY,
    val title: String = "",
    val creators: String = "",
    val hitsFrom: String = "",
    val hitsTo: String = "",
    val kudosFrom: String = "",
    val kudosTo: String = "",
    val commentsFrom: String = "",
    val commentsTo: String = "",
    val bookmarksFrom: String = "",
    val bookmarksTo: String = "",
    val dateFrom: LocalDate? = null,
    val dateTo: LocalDate? = null,
    /** Imported values not representable by these controls; retained across ordinary copy edits. */
    val preservedFilterValues: Map<String, PreservedSearchFilterValue> = emptyMap()
) {
    val hasActiveFilters: Boolean
        get() = fandom.isNotBlank() ||
            characters.isNotBlank() ||
            relationships.isNotBlank() ||
            additionalTags.isNotBlank() ||
            excludedFandoms.isNotBlank() ||
            excludedCharacters.isNotBlank() ||
            excludedRelationships.isNotBlank() ||
            excludedAdditionalTags.isNotBlank() ||
            rating != AO3Rating.ANY ||
            !includeNotRated ||
            warnings.isNotEmpty() ||
            excludedWarnings.isNotEmpty() ||
            categories.isNotEmpty() ||
            excludedCategories.isNotEmpty() ||
            crossover != AO3Crossover.ANY ||
            completion != AO3Completion.ANY ||
            wordsFrom.isNotBlank() ||
            wordsTo.isNotBlank() ||
            updated != AO3Updated.ANY ||
            language != AO3Language.ANY ||
            sort != AO3SearchSort.RELEVANCE ||
            sortDirection != AO3SortDirection.DESCENDING ||
            chapterCount != AO3ChapterCount.ANY ||
            title.isNotBlank() || creators.isNotBlank() ||
            hitsFrom.isNotBlank() || hitsTo.isNotBlank() ||
            kudosFrom.isNotBlank() || kudosTo.isNotBlank() ||
            commentsFrom.isNotBlank() || commentsTo.isNotBlank() ||
            bookmarksFrom.isNotBlank() || bookmarksTo.isNotBlank() ||
            dateFrom != null || dateTo != null || preservedFilterValues.isNotEmpty()

    val isSearchable: Boolean
        get() = query.isNotBlank() || hasActiveFilters

    /**
     * Excluded tags no longer appear here. They used to be folded in as `-"tag"`
     * phrases, which was wrong in two ways and unsafe in a third:
     *
     *  - **Wrong axis.** A quoted phrase matches summary and title text as well as
     *    tags, so it removed works that merely *mention* the words. Measured on one
     *    corpus of 92,495 works, excluding "Time Travel" + "Fluff" leaves 74,261
     *    through the tag field and 73,419 through phrase syntax — 842 works dropped
     *    that carry neither tag.
     *  - **No canonical resolution.** otwarchive turns a *recognised* excluded name
     *    into `term_filter(:filter_ids, id)` against the work's canonical filter
     *    tags, so synonyms and sub-tags go too. Phrase syntax gets none of that.
     *  - **Unescaped interpolation.** `-"$it"` put user text straight into query
     *    syntax, so a tag containing a double quote (AO3 allows it) closed the
     *    phrase early and the rest of the query became garbage.
     *
     * All three disappear by using AO3's own `excluded_tag_names` field
     * ([excludedTagNames]) — the endpoint accepts it even though the *form* has no
     * exclusion input. Warnings and categories stay here because AO3 offers no
     * structured exclusion field for them, and they are enum ids, not user text.
     */
    val searchQuery: String
        get() {
            val clauses = mutableListOf<String>()
            query.trim().takeIf { it.isNotEmpty() }?.let(clauses::add)
            clauses += AO3Warning.entries
                .filter(excludedWarnings::contains)
                .map { "-archive_warning_ids:${it.ao3Id}" }
            clauses += AO3Category.entries
                .filter(excludedCategories::contains)
                .map { "-category_ids:${it.ao3Id}" }
            ratingSearchClause()?.let(clauses::add)
            return clauses.joinToString(" ")
        }

    /**
     * The four excluded-tag fields as AO3's own `work_search[excluded_tag_names]`
     * — a comma-separated list, verified live to accept more than one name.
     *
     * The comma convention matches AO3's: otwarchive splits this field with
     * `options[field].split(",").map(&:squish)`, the same rule
     * [commaSeparatedValues] applies here, so both sides agree. A tag whose own
     * name contains a comma is therefore inexpressible — it was equally
     * inexpressible through the old phrase route, which also split on commas first.
     *
     * null when nothing is excluded, so the parameter is omitted entirely.
     */
    val excludedTagNames: String?
        get() = excludedTags().takeIf { it.isNotEmpty() }?.joinToString(",")

    val structuredRatingId: String?
        get() {
            val ratings = selectedRatings()
            return ratings.singleOrNull()?.ao3Id
        }

    private fun excludedTags(): List<String> {
        return listOf(
            excludedFandoms,
            excludedCharacters,
            excludedRelationships,
            excludedAdditionalTags
        ).flatMap(::commaSeparatedValues).dedupeFirstSeen()
    }

    private fun ratingSearchClause(): String? {
        if (rating == AO3Rating.ANY) {
            return if (includeNotRated) null else "-rating_ids:${AO3Rating.NOT_RATED.ao3Id}"
        }

        val ratings = selectedRatings()
        if (ratings.size <= 1) return null
        return ratings.joinToString(
            separator = " OR ",
            prefix = "(",
            postfix = ")"
        ) { "rating_ids:${it.ao3Id}" }
    }

    private fun selectedRatings(): List<AO3Rating> {
        if (rating == AO3Rating.ANY) return emptyList()
        if (rating == AO3Rating.NOT_RATED) return listOf(AO3Rating.NOT_RATED)

        val ranked = listOf(
            AO3Rating.GENERAL,
            AO3Rating.TEEN,
            AO3Rating.MATURE,
            AO3Rating.EXPLICIT
        )
        val index = ranked.indexOf(rating)
        if (index < 0) return emptyList()

        val selected = when (ratingMatch) {
            AO3RatingMatch.EXACT -> ranked.subList(index, index + 1)
            AO3RatingMatch.OR_HIGHER -> ranked.subList(index, ranked.size)
            AO3RatingMatch.OR_LOWER -> ranked.subList(0, index + 1)
        }.toMutableList()

        if (includeNotRated) selected += AO3Rating.NOT_RATED
        return selected
    }

    companion object {
        fun commaSeparatedValues(field: String): List<String> {
            return field.split(",")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
        }
    }
}

enum class AO3Rating(
    val appleCaseName: String,
    val title: String,
    val ao3Id: String?
) {
    ANY("any", "Any rating", null),
    GENERAL("general", "General Audiences", "10"),
    TEEN("teen", "Teen And Up", "11"),
    MATURE("mature", "Mature", "12"),
    EXPLICIT("explicit", "Explicit", "13"),
    NOT_RATED("notRated", "Not Rated", "9");

    companion object {
        val searchCases = listOf(ANY, GENERAL, TEEN, MATURE, EXPLICIT)
    }
}

enum class AO3RatingMatch(val appleCaseName: String, val title: String) {
    EXACT("exact", "Exact"),
    OR_HIGHER("orHigher", "Rating+"),
    OR_LOWER("orLower", "Rating-")
}

enum class AO3Warning(val appleCaseName: String, val ao3Id: String, val title: String) {
    NO_WARNINGS("noWarnings", "16", "No Archive Warnings Apply"),
    CHOOSE_NOT_TO("chooseNotTo", "14", "Creator Chose Not To Use Archive Warnings"),
    VIOLENCE("violence", "17", "Graphic Depictions Of Violence"),
    DEATH("death", "18", "Major Character Death"),
    NON_CON("nonCon", "19", "Rape/Non-Con"),
    UNDERAGE("underage", "20", "Underage Sex")
}

enum class AO3Category(val appleCaseName: String, val ao3Id: String, val title: String) {
    FF("ff", "116", "F/F"),
    FM("fm", "22", "F/M"),
    GEN("gen", "21", "Gen"),
    MM("mm", "23", "M/M"),
    MULTI("multi", "2246", "Multi"),
    OTHER("other", "24", "Other")
}

enum class AO3Crossover(val appleCaseName: String, val title: String, val ao3Value: String?) {
    ANY("any", "Include", null),
    EXCLUDE("exclude", "Exclude crossovers", "F"),
    ONLY("only", "Only crossovers", "T")
}

enum class AO3Completion(val appleCaseName: String, val title: String, val ao3Value: String?) {
    ANY("any", "All", null),
    COMPLETE("complete", "Complete", "T"),
    IN_PROGRESS("inProgress", "In Progress", "F")
}

enum class AO3Updated(val appleCaseName: String, val title: String, val ao3Value: String?) {
    ANY("any", "Any time", null),
    WEEK("week", "Past week", "< 1 week ago"),
    MONTH("month", "Past month", "< 1 month ago"),
    SIX_MONTHS("sixMonths", "Past 6 months", "< 6 months ago"),
    YEAR("year", "Past year", "< 1 year ago")
}

// iOS AO3SearchFilters.Language.rawList, native labels and order verbatim.
// Existing enum names / appleCaseName aliases remain readable by the unchanged saved-search codec.
enum class AO3Language(val appleCaseName: String, val title: String, val code: String?) {
    ANY("any", "Any language", null),
    SO("so", "af Soomaali", "so"),
    AFR("afr", "Afrikaans", "afr"),
    AIN("ain", "Aynu itak | アイヌ イタㇰ", "ain"),
    AKK("akk", "𒀝𒅗𒁺𒌑", "akk"),
    ARABIC("arabic", "العربية", "ar"),
    AMH("amh", "አማርኛ", "amh"),
    EGY("egy", "𓂋𓏺𓈖 𓆎𓅓𓏏𓊖", "egy"),
    OJI("oji", "Anishinaabemowin", "oji"),
    ARC("arc", "ܐܪܡܝܐ | ארמיא", "arc"),
    HY("hy", "հայերեն", "hy"),
    ASE("ase", "American Sign Language", "ase"),
    AST("ast", "asturianu", "ast"),
    AZJ("azj", "Azərbaycan dili | آذربایجان دیلی", "azj"),
    INDONESIAN("indonesian", "Bahasa Indonesia", "id"),
    MS("ms", "Bahasa Malaysia", "ms"),
    BG("bg", "Български", "bg"),
    BN("bn", "বাংলা", "bn"),
    JV("jv", "Basa Jawa", "jv"),
    SUN("sun", "ᮘᮞ ᮞᮥᮔ᮪ᮓ | Basa Sunda", "sun"),
    BA("ba", "Башҡорт теле", "ba"),
    BE("be", "беларуская", "be"),
    BAR("bar", "Boarisch", "bar"),
    BOS("bos", "Bosanski", "bos"),
    BR("br", "Brezhoneg", "br"),
    BFI("bfi", "British Sign Language", "bfi"),
    BUA("bua", "Буряад хэлэн | ᠪᠤᠷᠢᠶᠠᠳ ᠮᠣᠩᠭᠣᠯ ᠬᠡᠯᠡ", "bua"),
    CA("ca", "Català", "ca"),
    CEB("ceb", "Cebuano", "ceb"),
    CS("cs", "Čeština", "cs"),
    CHN("chn", "Chinuk Wawa", "chn"),
    CRH("crh", "къырымтатар тили | qırımtatar tili", "crh"),
    CY("cy", "Cymraeg", "cy"),
    DA("da", "Dansk", "da"),
    GERMAN("german", "Deutsch", "de"),
    DIV("div", "ދިވެހި,", "div"),
    ET("et", "eesti keel", "et"),
    EL("el", "Ελληνικά", "el"),
    SUX("sux", "𒅴𒂠", "sux"),
    ENGLISH("english", "English", "en"),
    ANG("ang", "Eald Englisċ", "ang"),
    SPANISH("spanish", "Español", "es"),
    EO("eo", "Esperanto", "eo"),
    EU("eu", "Euskara", "eu"),
    FA("fa", "فارسی", "fa"),
    FILIPINO("filipino", "Filipino", "fil"),
    CHA("cha", "Finuʼ Chamorro", "cha"),
    FRENCH("french", "Français", "fr"),
    FRR("frr", "Friisk", "frr"),
    FRY("fry", "Frysk", "fry"),
    FUR("fur", "Furlan", "fur"),
    GA("ga", "Gaeilge", "ga"),
    GD("gd", "Gàidhlig", "gd"),
    GL("gl", "Galego", "gl"),
    GOT("got", "𐌲𐌿𐍄𐌹𐍃𐌺𐌰", "got"),
    GYN("gyn", "Creolese", "gyn"),
    HAK("hak", "中文-客家话", "hak"),
    KOREAN("korean", "한국어", "ko"),
    HAU("hau", "Hausa | هَرْشَن هَوْسَ", "hau"),
    HINDI("hindi", "हिन्दी", "hi"),
    MWW("mww", "Hmoob dawb", "mww"),
    HR("hr", "Hrvatski", "hr"),
    HAW("haw", "ʻŌlelo Hawaiʻi", "haw"),
    IA("ia", "Interlingua", "ia"),
    ZU("zu", "isiZulu", "zu"),
    IS("is", "Íslenska", "is"),
    ITALIAN("italian", "Italiano", "it"),
    HE("he", "עברית", "he"),
    KAL("kal", "Kalaallisut", "kal"),
    XAL("xal", "Хальмг Өөрдин келн", "xal"),
    MOH("moh", "Kanienʼkéha", "moh"),
    KAN("kan", "ಕನ್ನಡ", "kan"),
    KAT("kat", "ქართული", "kat"),
    COR("cor", "Kernewek", "cor"),
    KHM("khm", "ភាសាខ្មែរ", "khm"),
    QKZ("qkz", "Khuzdul", "qkz"),
    SW("sw", "Kiswahili", "sw"),
    HT("ht", "kreyòl ayisyen", "ht"),
    KU("ku", "Kurdî | کوردی", "ku"),
    KIR("kir", "Кыргызча", "kir"),
    LAD("lad", "Ladino / לאדינו", "lad"),
    FCS("fcs", "Langue des signes québécoise", "fcs"),
    LV("lv", "Latviešu valoda", "lv"),
    LB("lb", "Lëtzebuergesch", "lb"),
    LT("lt", "Lietuvių kalba", "lt"),
    LA("la", "Lingua latina", "la"),
    HU("hu", "Magyar", "hu"),
    MK("mk", "македонски", "mk"),
    ML("ml", "മലയാളം", "ml"),
    MT("mt", "Malti", "mt"),
    MNC("mnc", "ᠮᠠᠨᠵᡠ ᡤᡳᠰᡠᠨ", "mnc"),
    QMD("qmd", "Mando'a", "qmd"),
    MR("mr", "मराठी", "mr"),
    MIC("mic", "Mi'kmaq", "mic"),
    ENM("enm", "Middel Englisch", "enm"),
    MIK("mik", "Mikisúkî", "mik"),
    HNJ("hnj", "Moob leeg", "hnj"),
    MON("mon", "ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ᠌ | Монгол Кирилл үсэг", "mon"),
    MY("my", "မြန်မာဘာသာ", "my"),
    MYV("myv", "Эрзянь кель", "myv"),
    QNV("qnv", "Lìʼfya leNaʼvi", "qnv"),
    NAH("nah", "Nāhuatl", "nah"),
    NAN("nan", "中文-闽南话 臺語", "nan"),
    PPL("ppl", "Nawat", "ppl"),
    DUTCH("dutch", "Nederlands", "nl"),
    JAPANESE("japanese", "日本語", "ja"),
    NO("no", "Norsk", "no"),
    CE("ce", "Нохчийн мотт", "ce"),
    OOD("ood", "O'odham Ñiok", "ood"),
    OTA("ota", "لسان عثمانى", "ota"),
    PS("ps", "پښتو", "ps"),
    PDC("pdc", "Pennsilfaanisch Deitsch", "pdc"),
    NDS("nds", "Plattdüütsch", "nds"),
    POLISH("polish", "Polski", "pl"),
    PORTUGUESE("portuguese", "Português brasileiro", "ptBR"),
    PTPT("ptPT", "Português europeu", "ptPT"),
    FUC("fuc", "Pulaar", "fuc"),
    PA("pa", "ਪੰਜਾਬੀ", "pa"),
    KAZ("kaz", "qazaqşa | қазақша", "kaz"),
    QLQ("qlq", "Uncategorized Constructed Languages", "qlq"),
    QYA("qya", "Quenya", "qya"),
    RO("ro", "Română", "ro"),
    ROM("rom", "RRomani Ćhib", "rom"),
    RUSSIAN("russian", "Русский", "ru"),
    SMI("smi", "Sámi", "smi"),
    SAH("sah", "саха тыла", "sah"),
    SCO("sco", "Scots", "sco"),
    SQ("sq", "Shqip", "sq"),
    SJN("sjn", "Sindarin", "sjn"),
    SI("si", "සිංහල", "si"),
    SK("sk", "Slovenčina", "sk"),
    SLV("slv", "Slovenščina", "slv"),
    SLA("sla", "Slověnьskъ Językъ", "sla"),
    GEM("gem", "Sprēkō Þiudiskō", "gem"),
    SR("sr", "Српски", "sr"),
    FI("fi", "suomi", "fi"),
    SV("sv", "Svenska", "sv"),
    TA("ta", "தமிழ்", "ta"),
    TAT("tat", "татар теле", "tat"),
    MRI("mri", "te reo Māori", "mri"),
    TEL("tel", "తెలుగు", "tel"),
    TIR("tir", "ትግርኛ", "tir"),
    THAI("thai", "ไทย", "th"),
    TQX("tqx", "Thermian", "tqx"),
    BOD("bod", "བོད་སྐད་", "bod"),
    VIETNAMESE("vietnamese", "Tiếng Việt", "vi"),
    COP("cop", "ϯⲙⲉⲧⲣⲉⲙⲛ̀ⲭⲏⲙⲓ", "cop"),
    TLH("tlh", "tlhIngan-Hol", "tlh"),
    TOK("tok", "toki pona", "tok"),
    TRF("trf", "Trinidadian Creole", "trf"),
    TSD("tsd", "τσακώνικα", "tsd"),
    CHR("chr", "ᏣᎳᎩ ᎦᏬᏂᎯᏍᏗ", "chr"),
    TURKISH("turkish", "Türkçe", "tr"),
    UK("uk", "Українська", "uk"),
    ALE("ale", "Unangam Tunuu", "ale"),
    URD("urd", "اُردُو", "urd"),
    UIG("uig", "ئۇيغۇر تىلى", "uig"),
    VOL("vol", "Volapük", "vol"),
    WUU("wuu", "中文-吴语", "wuu"),
    YI("yi", "יידיש", "yi"),
    YUA("yua", "maayaʼ tʼàan", "yua"),
    YUE("yue", "中文-广东话 粵語", "yue"),
    CHINESE("chinese", "中文-普通话 國語", "zh");
}

enum class AO3SearchSort(
    val appleCaseName: String,
    val title: String,
    val sortColumn: String?
) {
    RELEVANCE("relevance", "Best Match", null),
    CREATOR("creator", "Creator", "authors_to_sort_on"),
    TITLE("workTitle", "Title", "title_to_sort_on"),
    DATE_UPDATED("dateUpdated", "Date Updated", "revised_at"),
    DATE_POSTED("datePosted", "Date Posted", "created_at"),
    WORDS("words", "Word Count", "word_count"),
    KUDOS("kudos", "Kudos", "kudos_count"),
    HITS("hits", "Hits", "hits"),
    COMMENTS("comments", "Comments", "comments_count"),
    BOOKMARKS("bookmarks", "Bookmarks", "bookmarks_count");

    val naturalDirection: AO3SortDirection
        get() = if (this == CREATOR || this == TITLE) AO3SortDirection.ASCENDING else AO3SortDirection.DESCENDING
}

enum class AO3SortDirection(val appleCaseName: String, val title: String, val ao3Value: String) {
    DESCENDING("descending", "Descending", "desc"),
    ASCENDING("ascending", "Ascending", "asc")
}

enum class AO3ChapterCount(val appleCaseName: String, val title: String, val ao3Value: String?) {
    ANY("any", "Any", null),
    SINGLE_CHAPTER("singleChapter", "Single Chapter Only", "1")
}

internal fun Iterable<String>.dedupeFirstSeen(): List<String> {
    val seen = linkedSetOf<String>()
    forEach { value ->
        if (value.isNotBlank()) seen += value.trim()
    }
    return seen.toList()
}

/** Codec-only preservation metadata. Neither member is written as a new JSON key. */
data class PreservedSearchFilterValue(
    val raw: JsonElement,
    val decoded: JsonElement?
)
