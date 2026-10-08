package io.github.cidy02.kudos.writing

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.font.FontWeight
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.subject.*

internal enum class WorkAssociation(val title: String) {
    Series("Series"), CollectionsGifts("Collections and gifts"), Creators("Co-creators"), Parent("Inspired by")
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun WritingAssociationPicker(
    kind: WorkAssociation, form: AO3WorkForm, model: WritingWorkFormState,
    repository: AO3TagAutocompleteRepository?, onBack: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val keyboard = LocalSoftwareKeyboardController.current
    val scope = rememberCoroutineScope()
    val search = remember(kind, repository) { WritingCollectionsSearchState(repository, scope) }
    val searchState by search.state.collectAsState()
    val list = rememberLazyListState()
    val visibleCollections = form.collections.filter { offer ->
        val term = trimWritingTag(searchState.query)
        term.isEmpty() || offer.title.contains(term, true) || offer.name.contains(term, true)
    }
    val foundCollections = searchState.offers.filter { offer -> form.collections.none { it.name.equals(offer.name, true) } }
    LaunchedEffect(searchState.query, foundCollections.firstOrNull()?.name) {
        if (kind == WorkAssociation.CollectionsGifts && searchState.query.isNotEmpty()) {
            // Search stays pinned; the first answer is reachable above the keyboard even with many held rows.
            list.scrollToItem(if (foundCollections.isEmpty()) 2 else 3 + visibleCollections.size)
        }
    }
    var gift by remember(kind, model) { mutableStateOf("") }
    var languageChoice by remember { mutableStateOf(false) }
    DisposableEffect(search) { onDispose { search.close() } }
    LaunchedEffect(kind, model) { if (kind == WorkAssociation.CollectionsGifts) model.openCollections() }
    val leave = { keyboard?.hide(); search.close(); onBack() }
    BackHandler(onBack = leave)
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = leave)
    val addGift = { if (model.addGift(gift)) gift = "" }
    Column(Modifier.fillMaxSize().subjectScreenWash(palette).imePadding()) {
        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        Spacer(Modifier.height(76.dp))
        LazyColumn(Modifier.weight(1f).testTag("Writing association picker"), state = list,
            contentPadding = PaddingValues(bottom = 24.dp)) {
            item {
                SubjectHeaderBlock("Edit work", kind.title, subtitle = when (kind) {
                    WorkAssociation.Series -> seriesPickerSubtitle(form)
                    WorkAssociation.Parent -> form.parentWork.url.ifEmpty { "No source work" }
                    else -> form.title
                }, palette = palette, gutter = SubjectMetrics.accountGutter)
            }
            when (kind) {
                WorkAssociation.Series -> {
                    item { AssociationSection("Your series", form.series.size) }
                    if (form.series.isEmpty()) item {
                        SettingsPanel(Modifier.padding(top = 8.dp)) { SubjectFormRow("You have no series yet", value = "") }
                    }
                    itemsIndexed(form.series) { index, row ->
                        val current = form.currentSeries.any { it.seriesID == row.seriesID }
                        AssociationPanelRow(index, form.series.size) {
                            AssociationPickRow(row.title, if (current) "This work is in it" else null,
                                row.isSelected, current, selectedText = "Added on save", onPick = { model.selectSeries(row.seriesID) })
                        }
                    }
                    item { WorkFormFootnote("Each save adds this work to one series. Saving doesn't remove it from another " +
                        "series. To do that, use Remove works on the series' Edit screen.") }
                    val ordered = form.series.firstOrNull { it.isSelected }?.title ?: form.currentSeries.firstOrNull()?.title
                    if (ordered != null) item {
                        WorkFormSection("Position in $ordered")
                        SettingsPanel(Modifier.padding(top = 8.dp)) {
                            // Separate AO3 write not available yet. Show the iOS value with no disclosure/action.
                            SubjectFormRow("Reorder the series", value = "")
                        }
                        WorkFormFootnote("Changing the reading order updates every work in the series. Save the new " +
                            "order on its own screen.")
                    }
                    item {
                        WorkFormSection("New series")
                        SettingsPanel(Modifier.padding(top = 8.dp)) {
                            SubjectTextFieldRow("Create a series from this work", form.newSeriesTitle, "Title", model::newSeries)
                        }
                        WorkFormFootnote("AO3 creates the series with this work first. Add the series summary and notes afterwards.")
                    }
                }
                WorkAssociation.CollectionsGifts -> {
                    val rows = visibleCollections.map { it to false } + foundCollections.map { it to true }
                    val empty = rows.isEmpty()
                    item { AssociationSection("Your collections", form.collections.size) }
                    stickyHeader {
                        Column(Modifier.subjectWash(palette, SubjectMetrics.defaultWashHeight)
                            .padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                            .writingSuggestionPanel(first = true, last = false)) {
                            SubjectTextFieldRow("Search", searchState.query, "Search all collections by name", search::type, autocorrect = false)
                            SubjectRowSeparator()
                        }
                    }
                    if (empty) item {
                        AssociationPanelRow(0, 1, continuation = true) {
                            SubjectFormRow(if (form.collections.isEmpty() && searchState.query.isEmpty()) "AO3 offers this work no collections"
                                else "No collection matches “${searchState.query}”", value = "", valueMaxLines = Int.MAX_VALUE)
                        }
                    }
                    itemsIndexed(rows) { index, (offer, hit) ->
                        AssociationPanelRow(index, rows.size, continuation = true) {
                            AssociationPickRow(offer.title.ifEmpty { offer.name }, collectionStateText(offer.access),
                                offer.isSelected, add = hit, onPick = {
                                    if (hit) model.addCollection(offer) else model.toggleCollection(offer.name)
                                })
                        }
                    }
                    item { WorkFormFootnote("A work submitted to a moderated collection waits for a maintainer's approval. " +
                        "A work in an unrevealed collection stays hidden until the reveal. AO3 shows either state on the work.") }
                    item { AssociationSection("Gift recipients", form.gifts.size) }
                    item {
                        Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                            .writingSuggestionPanel(first = true, last = form.gifts.isEmpty())) {
                            WorkFormControlRow("Add") {
                                Box(if (isAccessibilityFontScale()) Modifier.fillMaxWidth() else Modifier.fillMaxWidth(0.65f)) {
                                    SubjectTextFieldRow("Add", gift, "Username or pseud", { gift = it }, autocorrect = false,
                                        fieldOnly = true, onSubmit = addGift, trailing = {
                                            TextButton(onClick = addGift, enabled = trimWritingTag(gift).isNotEmpty(),
                                                colors = ButtonDefaults.textButtonColors(contentColor = palette.accent, disabledContentColor = tokens.tertiaryInk)) {
                                                Text("Add", fontSize = 14.5.sp, lineHeight = 20.sp)
                                            }
                                        })
                                }
                            }
                            if (form.gifts.isNotEmpty()) SubjectRowSeparator()
                        }
                    }
                    itemsIndexed(form.gifts) { index, name ->
                        AssociationPanelRow(index, form.gifts.size, continuation = true) {
                            SubjectFormRow(name, trailing = {
                                IconButton(onClick = { model.removeGift(name) }) {
                                    Icon(Icons.Default.Close, "Remove $name", tint = SubjectPalette.fromHue(0.0, tokens.theme).accent, modifier = Modifier.size(18.dp))
                                }
                            })
                        }
                    }
                    item { WorkFormFootnote("When you post, AO3 emails each gift recipient. You can't take back the gift, " +
                        "so check each name before you save.") }
                    if (form.parentWork.url.isNotEmpty()) item {
                        WorkFormSection("Also on this work")
                        SettingsPanel(Modifier.padding(top = 8.dp)) { SubjectFormRow("Inspired by", value = "1 work") }
                    }
                }
                WorkAssociation.Creators -> {
                    item { AssociationSection("Your pseuds", form.creators.availablePseuds.size) }
                    if (form.creators.availablePseuds.isEmpty()) item {
                        SettingsPanel(Modifier.padding(top = 8.dp)) { SubjectFormRow("AO3 listed no pseuds for this work", value = "") }
                    }
                    itemsIndexed(form.creators.availablePseuds) { index, pseud ->
                        AssociationPanelRow(index, form.creators.availablePseuds.size) {
                            WorkFormToggle(pseud.title, pseud.value in form.creators.selectedPseudIDs) { model.togglePseud(pseud.value) }
                        }
                    }
                    item {
                        WorkFormSection("Invite a co-creator")
                        SettingsPanel(Modifier.padding(top = 8.dp)) {
                            SubjectTextFieldRow("Byline", form.creators.coauthorByline, "username (pseud)", model::coauthor, autocorrect = false)
                        }
                        WorkFormFootnote("AO3 invites a co-creator, and the work stays unchanged until they accept. " +
                            "Enter their byline exactly as it appears on AO3, as username or username (pseud).")
                    }
                }
                WorkAssociation.Parent -> {
                    item {
                        WorkFormSection("Source work")
                        SettingsPanel(Modifier.padding(top = 8.dp)) {
                            SubjectTextFieldRow("URL", form.parentWork.url, "https://archiveofourown.org/works/…",
                                { value -> model.parentWork { it.copy(url = value) } }, autocorrect = false, keyboardType = KeyboardType.Uri)
                            SubjectRowSeparator()
                            SubjectTextFieldRow("Title", form.parentWork.title, "Optional", { value -> model.parentWork { it.copy(title = value) } })
                            SubjectRowSeparator()
                            SubjectTextFieldRow("Author", form.parentWork.author, "Optional", { value -> model.parentWork { it.copy(author = value) } })
                        }
                        WorkFormFootnote("For a work on AO3, enter its web address. For a work from elsewhere, enter its " +
                            "title and author, which will appear instead of a link.")
                    }
                    item {
                        WorkFormSection("Translation")
                        SettingsPanel(Modifier.padding(top = 8.dp)) {
                            WorkFormToggle("This work is a translation", form.parentWork.isTranslation) { value -> model.parentWork { it.copy(isTranslation = value) } }
                            SubjectRowSeparator()
                            SubjectFormRow("Language of the source", value = form.languageOptions.firstOrNull { it.value == form.parentWork.languageID }?.title
                                ?: form.parentWork.languageID.ifEmpty { "Select…" }, valueMaxLines = Int.MAX_VALUE,
                                onClick = { languageChoice = true })
                        }
                    }
                }
            }
        }
    }
    if (languageChoice) WorkFormChoiceSheet("Language of the source", form.languageOptions, form.parentWork.languageID,
        onDismiss = { languageChoice = false }, onPick = { value ->
            model.parentWork { it.copy(languageID = value) }; languageChoice = false
        })
}

@Composable
private fun AssociationSection(title: String, count: Int) {
    SectionRuleHeader(title, count = count, modifier = Modifier.padding(top = 18.dp))
}

@Composable
private fun AssociationPanelRow(index: Int, count: Int, continuation: Boolean = false, content: @Composable () -> Unit) {
    Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = if (index == 0 && !continuation) 8.dp else 0.dp)
        .writingSuggestionPanel(first = index == 0 && !continuation, last = index == count - 1)) {
        content()
        if (index < count - 1) SubjectRowSeparator()
    }
}

@Composable
private fun AssociationPickRow(title: String, detail: String?, selected: Boolean, current: Boolean = false,
    add: Boolean = false, selectedText: String = "Selected", onPick: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Row(Modifier.fillMaxWidth().clickable(enabled = !current, role = Role.Button, onClick = onPick)
        .semantics(mergeDescendants = true) {
            contentDescription = if (add) "Add $title" else title
            stateDescription = listOfNotNull(detail, if (add) null else if (current) null else if (selected) selectedText else "Not selected").joinToString(". ")
        }.padding(horizontal = 14.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(11.dp)) {
        Icon(when { current -> Icons.Default.Check; add -> Icons.Default.AddCircleOutline;
            selected -> Icons.Default.CheckCircle; else -> Icons.Default.RadioButtonUnchecked }, null,
            tint = if (selected || add) tokens.scopePalette.accent else tokens.secondaryInk, modifier = Modifier.size(18.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium)
            if (detail != null) Text(detail, color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp)
        }
    }
}
