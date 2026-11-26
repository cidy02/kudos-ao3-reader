/*
 * TEMPORARY STUB — T-576b (Apple Rich Text host, parts 1 & 2).
 * Replaced by the built `editor-core` ProseMirror bundle (T-576a).
 *
 * Answers every §7.2 bridge call, §7.11 verifySwitch, and §10.3 setAppearance
 * trivially without ever assigning untrusted HTML to `innerHTML` (§11).
 * Emits `ready`, rate-limited `edited`, `toolbarState` (with undoTitle/redoTitle),
 * `caretRect` (N4), and debounced `mirrorBlocks` (§7.10).
 */
(function () {
  "use strict";

  const BRIDGE_VERSION = 1;
  const SCHEMA_VERSION = 1;
  const BUNDLE_VERSION = "0.0.0-stub";

  const root = document.getElementById("editor-root");

  let currentHtml = "";
  let currentRevision = 0;
  let dirtySinceLoad = false;
  let undoStack = [];
  let redoStack = [];
  let editTimer = null;
  let mirrorTimer = null;
  let lastEditSentAt = 0;
  let lastMirroredBlocks = [];

  function postEvent(event) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.kudos) {
        window.webkit.messageHandlers.kudos.postMessage(event);
      }
    } catch (_) {
      // Ignore outside WKWebView.
    }
  }

  function emptyLossReport() {
    return {
      dropped: { elements: {}, attributes: {} },
      unwrapped: {},
      normalized: 0,
      preserved: 0
    };
  }

  function applyTheme(theme) {
    if (!theme || typeof theme !== "object") return;
    const style = document.documentElement.style;
    if (theme.background) style.setProperty("--bg", String(theme.background));
    if (theme.text) style.setProperty("--fg", String(theme.text));
    if (theme.accent) style.setProperty("--accent", String(theme.accent));
    if (theme.link) style.setProperty("--link", String(theme.link));
    if (theme.fontFamily) style.setProperty("--font", String(theme.fontFamily));
    if (typeof theme.fontSizePx === "number") style.setProperty("--font-size", theme.fontSizePx + "px");
    if (typeof theme.lineHeight === "number") style.setProperty("--line-height", String(theme.lineHeight));
  }

  function applyAppearance(appearance) {
    if (!appearance || typeof appearance !== "object") return;
    const docEl = document.documentElement;
    const style = docEl.style;
    if (appearance.fontFamily) style.setProperty("--font", String(appearance.fontFamily));
    if (typeof appearance.fontSizePx === "number") {
      style.setProperty("--font-size", appearance.fontSizePx + "px");
    }
    if (typeof appearance.lineHeight === "number") {
      style.setProperty("--line-height", String(appearance.lineHeight));
    }
    style.setProperty("--font-weight", appearance.boldText ? "600" : "400");
    if (appearance.colorScheme) docEl.dataset.colorScheme = String(appearance.colorScheme);
    docEl.dataset.contrast = appearance.increaseContrast ? "high" : "normal";
    docEl.dataset.boldText = appearance.boldText ? "true" : "false";
    if (appearance.contentSizeCategory) {
      docEl.dataset.contentSizeCategory = String(appearance.contentSizeCategory);
    }
    docEl.dataset.accessibilitySize = appearance.isAccessibilityCategory ? "true" : "false";
  }

  function countWords(text) {
    const plain = String(text || "").replace(/<[^>]*>/g, " ").trim();
    if (!plain) return 0;
    return plain.split(/\s+/).filter(Boolean).length;
  }

  function splitBlocks(html) {
    const text = String(html || "");
    if (!text) return [""];
    return text.split(/\n\n+/);
  }

  function emitToolbarState() {
    const undoEntry = undoStack.length > 0 ? undoStack[undoStack.length - 1] : null;
    const redoEntry = redoStack.length > 0 ? redoStack[redoStack.length - 1] : null;
    postEvent({
      type: "toolbarState",
      marks: [],
      block: "paragraph",
      align: null,
      dir: null,
      canUndo: undoStack.length > 0,
      canRedo: redoStack.length > 0,
      undoTitle: undoEntry ? undoEntry.label : null,
      redoTitle: redoEntry ? redoEntry.label : null
    });
  }

  function emitCaretRect() {
    if (!root) return;
    const selection = window.getSelection && window.getSelection();
    if (!selection || selection.rangeCount === 0) return;
    const range = selection.getRangeAt(0).cloneRange();
    range.collapse(true);
    const rect = range.getBoundingClientRect();
    if (!rect || (rect.width === 0 && rect.height === 0 && rect.top === 0)) return;
    postEvent({
      type: "caretRect",
      x: rect.left + window.scrollX,
      y: rect.top + window.scrollY,
      width: Math.max(rect.width, 2),
      height: Math.max(rect.height, 18)
    });
  }

  function scheduleEditedEvent() {
    const now = Date.now();
    const minIntervalMs = 250; // <= 4 per second, trailing edge guaranteed (§7.2)
    const elapsed = now - lastEditSentAt;
    if (elapsed >= minIntervalMs) {
      lastEditSentAt = now;
      if (editTimer !== null) {
        clearTimeout(editTimer);
        editTimer = null;
      }
      postEvent({ type: "edited", revision: currentRevision });
      return;
    }
    if (editTimer === null) {
      editTimer = setTimeout(function () {
        editTimer = null;
        lastEditSentAt = Date.now();
        postEvent({ type: "edited", revision: currentRevision });
      }, minIntervalMs - elapsed);
    }
  }

  function scheduleMirrorUpdate() {
    if (mirrorTimer !== null) clearTimeout(mirrorTimer);
    mirrorTimer = setTimeout(function () {
      mirrorTimer = null;
      const nextBlocks = splitBlocks(currentHtml);
      const changes = [];
      let lastChanged = 0;
      for (let i = 0; i < nextBlocks.length; i += 1) {
        if (lastMirroredBlocks[i] !== nextBlocks[i]) {
          changes.push({
            index: i,
            html: nextBlocks[i],
            separatorAfter: i + 1 < nextBlocks.length ? "\n\n" : ""
          });
          lastChanged = i;
        }
      }
      const previousLength = lastMirroredBlocks.length;
      lastMirroredBlocks = nextBlocks;
      if (changes.length > 0 || nextBlocks.length !== previousLength) {
        postEvent({
          type: "mirrorBlocks",
          revision: currentRevision,
          totalBlocks: nextBlocks.length,
          activeBlockIndex: lastChanged,
          changes: changes
        });
      }
    }, 300);
  }

  if (root) {
    root.addEventListener("input", function () {
      undoStack.push({ html: currentHtml, label: "Typing" });
      redoStack = [];
      currentHtml = root.textContent || "";
      currentRevision += 1;
      dirtySinceLoad = true;
      scheduleEditedEvent();
      scheduleMirrorUpdate();
      emitToolbarState();
      emitCaretRect();
    });
    document.addEventListener("selectionchange", function () {
      if (document.activeElement === root) emitCaretRect();
    });
  }

  async function handleCall(name, args) {
    const payload = args && typeof args === "object" ? args : {};
    switch (name) {
      case "configure":
        applyTheme(payload.theme);
        return {
          bridgeVersion: BRIDGE_VERSION,
          schemaVersion: SCHEMA_VERSION,
          bundleVersion: BUNDLE_VERSION
        };

      case "load":
        currentHtml = typeof payload.html === "string" ? payload.html : "";
        currentRevision = typeof payload.revision === "number" ? payload.revision : 0;
        dirtySinceLoad = false;
        undoStack = [];
        redoStack = [];
        lastMirroredBlocks = splitBlocks(currentHtml);
        if (root) {
          root.contentEditable = "false";
          root.textContent = currentHtml;
        }
        emitToolbarState();
        return {
          revision: currentRevision,
          loss: emptyLossReport(),
          timing: { parseMs: 0, buildMs: 0, renderMs: 0 }
        };

      case "activate":
        if (root) {
          root.contentEditable = "true";
          if (payload.focus) root.focus();
        }
        return { caretFound: payload.caret != null };

      case "freeze":
        if (root) {
          root.blur();
          root.contentEditable = "false";
        }
        return { revision: currentRevision };

      case "snapshot":
        return {
          revision: currentRevision,
          html: currentHtml,
          caretOffset: payload.caret ? 0 : null,
          words: countWords(currentHtml)
        };

      case "command": {
        const commandName = String(payload.name || "");
        if (commandName === "undo" && undoStack.length > 0) {
          const previous = undoStack.pop();
          redoStack.push({ html: currentHtml, label: previous.label });
          currentHtml = previous.html;
          currentRevision += 1;
          dirtySinceLoad = true;
          if (root) root.textContent = currentHtml;
          scheduleEditedEvent();
          scheduleMirrorUpdate();
          emitToolbarState();
          return { applied: true };
        }
        if (commandName === "redo" && redoStack.length > 0) {
          const next = redoStack.pop();
          undoStack.push({ html: currentHtml, label: next.label });
          currentHtml = next.html;
          currentRevision += 1;
          dirtySinceLoad = true;
          if (root) root.textContent = currentHtml;
          scheduleEditedEvent();
          scheduleMirrorUpdate();
          emitToolbarState();
          return { applied: true };
        }
        return { applied: false };
      }

      case "lint":
        return { loss: emptyLossReport() };

      case "setTheme":
        applyTheme(payload);
        return {};

      case "setAppearance":
        applyAppearance(payload);
        return {};

      case "dispose":
        currentHtml = "";
        dirtySinceLoad = false;
        undoStack = [];
        redoStack = [];
        lastMirroredBlocks = [];
        if (mirrorTimer !== null) {
          clearTimeout(mirrorTimer);
          mirrorTimer = null;
        }
        if (root) {
          root.contentEditable = "false";
          root.textContent = "";
        }
        return {};

      case "verifySwitch":
        return {
          ok: true,
          candidateHtml: typeof payload.html === "string" ? payload.html : currentHtml,
          reason: null
        };

      default:
        throw { code: "unknown-call", message: "Unsupported editor call: " + String(name) };
    }
  }

  window.KudosEditor = {
    call: handleCall
  };

  postEvent({
    type: "ready",
    bundleVersion: BUNDLE_VERSION,
    schemaVersion: SCHEMA_VERSION
  });
})();
