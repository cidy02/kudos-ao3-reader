import Foundation

extension WritingDocumentStore {
    func listStoryNotes(workID: UUID) throws -> [WritingStoryNote] {
        try readStoryNotes(workID: workID).notes
    }

    func addStoryNote(
        workID: UUID,
        kind: WritingStoryNoteKind,
        name: String,
        detail: String,
        pinned: Bool
    ) throws -> WritingStoryNote {
        let directory = try liveWorkDirectory(workID)
        var file = try readStoryNotes(in: directory)
        let stamp = now()
        let note = WritingStoryNote(
            id: UUID(),
            kind: kind,
            name: name,
            detail: detail,
            pinned: pinned,
            updatedAt: stamp,
            updatedBy: try deviceID()
        )
        file.notes.append(note)
        try WritingDocumentIO.writeJSON(file, to: WritingDocumentPaths.storyNotes(directory))
        return note
    }

    func updateStoryNote(workID: UUID, note: WritingStoryNote) throws -> WritingStoryNote {
        let directory = try liveWorkDirectory(workID)
        var file = try readStoryNotes(in: directory)
        guard let index = file.notes.firstIndex(where: { $0.id == note.id }) else {
            throw WritingDocumentError.storyNoteNotFound(note.id)
        }
        var saved = note
        saved.updatedAt = now()
        saved.updatedBy = try deviceID()
        file.notes[index] = saved
        try WritingDocumentIO.writeJSON(file, to: WritingDocumentPaths.storyNotes(directory))
        return saved
    }

    func deleteStoryNote(workID: UUID, noteID: UUID) throws {
        let directory = try liveWorkDirectory(workID)
        var file = try readStoryNotes(in: directory)
        guard file.notes.contains(where: { $0.id == noteID }) else {
            throw WritingDocumentError.storyNoteNotFound(noteID)
        }
        file.notes.removeAll { $0.id == noteID }
        try WritingDocumentIO.writeJSON(file, to: WritingDocumentPaths.storyNotes(directory))
    }

    /// Names for spell-check and suggestions, in note order, blanks and repeats dropped.
    func storyNoteNames(workID: UUID) throws -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for note in try listStoryNotes(workID: workID) {
            let name = note.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            names.append(name)
        }
        return names
    }

    func listAnnotations(workID: UUID, chapterID: UUID? = nil) throws -> [WritingAnnotation] {
        let annotations = try readAnnotations(workID: workID).annotations
        guard let chapterID else { return annotations }
        return annotations.filter { $0.chapterID == chapterID }
    }

    func addAnnotation(
        workID: UUID,
        chapterID: UUID,
        anchor: WritingAnnotationAnchor,
        text: String,
        kind: WritingAnnotationKind
    ) throws -> WritingAnnotation {
        _ = try chapterDirectory(workID: workID, chapterID: chapterID)
        let directory = try liveWorkDirectory(workID)
        var file = try readAnnotations(in: directory)
        let clamped = clampedAnchor(anchor)
        let stamp = now()
        let annotation = WritingAnnotation(
            id: UUID(),
            chapterID: chapterID,
            quote: clamped.quote,
            prefix: clamped.prefix,
            suffix: clamped.suffix,
            utf16Offset: clamped.utf16Offset,
            text: text,
            createdAt: stamp,
            resolvedAt: nil,
            kind: kind,
            updatedAt: stamp,
            updatedBy: try deviceID()
        )
        file.annotations.append(annotation)
        try WritingDocumentIO.writeJSON(file, to: WritingDocumentPaths.annotations(directory))
        return annotation
    }

    func updateAnnotation(workID: UUID, annotation: WritingAnnotation) throws -> WritingAnnotation {
        _ = try chapterDirectory(workID: workID, chapterID: annotation.chapterID)
        let directory = try liveWorkDirectory(workID)
        var file = try readAnnotations(in: directory)
        guard let index = file.annotations.firstIndex(where: { $0.id == annotation.id }) else {
            throw WritingDocumentError.annotationNotFound(annotation.id)
        }
        let clamped = clampedAnchor(annotation.anchor)
        var saved = annotation
        saved.quote = clamped.quote
        saved.prefix = clamped.prefix
        saved.suffix = clamped.suffix
        saved.utf16Offset = clamped.utf16Offset
        saved.updatedAt = now()
        saved.updatedBy = try deviceID()
        file.annotations[index] = saved
        try WritingDocumentIO.writeJSON(file, to: WritingDocumentPaths.annotations(directory))
        return saved
    }

    func deleteAnnotation(workID: UUID, annotationID: UUID) throws {
        let directory = try liveWorkDirectory(workID)
        var file = try readAnnotations(in: directory)
        guard file.annotations.contains(where: { $0.id == annotationID }) else {
            throw WritingDocumentError.annotationNotFound(annotationID)
        }
        file.annotations.removeAll { $0.id == annotationID }
        try WritingDocumentIO.writeJSON(file, to: WritingDocumentPaths.annotations(directory))
    }

    /// Places each of the chapter's notes against `bodyHTML`. Placed notes whose hint
    /// moved are saved. Notes that cannot be placed are left untouched and returned in
    /// `lost`. Nothing here is written to AO3.
    func reanchorAnnotations(
        workID: UUID,
        chapterID: UUID,
        bodyHTML: String
    ) throws -> WritingAnnotationReanchorReport {
        _ = try chapterDirectory(workID: workID, chapterID: chapterID)
        let directory = try liveWorkDirectory(workID)
        var file = try readAnnotations(in: directory)
        var placed: [WritingAnnotation] = []
        var lost: [WritingAnnotation] = []
        var changed = false
        for index in file.annotations.indices {
            guard file.annotations[index].chapterID == chapterID else { continue }
            let current = file.annotations[index]
            switch WritingAnnotationReanchor.reanchor(current.anchor, in: bodyHTML) {
            case .lost:
                lost.append(current)
            case .placed(let anchor):
                var next = current
                if next.anchor != anchor {
                    next.quote = anchor.quote
                    next.prefix = anchor.prefix
                    next.suffix = anchor.suffix
                    next.utf16Offset = anchor.utf16Offset
                    next.updatedAt = now()
                    next.updatedBy = try deviceID()
                    file.annotations[index] = next
                    changed = true
                }
                placed.append(file.annotations[index])
            }
        }
        if changed {
            try WritingDocumentIO.writeJSON(file, to: WritingDocumentPaths.annotations(directory))
        }
        return WritingAnnotationReanchorReport(placed: placed, lost: lost)
    }

    private func readStoryNotes(workID: UUID) throws -> WritingStoryNotesFile {
        try readStoryNotes(in: try liveWorkDirectory(workID))
    }

    private func readStoryNotes(in directory: URL) throws -> WritingStoryNotesFile {
        let url = WritingDocumentPaths.storyNotes(directory)
        guard fileExists(url) else { return WritingStoryNotesFile(notes: []) }
        return try WritingDocumentIO.readJSON(WritingStoryNotesFile.self, from: url)
    }

    private func readAnnotations(workID: UUID) throws -> WritingAnnotationsFile {
        try readAnnotations(in: try liveWorkDirectory(workID))
    }

    private func readAnnotations(in directory: URL) throws -> WritingAnnotationsFile {
        let url = WritingDocumentPaths.annotations(directory)
        guard fileExists(url) else { return WritingAnnotationsFile(annotations: []) }
        return try WritingDocumentIO.readJSON(WritingAnnotationsFile.self, from: url)
    }

    private func clampedAnchor(_ anchor: WritingAnnotationAnchor) -> WritingAnnotationAnchor {
        WritingAnnotationAnchor(
            quote: anchor.quote,
            prefix: String(anchor.prefix.prefix(WritingAnnotationReanchor.contextLimit)),
            suffix: String(anchor.suffix.prefix(WritingAnnotationReanchor.contextLimit)),
            utf16Offset: max(0, anchor.utf16Offset)
        )
    }
}
