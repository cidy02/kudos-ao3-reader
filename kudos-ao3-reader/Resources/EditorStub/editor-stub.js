/*
 * TEMPORARY STUB — T-576b (Apple Rich Text host, part 1).
 * Replaced by the built `editor-core` ProseMirror bundle (T-576a).
 *
 * Answers every §7.2 bridge call and §7.11 verifySwitch trivially without ever
 * parsing untrusted HTML into the page as markup (§11).
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
  let lastEditSentAt = 0;

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

  function countWords(text) {
    const plain = String(text || "").replace(/<[^>]*>/g, " ").trim();
    if (!plain) return 0;
    return plain.split(/\s+/).filter(Boolean).length;
  }

  function emitToolbarState() {
    postEvent({
      type: "toolbarState",
      marks: [],
      block: "paragraph",
      align: null,
      dir: null,
      canUndo: undoStack.length > 0,
      canRedo: redoStack.length > 0
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

  if (root) {
    root.addEventListener("input", function () {
      undoStack.push(currentHtml);
      redoStack = [];
      currentHtml = root.textContent || "";
      currentRevision += 1;
      dirtySinceLoad = true;
      scheduleEditedEvent();
      emitToolbarState();
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
          redoStack.push(currentHtml);
          currentHtml = undoStack.pop();
          currentRevision += 1;
          dirtySinceLoad = true;
          if (root) root.textContent = currentHtml;
          scheduleEditedEvent();
          emitToolbarState();
          return { applied: true };
        }
        if (commandName === "redo" && redoStack.length > 0) {
          undoStack.push(currentHtml);
          currentHtml = redoStack.pop();
          currentRevision += 1;
          dirtySinceLoad = true;
          if (root) root.textContent = currentHtml;
          scheduleEditedEvent();
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

      case "dispose":
        currentHtml = "";
        dirtySinceLoad = false;
        undoStack = [];
        redoStack = [];
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
