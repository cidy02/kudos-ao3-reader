#!/usr/bin/env python3
"""Standard-library reference for D4 reducer retention algebra.

This checks the fixture envelope and reducer contract against an independent
naive reducer. It does not implement D5 transport or the v8 shipped merge.
"""
import itertools
import json
import math
import random
import re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KINDS = {"RK-IDENTITY", "RK-LWW", "RK-MAX", "RK-VALUE", "RK-ONCE",
         "RK-GROW", "RK-LIFECYCLE", "RK-AUTH", "RK-EPOCH", "RK-RECORD",
         "RK-ANNOTATION", "RK-ASSET", "RK-FONT", "RK-ENTRY", "RK-DIAG",
         "RK-LEGACY", "RK-OPAQUE"}
DISPATCH = {
    "work.delete": "RK-LIFECYCLE", "work.restore": "RK-LIFECYCLE",
    "work.purge": "RK-LIFECYCLE", "asset.write": "RK-ASSET",
    "asset.remove": "RK-ASSET", "writer.enroll": "RK-AUTH",
    "writer.revoke": "RK-AUTH", "legacy.evidence": "RK-LEGACY",
    "queue.membership.add": "RK-EPOCH", "queue.membership.move": "RK-EPOCH",
    "queue.membership.remove": "RK-EPOCH", "annotation.add": "RK-ANNOTATION",
    "queue.membership.note": "RK-EPOCH", "queue.membership.state": "RK-EPOCH",
    "queue.membership.origin": "RK-EPOCH",
    "annotation.edit": "RK-ANNOTATION", "annotation.delete": "RK-ANNOTATION",
    "bookmark.put": "RK-RECORD", "bookmark.delete": "RK-RECORD",
    "favorite.put": "RK-RECORD", "favorite.delete": "RK-RECORD",
    "session.put": "RK-RECORD", "session.delete": "RK-RECORD",
    "watermark.put": "RK-RECORD", "watermark.delete": "RK-RECORD",
    "savedSearch.put": "RK-RECORD", "savedSearch.delete": "RK-RECORD",
    "tagAlias.put": "RK-RECORD", "tagAlias.delete": "RK-RECORD",
    "font.add": "RK-FONT", "font.remove": "RK-FONT",
    "original.set": "RK-ONCE", "taglist.add": "RK-GROW",
    "setting.entry.set": "RK-ENTRY", "setting.entry.reset": "RK-ENTRY",
    "setting.set": "RK-LWW", "setting.reset": "RK-LWW",
    "pronunciation.set": "RK-ENTRY", "pronunciation.reset": "RK-ENTRY",
    "future.thing": "RK-OPAQUE",
    "followedTag.put": "RK-RECORD", "followedTag.delete": "RK-RECORD",
    "queue.delete": "RK-LIFECYCLE", "queue.restore": "RK-LIFECYCLE",
    "queue.purge": "RK-LIFECYCLE", "collection.delete": "RK-LIFECYCLE",
    "collection.restore": "RK-LIFECYCLE", "collection.purge": "RK-LIFECYCLE",
    "collection.membership.add": "RK-EPOCH", "collection.membership.remove": "RK-EPOCH",
    "queueTag.attach": "RK-EPOCH", "queueTag.detach": "RK-EPOCH",
    "userTag.attach": "RK-EPOCH", "userTag.detach": "RK-EPOCH",
    "queueSavedSearchLink.set": "RK-RECORD", "queueSavedSearchLink.clear": "RK-RECORD",
    "recoveryDoc.put": "RK-LWW",
}
RECORD_DELETES = {k for k in DISPATCH if DISPATCH[k] == "RK-RECORD" and
                  k.endswith((".delete", ".clear"))}
EVIDENCE_CONTEXT = {}
GROUPS = {"seriesPosition": "RK-MAX", "epubPreservationStatusRaw": "RK-MAX",
          "preservedAt": "RK-MAX", "lastPreservationAttemptAt": "RK-MAX",
          "lastAvailabilityCheck": "RK-MAX", "coverRecipeJSON": "RK-VALUE",
          "importSourceRaw": "RK-ONCE", "importSourceSince": "RK-ONCE",
          "kudosAtSave": "RK-ONCE", "hitsAtSave": "RK-ONCE",
          "bookmarksAtSave": "RK-ONCE", "statsSavedAt": "RK-ONCE",
          "ageDaysAtSave": "RK-ONCE", "fandomWorksAtSave": "RK-ONCE",
          "hasGivenKudos": "RK-GROW", "ao3Unavailable": "RK-GROW",
          "workTagsFetched": "RK-GROW", "tags": "RK-GROW",
          "warnings": "RK-GROW", "categories": "RK-GROW",
          "fandoms": "RK-GROW", "characters": "RK-GROW",
          "relationships": "RK-GROW", "freeforms": "RK-GROW",
          }
LWW_GROUPS = {"title", "author", "summary", "rating", "language",
              "datePublished", "dateUpdated", "chapters", "seriesTitle",
              "seriesURL", "ao3SeriesID", "sourceURL", "wordCount", "kudos",
              "comments", "bookmarks", "hits", "knownChapterCount",
              "isFavorite", "isSaved", "isFinished", "isComplete",
              "readingStatus", "keepInProgressOverride", "hiddenFromHistoryAt", "progressCore",
              "readiumLocator", "legacyReaderProgress", "metadataSyncStatusRaw",
              "chapterWordCountsJSON", "wordUnitRaw", "authorIdentitiesJSON",
              "downloadedAt", "name", "description", "colour", "pin",
              "keepsWorksOffline", "notes", "smartRules", "searchSources",
              "sortOrder", "showsOnHome", "workOrderRaw"}
DATE_GROUPS = {"preservedAt", "lastPreservationAttemptAt", "lastAvailabilityCheck"}
PRESERVATION_RANK = {"notPreserved": 0, "queued": 1, "preserving": 1,
                     "failed": 1, "missingFile": 1, "preserved": 2}
READING_STATUS_FIELDS = {"readingStatusRaw", "stopReasonRaw", "stopTag", "stopNote",
                         "stackThreshold", "stackBaselineChapterCount",
                         "statusWasRecorded", "statusChangedAt", "stoppedAt"}


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":"))


def schema_check(value, rule, root, path="$"):
    if "$ref" in rule:
        ref = rule["$ref"]
        assert ref.startswith("#/"), (path, ref)
        cur = root
        for part in ref[2:].split("/"):
            cur = cur[part.replace("~1", "/").replace("~0", "~")]
        schema_check(value, cur, root, path)
    for sub in rule.get("allOf", []):
        schema_check(value, sub, root, path)
    if "anyOf" in rule:
        assert any(valid(value, sub, root) for sub in rule["anyOf"]), path
    if "oneOf" in rule:
        assert sum(valid(value, sub, root) for sub in rule["oneOf"]) == 1, path
    if "not" in rule:
        assert not valid(value, rule["not"], root), path
    if "if" in rule and valid(value, rule["if"], root):
        schema_check(value, rule.get("then", {}), root, path)
    if "const" in rule:
        assert value == rule["const"], (path, "const")
    if "enum" in rule:
        assert value in rule["enum"], (path, "enum")
    types = rule.get("type")
    if types:
        types = types if isinstance(types, list) else [types]
        checks = {"object": lambda: isinstance(value, dict),
                  "array": lambda: isinstance(value, list),
                  "string": lambda: isinstance(value, str),
                  "integer": lambda: isinstance(value, int) and not isinstance(value, bool),
                  "number": lambda: isinstance(value, (int, float)) and not isinstance(value, bool),
                  "boolean": lambda: isinstance(value, bool),
                  "null": lambda: value is None}
        assert any(checks[t]() for t in types), (path, "type", types)
    if isinstance(value, dict):
        assert all(k in value for k in rule.get("required", [])), (path, "required")
        assert len(value) >= rule.get("minProperties", 0), (path, "minProperties")
        props = rule.get("properties", {})
        patterns = rule.get("patternProperties", {})
        for key, item in value.items():
            if key in props:
                schema_check(item, props[key], root, path + "." + key)
            matching = [r for p, r in patterns.items() if re.search(p, key)]
            for r in matching:
                schema_check(item, r, root, path + "." + key)
            if key not in props and not matching:
                extra = rule.get("additionalProperties", True)
                assert extra is not False, (path, "additionalProperties", key)
                if isinstance(extra, dict):
                    schema_check(item, extra, root, path + "." + key)
    if isinstance(value, list):
        assert len(value) >= rule.get("minItems", 0), (path, "minItems")
        assert len(value) <= rule.get("maxItems", float("inf")), (path, "maxItems")
        if rule.get("uniqueItems"):
            assert len({canonical(x) for x in value}) == len(value), (path, "uniqueItems")
        items = rule.get("items", {})
        for i, item in enumerate(value):
            sub = items[i] if isinstance(items, list) and i < len(items) else items
            if isinstance(sub, dict):
                schema_check(item, sub, root, f"{path}[{i}]")
    if isinstance(value, str):
        assert len(value) >= rule.get("minLength", 0), (path, "minLength")
        if "pattern" in rule:
            assert re.search(rule["pattern"], value), (path, "pattern")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        assert value >= rule.get("minimum", -float("inf")), (path, "minimum")
        assert value <= rule.get("maximum", float("inf")), (path, "maximum")


def valid(value, rule, root):
    try:
        schema_check(value, rule, root)
        return True
    except AssertionError:
        return False


def atom(op, reducer, group="", value=None):
    a = {"reducer": reducer, "id": op["id"], "stamp": op["stamp"],
         "key": op.get("target", op.get("payload", {}).get("owner", "")),
         "group": group, "value": value}
    if reducer not in {"RK-LWW", "RK-MAX", "RK-VALUE", "RK-ENTRY", "RK-GROW"}:
        a["source"] = op
    return a


def scope_of(op):
    return set(op.get("payload", {}).get("scope", [op.get("target")]))


def valid_native_purge(op, lookup):
    """Only command shape; mutable authorization and basis matching are separate."""
    observed = op.get("observed", {})
    payload = op.get("payload", {})
    if payload.get("reason") not in {"explicit", "expired"}:
        return False
    basis = observed.get("basis", [])
    if not basis:
        return False
    named = [lookup.get(name) for name in basis]
    if any(d is None or d["kind"] != op["kind"].replace(".purge", ".delete") or
           not scope_of(d) & scope_of(op) for d in named):
        return False
    union = set().union(*(scope_of(d) for d in named))
    return bool(payload.get("administrative") or union <= scope_of(op))


def typed_valid(op, visiting=frozenset()):
    """Structural typed-evidence result, independent of delivery and authority."""
    kind = op["kind"]
    observed = op.get("observed", {})
    payload = op.get("payload", {})
    if kind == "legacy.evidence":
        return bool(payload.get("verified") and payload.get("adopted"))
    if kind.endswith(".restore"):
        names = observed.get("deletions", [])
        if not names or any(name not in EVIDENCE_CONTEXT or
                            EVIDENCE_CONTEXT[name]["kind"] != kind.replace(".restore", ".delete") or
                            not scope_of(EVIDENCE_CONTEXT[name]) & scope_of(op) for name in names):
            return False
        if any(name not in EVIDENCE_CONTEXT or
               EVIDENCE_CONTEXT[name]["kind"] != kind.replace(".restore", ".purge") or
               EVIDENCE_CONTEXT[name].get("payload", {}).get("reason") != "expired" or
               not valid_native_purge(EVIDENCE_CONTEXT[name], EVIDENCE_CONTEXT) or
               not scope_of(EVIDENCE_CONTEXT[name]) & scope_of(op) or
               EVIDENCE_CONTEXT[name]["stamp"][0] >= op["stamp"][0]
               for name in observed.get("observedExpiry", [])):
            return False
        union = set().union(*(scope_of(EVIDENCE_CONTEXT[name]) for name in names))
        return bool(payload.get("administrative") or union <= scope_of(op))
    if kind == "asset.write":
        base = observed.get("base")
        if base is None:
            return True
        if base in visiting or base not in EVIDENCE_CONTEXT:
            return False
        predecessor = EVIDENCE_CONTEXT[base]
        return (predecessor["kind"] == kind and predecessor.get("target") == op.get("target") and
                predecessor.get("payload", {}).get("assetKind") == payload.get("assetKind") and
                typed_valid(predecessor, visiting | {base}))
    if kind == "asset.remove":
        names = observed.get("names", [])
        owner = op.get("target", payload.get("owner"))
        return bool(names) and all(name in EVIDENCE_CONTEXT and
                   EVIDENCE_CONTEXT[name]["kind"] == "asset.write" and
                   EVIDENCE_CONTEXT[name].get("target") == owner and
                   EVIDENCE_CONTEXT[name].get("payload", {}).get("assetKind") == payload.get("assetKind") and
                   typed_valid(EVIDENCE_CONTEXT[name]) for name in names)
    if kind.endswith(".purge"):
        basis = observed.get("basis", [])
        if not basis:
            evidence = observed.get("evidence", [])
            return bool(payload.get("reason") == "explicit" and evidence and
                   all(name in EVIDENCE_CONTEXT and
                   EVIDENCE_CONTEXT[name]["kind"] == "legacy.evidence" and
                   EVIDENCE_CONTEXT[name].get("payload", {}).get("digest") == payload.get("legacyEvidence") and
                   typed_valid(EVIDENCE_CONTEXT[name]) for name in evidence))
        return valid_native_purge(op, EVIDENCE_CONTEXT)
    if kind == "annotation.delete":
        adds, sources = observed.get("adds", []), observed.get("sources", [])
        return bool(adds and len(adds) == len(sources) and all(
            name in EVIDENCE_CONTEXT and EVIDENCE_CONTEXT[name]["kind"] == "annotation.add" and
            EVIDENCE_CONTEXT[name].get("target") == source
            for name, source in zip(adds, sources)))
    if kind in {"queue.membership.move", "queue.membership.remove",
                "queue.membership.note", "queue.membership.state", "queue.membership.origin",
                "collection.membership.remove", "queueTag.detach", "userTag.detach"}:
        add_kind = (kind.replace(".detach", ".attach") if kind.endswith(".detach") else
                    kind.split(".")[0] + ".membership.add")
        names = observed.get("epochs", [])
        return bool(names and all(name in EVIDENCE_CONTEXT and
                    EVIDENCE_CONTEXT[name]["kind"] == add_kind and
                    EVIDENCE_CONTEXT[name].get("target") == op.get("target") for name in names))
    if kind == "font.remove":
        names = observed.get("names", [])
        return bool(names and all(name in EVIDENCE_CONTEXT and
                    EVIDENCE_CONTEXT[name]["kind"] == "font.add" for name in names))
    if kind in RECORD_DELETES:
        put_kind = kind.replace(".delete", ".put").replace(".clear", ".set")
        names = observed.get("puts", [])
        return bool(names) and all(name in EVIDENCE_CONTEXT and
                   EVIDENCE_CONTEXT[name]["kind"] == put_kind and
                   EVIDENCE_CONTEXT[name].get("target") == op.get("target")
                   for name in names)
    return True


def expand(op):
    facts = expand_semantic(op)
    # A covered reference still needs typed evidence after its value lost a
    # register. This compact marker models the checkpoint evidence index.
    marker = atom(op, "RK-DIAG", "@typedEvidence", {
        "kind": op["kind"], "owner": op.get("target", op.get("payload", {}).get("owner", "")),
        "valid": typed_valid(op)})
    marker.pop("source")
    facts.append(marker)
    if op["kind"] == "work.edit" and any(
            g not in op.get("payload", {}).get("malformed", []) and
            not (isinstance(v, dict) and v.get("malformed"))
            for g, v in op.get("payload", {}).get("groups", {}).items()):
        facts.append(atom(op, "RK-LWW", "@greatestContent", op["id"]))
    return facts


def expand_semantic(op):
    kind = op["kind"]
    payload = op.get("payload", {})
    if kind in {"work.create", "work.edit", "queue.create", "collection.create",
                "queue.edit", "collection.edit"}:
        out = []
        if kind in {"work.create", "queue.create", "collection.create"}:
            out.append(atom(op, "RK-IDENTITY", value={
                "ao3WorkID": payload.get("ao3WorkID"), "urls": payload.get("urls", []),
                "supersedes": payload.get("supersedes"), "entityClass": kind.split(".")[0],
                "entityKind": payload.get("kind")}))
        malformed = payload.get("malformed", [])
        for group, value in payload.get("groups", {}).items():
            assert group in GROUPS or group in LWW_GROUPS, (kind, group)
            assert not (kind.startswith("queue.") and group == "tags"), (
                kind, "queue tags require queueTag.attach/detach")
            if group == "readingStatus" and group not in malformed:
                assert isinstance(value, dict) and set(value) == READING_STATUS_FIELDS, (
                    kind, "readingStatus is one complete atomic group")
            reducer = GROUPS.get(group, "RK-LWW")
            if group in malformed or (isinstance(value, dict) and value.get("malformed")):
                out.append(atom(op, "RK-DIAG", group, {"error": "malformedGroup"}))
            else:
                suffix = "|" + str(payload["forDigest"]) if group in {
                    "chapterWordCountsJSON", "wordUnitRaw"} and "forDigest" in payload else ""
                out.append(atom(op, reducer, group + suffix, value))
        return out
    assert kind in DISPATCH, ("unmapped operation kind", kind)
    reducer = DISPATCH[kind]
    if kind in {"setting.set", "setting.reset"}:
        if payload.get("malformed"):
            return [atom(op, "RK-DIAG", "value", {"error": "malformedGroup"})]
        return [atom(op, "RK-LWW", "value", None if kind.endswith(".reset") else payload.get("value"))]
    if payload.get("malformed") and reducer == "RK-ENTRY":
        return [atom(op, "RK-DIAG", kind, {"error": "malformedGroup"})]
    if reducer == "RK-ENTRY":
        return [atom(op, reducer, "entry", None if kind.endswith(".reset") else
                     payload.get("value", payload.get("ipa")))]
    if kind == "taglist.add":
        assert payload["group"] in {"warnings", "categories", "tags", "fandoms",
                                    "characters", "relationships", "freeforms"}, payload["group"]
        return [atom(op, reducer, payload["group"], payload["values"])]
    if kind == "queueSavedSearchLink.set":
        assert {"lastCheckedAt", "newResultCount"} <= set(payload), op
        assert (payload["lastCheckedAt"] is None or
                isinstance(payload["lastCheckedAt"], str) and
                math.isfinite(instant_seconds(payload["lastCheckedAt"]))), op
        assert isinstance(payload["newResultCount"], int) and not isinstance(
            payload["newResultCount"], bool) and payload["newResultCount"] >= 0, op
    if kind == "queueTag.attach":
        assert "|" in op["target"] and isinstance(payload.get("tag"), str) and payload["tag"], op
    if kind == "queueTag.detach":
        assert "|" in op["target"] and not payload, op
    return [atom(op, reducer, payload.get("group", ""), payload.get("value", payload))]


def instant_seconds(value):
    if isinstance(value, (int, float)):
        return float(value)
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def cover_score(value):
    t = instant_seconds(value.get("pinnedAt", 0))
    if t != 0:
        return (t, 0, 0, 0, canonical(value))
    return (t, int(bool(value.get("fandom"))), int(bool(value.get("closedRing"))),
            value.get("tier", 0), canonical(value))


def rank(a):
    v = a["value"]
    if a["reducer"] == "RK-MAX":
        if a["group"] == "epubPreservationStatusRaw":
            v = PRESERVATION_RANK.get(v, -1)
        elif a["group"] in DATE_GROUPS:
            v = instant_seconds(v)
        return (v, tuple(a["stamp"]), a["id"])
    if a["reducer"] == "RK-VALUE":
        return (*cover_score(v), tuple(a["stamp"]), a["id"])
    return (tuple(a["stamp"]), a["id"])


def retain(atoms):
    winners = {}
    evidence = {}
    lifecycle = []
    epochs = []
    annotations = []
    for a in atoms:
        reducer = a["reducer"]
        assert reducer in KINDS, reducer
        if reducer in {"RK-LWW", "RK-MAX", "RK-VALUE", "RK-ENTRY"}:
            key = (reducer, a["key"], a["group"])
            old = winners.get(key)
            if old is None or rank(a) > rank(old):
                winners[key] = a
        elif reducer == "RK-GROW":
            vals = a["value"] if isinstance(a["value"], list) else [a["value"]]
            for val in vals:
                key = (reducer, a["key"], a["group"],
                       "boolean" if isinstance(val, bool) else canonical(val))
                old = winners.get(key)
                single = {**a, "value": val}
                if old is None or (val, rank(single)) > (old["value"], rank(old)):
                    winners[key] = single
        elif reducer == "RK-IDENTITY":
            evidence[(reducer, a["key"], a["id"])] = a
        elif reducer == "RK-ONCE":
            evidence[(reducer, a["key"], a["group"], a["id"])] = a
        elif reducer == "RK-LIFECYCLE":
            lifecycle.append(a)
        elif reducer == "RK-AUTH":
            evidence[(reducer, a["id"])] = a  # revocation may change old validity
        elif reducer == "RK-EPOCH":
            epochs.append(a)
        elif reducer == "RK-RECORD":
            evidence[(reducer, a["key"], a["id"])] = a  # put payloads and named deletes
        elif reducer == "RK-ANNOTATION":
            annotations.append(a)
        elif reducer == "RK-ASSET":
            evidence[(reducer, a["id"])] = a  # every graph edge and removal
        elif reducer == "RK-FONT":
            evidence[(reducer, a["id"])] = a  # all observed adds/removals
        elif reducer == "RK-DIAG":
            evidence[(reducer, a["key"], a["group"], a["id"])] = a
        elif reducer == "RK-LEGACY":
            digest = a.get("source", {}).get("payload", {}).get("digest", a["id"])
            evidence[(reducer, digest, a["id"])] = a
        elif reducer == "RK-OPAQUE":
            evidence[(reducer, a["id"])] = a
        else:
            raise AssertionError(("unhandled reducer", reducer))
    # Deletions and purges are durable witnesses. A restore need only survive if
    # it wins a named-deletion or observed-expiry slot; malformed references stay.
    deletions = {a["id"]: a["source"] for a in lifecycle
                 if a["source"]["kind"].endswith(".delete")}
    purges = {a["id"]: a["source"] for a in lifecycle
              if a["source"]["kind"].endswith(".purge")}
    lifecycle_lookup = {a["id"]: a["source"] for a in lifecycle}
    def scope(op):
        return set(op.get("payload", {}).get("scope", [op["target"]]))
    restore_slots = {}
    for a in lifecycle:
        op = a["source"]
        if not op["kind"].endswith(".restore"):
            evidence[("RK-LIFECYCLE", a["id"])] = a
            continue
        names = op.get("observed", {}).get("deletions", [])
        expiry = op.get("observed", {}).get("observedExpiry", [])
        if (not names or any(name not in deletions or
                             deletions[name]["kind"].split(".")[0] != op["kind"].split(".")[0] or
                             not scope(deletions[name]) & scope(op) for name in names) or
                any(e not in purges or purges[e].get("payload", {}).get("reason") != "expired" or
                    not valid_native_purge(purges[e], lifecycle_lookup) or
                    not scope(purges[e]) & scope(op) or purges[e]["stamp"][0] >= op["stamp"][0]
                    for e in expiry)):
            evidence[("RK-LIFECYCLE", a["id"])] = a
            continue
        union_scope = set().union(*(scope(deletions[name]) for name in names))
        if not op.get("payload", {}).get("administrative") and not union_scope <= scope(op):
            evidence[("RK-LIFECYCLE", a["id"])] = a
            continue
        if any(not any(key in scope(deletions[name]) for name in names) for key in scope(op)):
            evidence[("RK-LIFECYCLE", a["id"])] = a  # per-lineage invalid witness
        for name in names:
            for key in scope(op) & scope(deletions[name]):
                for slot in [(key, name, None)] + [(key, name, e) for e in expiry]:
                    old = restore_slots.get(slot)
                    if old is None or rank(a) > rank(old):
                        restore_slots[slot] = a
    for a in restore_slots.values():
        evidence[("RK-LIFECYCLE", a["id"])] = a
    # Add/remove identities remain available for named references; group edits
    # compact to the greatest fact separately for every named epoch.
    epoch_slots = {}
    epoch_adds = {a["id"]: a["source"] for a in epochs if
                  a["source"]["kind"].endswith((".add", ".attach"))}
    for a in epochs:
        op = a["source"]
        if op["kind"].endswith((".add", ".attach", ".remove", ".detach")):
            evidence[("RK-EPOCH", a["key"], a["id"])] = a
            continue
        names = op.get("observed", {}).get("epochs", [])
        expected_add = (op["kind"].split(".")[0] + ".membership.add"
                        if ".membership." in op["kind"] else op["kind"].replace(".detach", ".attach"))
        if not names or any(name not in epoch_adds or
                            epoch_adds[name]["kind"] != expected_add or
                            epoch_adds[name].get("target") != a["key"] for name in names):
            evidence[("RK-EPOCH", a["key"], a["id"])] = a
            continue
        for name in names:
            slot = (a["key"], name, op["kind"])
            old = epoch_slots.get(slot)
            if old is None or rank(a) > rank(old):
                epoch_slots[slot] = a
    for a in epoch_slots.values():
        evidence[("RK-EPOCH", a["key"], a["id"])] = a
    # Each annotation source retains its add/delete facts and the winning edit
    # for every edited field, plus its greatest nonempty note/content witness.
    annotation_slots = {}
    for a in annotations:
        op = a["source"]
        if not op["kind"].endswith(".edit"):
            evidence[("RK-ANNOTATION", a["id"])] = a
            continue
        fields = op.get("payload", {})
        for field in list(fields) + ["@content"] + (["@nonemptyNote"] if fields.get("note") else []):
            slot = (a["key"], field)
            old = annotation_slots.get(slot)
            if old is None or rank(a) > rank(old):
                annotation_slots[slot] = a
    for a in annotation_slots.values():
        evidence[("RK-ANNOTATION", a["id"])] = a
    return list(evidence.values()) + list(winners.values())


def project(atoms):
    return tuple(sorted(canonical(a) for a in retain(atoms)))


def oracle_project(atoms):
    """Naive full-history reducer; never calls retain(), rank(), or project()."""
    selected = {}
    unabridged = {}
    for a in atoms:
        family = a["reducer"]
        if family in {"RK-LWW", "RK-MAX", "RK-VALUE", "RK-ENTRY", "RK-GROW"}:
            values = a["value"] if family == "RK-GROW" and isinstance(a["value"], list) else [a["value"]]
            for value in values:
                item = {**a, "value": value}
                key = (family, a["key"], a["group"],
                       ("boolean" if isinstance(value, bool) else canonical(value)) if family == "RK-GROW" else "")
                current = selected.get(key)
                if family == "RK-MAX":
                    domain = {"notPreserved": 0, "queued": 1, "preserving": 1,
                              "failed": 1, "missingFile": 1, "preserved": 2}
                    score = domain.get(value, -1) if a["group"] == "epubPreservationStatusRaw" else value
                    prior_value = current["value"] if current else None
                    prior = (domain.get(prior_value, -1) if a["group"] == "epubPreservationStatusRaw"
                             else prior_value)
                    if a["group"] in {"preservedAt", "lastPreservationAttemptAt", "lastAvailabilityCheck"}:
                        score = instant_seconds(score)
                        prior = instant_seconds(prior) if current else None
                    wins = current is None or (score, a["stamp"], a["id"]) > (prior, current["stamp"], current["id"])
                elif family == "RK-VALUE":
                    old = current["value"] if current else None
                    def independently_rank_cover(pin_value):
                        raw = pin_value.get("pinnedAt", 0)
                        seconds = float(raw) if isinstance(raw, (int, float)) else datetime.fromisoformat(
                            raw.replace("Z", "+00:00")).timestamp()
                        if seconds == 0:
                            return (seconds, int(bool(pin_value.get("fandom"))),
                                    int(bool(pin_value.get("closedRing"))), pin_value.get("tier", 0),
                                    canonical(pin_value))
                        return (seconds, 0, 0, 0, canonical(pin_value))
                    wins = current is None or (*independently_rank_cover(value), a["stamp"], a["id"]) > (
                        *independently_rank_cover(old), current["stamp"], current["id"])
                elif family == "RK-GROW" and isinstance(value, bool):
                    wins = current is None or (value, a["stamp"], a["id"]) > (
                        current["value"], current["stamp"], current["id"])
                else:
                    wins = current is None or (a["stamp"], a["id"]) > (current["stamp"], current["id"])
                if wins:
                    selected[key] = item
        elif family not in {"RK-LIFECYCLE", "RK-EPOCH", "RK-ANNOTATION"}:
            unabridged[canonical(a)] = a
    for family in ("RK-LIFECYCLE", "RK-EPOCH", "RK-ANNOTATION"):
        facts = [a for a in atoms if a["reducer"] == family]
        if family == "RK-LIFECYCLE":
            deletes = {a["id"]: a["source"] for a in facts
                       if a["source"]["kind"].endswith(".delete")}
            expiry_ops = {a["id"]: a["source"] for a in facts
                          if a["source"]["kind"].endswith(".purge")}
            local_lifecycle = {a["id"]: a["source"] for a in facts}
            def scoped(op):
                return set(op.get("payload", {}).get("scope", [op["target"]]))
            slots = defaultdict(list)
            for a in facts:
                op = a["source"]
                if not op["kind"].endswith(".restore"):
                    unabridged[canonical(a)] = a
                    continue
                named = op.get("observed", {}).get("deletions", [])
                expiry_names = op.get("observed", {}).get("observedExpiry", [])
                malformed = (not named or any(
                    name not in deletes or deletes[name]["kind"].split(".")[0] != op["kind"].split(".")[0]
                    or not scoped(deletes[name]) & scoped(op) for name in named) or any(
                    e not in expiry_ops or expiry_ops[e].get("payload", {}).get("reason") != "expired"
                    or not valid_native_purge(expiry_ops[e], local_lifecycle)
                    or not scoped(expiry_ops[e]) & scoped(op) or expiry_ops[e]["stamp"][0] >= op["stamp"][0]
                    for e in expiry_names))
                if not malformed and not op.get("payload", {}).get("administrative"):
                    malformed = not set().union(*(scoped(deletes[name]) for name in named)) <= scoped(op)
                if malformed:
                    unabridged[canonical(a)] = a
                    continue
                if any(not any(key in scoped(deletes[name]) for name in named) for key in scoped(op)):
                    unabridged[canonical(a)] = a
                for name in named:
                    for key in scoped(op) & scoped(deletes[name]):
                        slots[(key, name, None)].append(a)
                        for e in expiry_names:
                            slots[(key, name, e)].append(a)
        elif family == "RK-EPOCH":
            slots = defaultdict(list)
            adds = {a["id"]: a["source"] for a in facts if
                    a["source"]["kind"].endswith((".add", ".attach"))}
            for a in facts:
                op = a["source"]
                if op["kind"].endswith((".add", ".attach", ".remove", ".detach")):
                    unabridged[canonical(a)] = a
                    continue
                named = op.get("observed", {}).get("epochs", [])
                add_kind = (op["kind"].split(".")[0] + ".membership.add"
                            if ".membership." in op["kind"] else op["kind"].replace(".detach", ".attach"))
                if not named or any(name not in adds or adds[name]["kind"] != add_kind or
                                    adds[name].get("target") != a["key"] for name in named):
                    unabridged[canonical(a)] = a
                    continue
                for name in named:
                    slots[(a["key"], name, op["kind"])].append(a)
        else:
            slots = defaultdict(list)
            for a in facts:
                op = a["source"]
                if not op["kind"].endswith(".edit"):
                    unabridged[canonical(a)] = a
                    continue
                fields = op.get("payload", {})
                for field in list(fields) + ["@content"] + (["@nonemptyNote"] if fields.get("note") else []):
                    slots[(a["key"], field)].append(a)
        for candidates in slots.values():
            winner = max(candidates, key=lambda x: (x["stamp"], x["id"]))
            unabridged[canonical(winner)] = winner
    return tuple(sorted([canonical(a) for a in selected.values()] + list(unabridged)))


def schedule_ids(universe, path):
    ops = universe["initial"].get("createHistory", []) + universe["ops"]
    known = {op["id"] for op in ops}
    by_id = {op["id"]: op for op in ops}
    source_keys = {op.get("target") for op in ops if op["kind"] == "annotation.add"}
    evidence_digests = {op.get("payload", {}).get("digest") for op in ops
                        if op["kind"] == "legacy.evidence"}
    event_ids = {event["id"] for event in universe.get("events", [])}
    schedules = universe["schedules"]
    per_writer = defaultdict(list)
    for op in ops:
        per_writer[op["writer"]].append(op)
    for writer, history in per_writer.items():
        history.sort(key=lambda op: op["seq"])
        assert [op["seq"] for op in history] == list(range(1, len(history) + 1)), (path, writer, "seq gap")
        counters = [op["stamp"][0] for op in history]
        assert all(a < b for a, b in zip(counters, counters[1:])), (path, writer, "counter order")
    if schedules["orders"] == "allInterleavings":
        total = math.factorial(len(universe["ops"]))
        for count in Counter(op["writer"] for op in universe["ops"]).values():
            total //= math.factorial(count)
        assert schedules["orderCount"] == total, (path, "orderCount", total)
    else:
        assert schedules["orderCount"] == len(schedules["orders"]), (path, "orderCount")
    if not schedules["missingPrerequisite"]:
        assert schedules.get("missingPrerequisiteEmptyBecause"), (path, "missing prerequisite explanation")

    for op in ops:
        expected_requires = set()
        if op["kind"] in RECORD_DELETES:
            assert "puts" in op.get("observed", {}) and "epochs" not in op["observed"], (
                path, op["id"], "record clear must name observed.puts")
        for name in op.get("requires", []):
            assert name in known, (path, op["id"], "requires", name)
            assert by_id[name]["writer"] != op["writer"], (path, op["id"], "same-writer requires", name)
        for field, value in op.get("observed", {}).items():
            if field == "gen":
                continue
            for name in value if isinstance(value, list) else [value]:
                if field == "authority" and isinstance(name, str) and name.startswith("root:"):
                    continue
                assert name in known or (field == "sources" and name in source_keys), (
                    path, op["id"], "observed." + field, name)
                # Wrong-kind/scope/counter observed-expiry references are delivered
                # and diagnosed by typed_valid(), not rejected as malformed fixtures.
                if name in known and by_id[name]["writer"] != op["writer"]:
                    expected_requires.add(name)
        for name in op.get("payload", {}).get("observedExpiry", []):
            assert name in known, (path, op["id"], "payload.observedExpiry", name)
        legacy = op.get("payload", {}).get("legacyEvidence")
        if legacy:
            assert legacy in evidence_digests, (path, op["id"], "legacyEvidence", legacy)
        assert expected_requires == set(op.get("requires", [])), (path, op["id"], "requires completeness", expected_requires)

    def check(entries, label):
        for item in entries:
            if isinstance(item, dict):
                assert set(item) in ({"op"}, {"event"}), (path, label, item)
                key = next(iter(item))
                assert item[key] in (known if key == "op" else event_ids), (path, label, item)
            else:
                assert item in known, (path, label, item)

    if isinstance(schedules["orders"], list):
        for order in schedules["orders"]:
            check(order, "orders")
    for family in ("duplicates", "restarts", "missingPrerequisite"):
        for case in schedules[family]:
            for field in ("order", "withheld", "thenDeliver", "expectedPendingAtEnd", "finalPending"):
                if field in case:
                    check(case[field], family + "." + field)
    for case in schedules["checkpoints"]:
        assert set(case["cutAfter"]).isdisjoint(case["thenOrder"]), (path, "checkpoint overlap")
        assert set(case["checkpointCut"]) == set(case["cutAfter"]), (path, "checkpoint cut ids")
        assert case["expectedAtCut"]["pending"] == [], (path, "closed cut pending")
        for field in ("cutAfter", "thenOrder", "checkpointCut"):
            check(case[field], "checkpoint." + field)
        cut = set(case["cutAfter"]) | {op["id"] for op in universe["initial"].get("createHistory", [])}
        assert set(case["cutAfter"]) | set(case["thenOrder"]) == {
            op["id"] for op in universe["ops"]}, (path, case["name"], "incomplete checkpoint partition")
        for name in cut:
            op = by_id[name]
            assert set(op.get("requires", [])) <= cut, (path, case["name"], "noncausal requires", name)
            assert all(other["id"] in cut for other in per_writer[op["writer"]]
                       if other["seq"] < op["seq"]), (path, case["name"], "writer gap", name)
        vector = {writer: max((op["seq"] for op in history if op["id"] in cut), default=0)
                  for writer, history in per_writer.items()}
        assert {k: v for k, v in vector.items() if v} == case["expectedAtCut"]["appliedVector"], (
            path, case["name"], "cut vector")
    initial_ids = {op["id"] for op in universe["initial"].get("createHistory", [])}
    for case in schedules["missingPrerequisite"]:
        def pending(delivery):
            applied = set(initial_ids)
            waiting = {name for name in delivery if name not in applied}
            while True:
                ready = {name for name in waiting if
                         set(by_id[name].get("requires", [])) <= applied and
                         all(other["id"] in applied for other in per_writer[by_id[name]["writer"]]
                             if other["seq"] < by_id[name]["seq"])}
                if not ready:
                    return waiting
                waiting -= ready
                applied |= ready
        assert pending(case["order"]) == set(case["expectedPendingAtEnd"]), (
            path, case["name"], "pending at gap", sorted(pending(case["order"])))
        if "thenDeliver" in case:
            assert pending(case["order"] + case["thenDeliver"]) == set(case.get("finalPending", [])), (
                path, case["name"], "pending after delivery")
    for case in schedules.get("incomparableCuts", []):
        for field in ("localApplied", "localUnpublished"):
            check(case[field], "incomparable." + field)
        for name in case.get("assert", {}).get("byteIdentity", []):
            assert name in known, (path, "byteIdentity", name)
        record = case.get("reservedRecord")
        if record:
            assert record["id"] in known, (path, "reserved op missing", record["id"])
            op = next(x for x in ops if x["id"] == record["id"])
            assert record["referenceEncoding"] == "utf8-sorted-keys-json-v1"
            assert bytes.fromhex(record["bytesHex"]) == canonical(op).encode(), (path, "reserved byte drift")
    intent = universe.get("localIntent")
    if intent:
        assert intent["id"] not in known, (path, "unreserved intent delivered as op")
        result = universe["expectedReservation"]
        assert result["id"] == intent["id"]
        assert all(result.get(field) == intent.get(field) for field in ("kind", "target", "payload", "observed"))
    check(universe["expected"].get("pending", []), "expected.pending")


def check_golden(universe):
    golden = universe.get("goldenReducer")
    if not golden:
        return False
    ops = universe["initial"].get("createHistory", []) + universe["ops"]
    summary = retain([a for op in ops for a in expand(op)])
    projected = project(summary)
    assert projected == oracle_project([a for op in ops for a in expand(op)])
    retained_ops = {a["id"]: a["source"] for a in summary if "source" in a}
    by_id = {op["id"]: op for op in ops}
    if "groups" in golden:
        actual = {a["group"]: a["value"] for a in summary if a["reducer"] == "RK-MAX"
                  and a["group"] in golden["groups"]}
        assert actual == golden["groups"], (universe["name"], "independent group golden")
        assert all(universe["expected"]["state"]["works"]["W-A"]["groups"][k] == v
                   for k, v in actual.items())
    if "livePutIds" in golden:
        puts = {op["id"] for op in retained_ops.values() if op["kind"].endswith(".put")}
        removed = {name for op in retained_ops.values() if op["kind"].endswith(".delete")
                   for name in op.get("observed", {}).get("puts", [])}
        live = sorted(puts - removed)
        seen = sorted({v for i in live for v in by_id[i]["payload"].get("seenIds", [])})
        assert live == golden["livePutIds"] and seen == golden["recordSeenIds"]
        assert universe["expected"]["state"]["records"]["tag:1"]["seenIds"] == seen
    if "validRestoreIds" in golden:
        restores = [op for op in retained_ops.values() if op["kind"] == "work.restore"]
        valid_restores = []
        for restore in restores:
            named = restore.get("observed", {}).get("deletions", [])
            if named and typed_valid(restore):
                valid_restores.append(restore["id"])
        revokes = [op for op in retained_ops.values() if op["kind"] == "writer.revoke"]
        authorized_expiry = sorted(op["id"] for op in retained_ops.values() if op["kind"] == "work.purge"
                                   and op["payload"]["reason"] == "expired"
                                   and not any(r["target"] == op["writer"] and
                                               r["stamp"] < op["stamp"] for r in revokes))
        assert sorted(valid_restores) == golden["validRestoreIds"]
        assert authorized_expiry == golden["authorizedExpiryIds"]
        assert universe["expected"]["state"]["works"]["W-A"]["lifecycle"] == "live"
        assert lifecycle_golden_diagnostics(summary) == universe["expected"]["diagnostics"]
    for cut in universe["schedules"]["checkpoints"]:
        names = set(cut["cutAfter"])
        cut_atoms = retain([a for op in ops if op["id"] in names or op in
                            universe["initial"].get("createHistory", []) for a in expand(op)])
        assert project(cut_atoms) == oracle_project([a for op in ops if op["id"] in names or op in
                                                     universe["initial"].get("createHistory", []) for a in expand(op)])
        suffix = [a for op in ops if op["id"] in cut["thenOrder"] for a in expand(op)]
        assert project(cut_atoms + suffix) == projected, (universe["name"], cut["name"], "golden cut + suffix")
        tested_groups = set().union(*(golden.get(family, {}) for family in ("groups", "lww", "value")))
        for entity_class in ("works", "queues"):
            for entity_key, entity in cut["expectedAtCut"].get(entity_class, {}).items():
                for group, value in entity.get("groups", {}).items():
                    if group in tested_groups:
                        assert any(a["key"] == entity_key and a["group"] == group and
                                   a["value"] == value for a in cut_atoms), (
                            universe["name"], cut["name"], entity_key, group)
        if "validRestoreIds" in golden:
            assert lifecycle_golden_diagnostics(cut_atoms) == cut["expectedAtCut"]["diagnostics"]
    if "entries" in golden:
        actual = {a["key"]: a["value"] for a in summary if a["reducer"] == "RK-ENTRY"
                  and a["key"] in golden["entries"]}
        assert actual == golden["entries"], (universe["name"], "entry set/reset")
    if "grow" in golden:
        actual = {key: sorted(a["value"] for a in summary if a["reducer"] == "RK-GROW"
                              and a["key"] + "|" + a["group"] == key)
                  for key in golden["grow"]}
        assert actual == golden["grow"], (universe["name"], "grow union")
    if "value" in golden:
        actual = {a["group"]: a["value"] for a in summary if a["reducer"] == "RK-VALUE"
                  and a["group"] in golden["value"]}
        assert actual == golden["value"], (universe["name"], "value comparator")
    if "lww" in golden:
        actual = {a["group"]: a["value"] for a in summary if a["reducer"] == "RK-LWW"
                  and a["group"] in golden["lww"]}
        assert actual == golden["lww"], (universe["name"], "split LWW groups")
    if "typedEvidence" in golden:
        actual = {a["id"]: a["value"]["valid"] for a in summary if a["reducer"] == "RK-DIAG"
                  and a["group"] == "@typedEvidence" and a["id"] in golden["typedEvidence"]}
        assert actual == golden["typedEvidence"], (universe["name"], "typed evidence validity")
    return True


def lifecycle_golden_diagnostics(summary):
    """Independent single-lineage diagnostic oracle for g1's named cut."""
    ops = {a["id"]: a["source"] for a in summary if a["reducer"] in
           {"RK-LIFECYCLE", "RK-AUTH"} and "source" in a}
    diagnostics = []
    for purge in ops.values():
        if purge["kind"] != "work.purge" or purge.get("payload", {}).get("reason") != "expired":
            continue
        key = purge["target"]
        if any(op["kind"] == "writer.revoke" and op["target"] == purge["writer"] and
               op["stamp"] < purge["stamp"] for op in ops.values()):
            diagnostics.append({"kind": "unauthorizedPurge", "key": key, "witness": purge["id"]})
            continue
        basis = purge.get("observed", {}).get("basis", [])
        observing = [op for op in ops.values() if op["kind"] == "work.restore" and
                     set(op.get("observed", {}).get("deletions", [])) & set(basis) and
                     purge["id"] in op.get("observed", {}).get("observedExpiry", [])]
        if observing:
            winner = max(observing, key=lambda op: (op["stamp"], op["id"]))
            diagnostics.extend([
                {"kind": "expiryInvalidated", "key": key, "witness": purge["id"],
                 "detail": "restored"},
                {"kind": "restoredAfterExpiry", "key": key, "witness": winner["id"],
                 "detail": purge["id"]}])
    return sorted(diagnostics, key=lambda d: (d["kind"], d["key"], d.get("witness", ""),
                                              d.get("detail", "")))


def check_order(ops, order):
    full = [a for i in order for a in expand(ops[i])]
    expected = project(full)
    assert expected == oracle_project(full), ("oracle final", order)
    for cut in range(len(order) + 1):
        prefix = [a for i in order[:cut] for a in expand(ops[i])]
        suffix = [a for i in order[cut:] for a in expand(ops[i])]
        assert project(retain(prefix) + suffix) == expected, ("cut", cut)
        assert project(retain(prefix) + suffix) == oracle_project(prefix + suffix), ("oracle cut", cut)
    return expected


def check_queue_links(universe):
    """Small state golden for Q2's live queue and saved-search prerequisite."""
    expected = universe["expected"]["state"].get("queueSavedSearchLinks")
    if expected is None:
        return False
    ops = universe["initial"].get("createHistory", []) + universe["ops"]
    assert not any(op["kind"] in {"queue.delete", "queue.restore", "queue.purge"}
                   for op in ops), (universe["name"], "Q2 golden needs lifecycle evaluator")
    def visible_links(history):
        queues = {op["target"] for op in history if op["kind"] == "queue.create"}
        searches = {op["id"]: op for op in history if op["kind"] == "savedSearch.put"}
        removed = {name for op in history if op["kind"] == "savedSearch.delete"
                   for name in op.get("observed", {}).get("puts", [])}
        live_searches = {op["target"] for name, op in searches.items() if name not in removed}
        cleared = {name for op in history if op["kind"] == "queueSavedSearchLink.clear"
                   for name in op.get("observed", {}).get("puts", [])}
        links = {}
        for op in history:
            if op["kind"] != "queueSavedSearchLink.set" or op["id"] in cleared:
                continue
            queue, search = op["target"].split("|", 1)
            if queue in queues and search in live_searches:
                old = links.get(op["target"])
                if old is None or (op["stamp"], op["id"]) > (old["stamp"], old["id"]):
                    links[op["target"]] = op
        return [{"queue": op["target"].split("|", 1)[0],
                 "savedSearch": op["target"].split("|", 1)[1],
                 **op["payload"]} for op in links.values()]
    actual = visible_links(ops)
    assert sorted(map(canonical, actual)) == sorted(map(canonical, expected)), (
        universe["name"], "Q2 link projection", actual, expected)
    first_search = next((i for i, op in enumerate(ops) if op["kind"] == "savedSearch.put"), None)
    if first_search is not None and any(op["kind"] == "queueSavedSearchLink.set"
                                        for op in ops[:first_search]):
        assert visible_links(ops[:first_search]) == [], (universe["name"], "Q2 fact-first cut")
    return True


def queue_tag_display(ops, target):
    """T2q display spelling from live attach epochs for one original endpoint."""
    removed = {name for op in ops if op["kind"] == "queueTag.detach" and op["target"] == target
               for name in op.get("observed", {}).get("epochs", [])}
    live = [op for op in ops if op["kind"] == "queueTag.attach" and
            op["target"] == target and op["id"] not in removed]
    return max(live, key=lambda op: (op["stamp"], op["id"]))["payload"]["tag"] if live else None


def check_round9_regressions():
    """Small semantic counterexamples for review-8 findings 2–4."""
    previous = EVIDENCE_CONTEXT.copy()
    def op(id, counter, kind, target=None, payload=None, observed=None):
        item = {"id": id, "writer": "inc-r9", "seq": counter,
                "stamp": [counter, "inc-r9", counter], "kind": kind,
                "payload": payload or {}, "observed": observed or {}}
        if target is not None:
            item["target"] = target
        return item
    try:
        write = op("w", 1, "asset.write", "W-A", {"assetKind": "epub", "digest": "d", "size": 1})
        remove = op("rm", 2, "asset.remove", payload={"owner": "W-A", "assetKind": "epub"},
                    observed={"names": ["w"]})
        EVIDENCE_CONTEXT.clear(); EVIDENCE_CONTEXT.update({x["id"]: x for x in (write, remove)})
        assert typed_valid(remove)
        marker = next(a for a in expand(remove) if a["group"] == "@typedEvidence")
        assert marker["value"]["owner"] == "W-A" and marker["value"]["valid"]
        assert not typed_valid(op("empty", 3, "asset.remove", payload=remove["payload"],
                                  observed={"names": []}))
        assert not typed_valid(op("empty-record", 4, "bookmark.delete", "bookmark:x",
                                  observed={"puts": []}))

        a1 = op("a1", 1, "queue.membership.add", "q1|W-A")
        a2 = op("a2", 2, "queue.membership.add", "q1|W-B")
        m1 = op("m1", 3, "queue.membership.move", "q1|W-A", {"rank": 5}, {"epochs": ["a1"]})
        bad = op("bad", 4, "queue.membership.move", "q1|W-A", {"rank": 99},
                 {"epochs": ["a1", "a2"]})
        EVIDENCE_CONTEXT.clear(); EVIDENCE_CONTEXT.update({x["id"]: x for x in (a1, a2, m1, bad)})
        epoch_atoms = [atom(x, "RK-EPOCH", value=x["payload"]) for x in (a1, a2, m1, bad)]
        kept = {a["id"] for a in retain(epoch_atoms)}
        assert {"m1", "bad"} <= kept and not typed_valid(bad)
        assert project(epoch_atoms) == oracle_project(epoch_atoms)
        m2 = op("m2", 5, "queue.membership.move", "q1|W-A", {"rank": 6}, {"epochs": ["a1"]})
        assert "m1" not in {a["id"] for a in retain(epoch_atoms + [atom(m2, "RK-EPOCH", value=m2["payload"])])}
        state1 = op("state1", 6, "queue.membership.state", "q1|W-A",
                    {"state": "reading"}, {"epochs": ["a1"]})
        state2 = op("state2", 7, "queue.membership.state", "q1|W-A",
                    {"state": "paused", "note": None}, {"epochs": ["a1"]})
        state_atoms = [atom(x, "RK-EPOCH", value=x["payload"]) for x in (a1, state1, state2)]
        assert {a["id"] for a in retain(state_atoms)} == {"a1", "state2"}
        assert project(state_atoms) == oracle_project(state_atoms)

        d = op("d", 1, "work.delete", "W-A", {"scope": ["W-A"]})
        r0 = op("r0", 2, "work.restore", "W-A", {"scope": ["W-A"]}, {"deletions": ["d"]})
        r1 = op("r1", 3, "work.restore", "W-A", {"scope": ["W-A", "W-B"]},
                {"deletions": ["d"]})
        EVIDENCE_CONTEXT.clear(); EVIDENCE_CONTEXT.update({x["id"]: x for x in (d, r0, r1)})
        life_atoms = [atom(x, "RK-LIFECYCLE", value=x["payload"]) for x in (d, r0, r1)]
        assert typed_valid(r1) and {a["id"] for a in retain(life_atoms)} == {"d", "r1"}
        assert project(life_atoms) == oracle_project(life_atoms)
        wide = op("wide", 4, "work.delete", "W-A", {"scope": ["W-A", "W-B"]})
        mixed = op("mixed", 5, "work.restore", "W-A", {"scope": ["W-A", "W-C"]},
                   {"deletions": ["wide"]})
        mixed_purge = op("mixed-p", 6, "work.purge", "W-A",
                         {"reason": "explicit", "scope": ["W-A", "W-C"]}, {"basis": ["wide"]})
        evidence = op("ev", 7, "legacy.evidence", payload={"verified": True,
                       "adopted": True, "digest": "d"})
        bad_expiry = op("bad-expiry", 8, "work.purge", "W-A", {"reason": "expired"},
                        {"basis": [], "evidence": ["ev"]})
        wrong_digest = op("wrong-digest", 9, "work.purge", "W-A",
                          {"reason": "explicit", "legacyEvidence": "other"},
                          {"basis": [], "evidence": ["ev"]})
        observing = op("observing", 10, "work.restore", "W-A", {"scope": ["W-A"]},
                       {"deletions": ["d"], "observedExpiry": ["bad-expiry"]})
        extra = (wide, mixed, mixed_purge, evidence, bad_expiry, wrong_digest, observing)
        EVIDENCE_CONTEXT.update({x["id"]: x for x in extra})
        assert all(not typed_valid(x) for x in (mixed, mixed_purge, bad_expiry,
                                                wrong_digest, observing))
        extended = life_atoms + [atom(x, "RK-LIFECYCLE", value=x["payload"]) for x in extra
                                 if x["kind"].startswith("work.")]
        assert "r1" in {a["id"] for a in retain(extended)}
        assert project(extended) == oracle_project(extended)

        status = {name: None for name in READING_STATUS_FIELDS}
        status_op = op("status", 1, "work.edit", "W-A", {"groups": {"readingStatus": status}})
        fields = expand_semantic(status_op)
        assert (len(fields) == 1 and fields[0]["reducer"] == "RK-LWW" and
                fields[0]["group"] == "readingStatus" and fields[0]["value"] == status)
        try:
            expand_semantic(op("split", 2, "work.edit", "W-A", {"groups": {"statusWasRecorded": True}}))
        except AssertionError:
            pass
        else:
            raise AssertionError("split reading-status field admitted")
        t1 = op("t1", 2, "queueTag.attach", "q1|wip", {"tag": "WIP"})
        t2 = op("t2", 3, "queueTag.attach", "q1|wip", {"tag": "wip"})
        detach = op("td", 4, "queueTag.detach", "q1|wip", observed={"epochs": ["t2"]})
        EVIDENCE_CONTEXT.clear(); EVIDENCE_CONTEXT.update({x["id"]: x for x in (t1, t2, detach)})
        assert len(expand_semantic(detach)) == 1 and typed_valid(detach)
        assert queue_tag_display((t1, t2), "q1|wip") == "wip"
        assert queue_tag_display((t1, t2, detach), "q1|wip") == "WIP"
    finally:
        EVIDENCE_CONTEXT.clear(); EVIDENCE_CONTEXT.update(previous)


def main():
    schema = json.loads((ROOT / "_schema.json").read_text())
    check_round9_regressions()
    matrix = (ROOT.parent / "SYNC_OPERATION_MATRIX.md").read_text()
    assert all("`" + k + "`" in matrix for k in KINDS), "matrix missing reducer kind"
    files = sorted(p for p in ROOT.glob("*.json") if not p.name.startswith("_"))
    fixture_cases = 0
    exhaustive = 0
    sampled = 0
    goldens = 0
    link_goldens = 0
    seen = set()
    for path in files:
        doc = json.loads(path.read_text())
        schema_check(doc, schema, schema, path.name)
        for universe in doc.get("universes", []):
            fixture_cases += 1
            ops = universe["initial"].get("createHistory", []) + universe["ops"]
            EVIDENCE_CONTEXT.clear()
            EVIDENCE_CONTEXT.update({op["id"]: op for op in ops})
            ids = [op["id"] for op in ops]
            assert len(ids) == len(set(ids)), (path.name, universe["name"], "duplicate op id")
            for op in ops:
                assert op["stamp"] == [op["stamp"][0], op["writer"], op["seq"]], op
            schedule_ids(universe, path.name + ":" + universe["name"])
            goldens += check_golden(universe)
            link_goldens += check_queue_links(universe)
            for op in ops:
                for a in expand(op):
                    seen.add(a["reducer"])
            n = len(ops)
            orders = itertools.permutations(range(n)) if n <= 5 else [
                tuple(range(n)), tuple(reversed(range(n)))]
            baseline = None
            for order in orders:
                actual = check_order(ops, order)
                if baseline is None:
                    baseline = actual
                assert actual == baseline, (path.name, universe["name"], "arrival")
                if n <= 5:
                    exhaustive += 1
                else:
                    sampled += 1
    print(f"schema + matrix: {len(files)} fixtures validated; {len(KINDS)} closed reducer kinds named")
    print(f"fixture reducers: {fixture_cases} universes, {exhaustive} exhaustive orders (<=5), {sampled} larger orders; cuts and arrival order equal")
    print(f"goldens + references: {goldens} independent semantic goldens checked; every scheduled op/event/intent resolved")
    print(f"Q2 link projection: {link_goldens} live-endpoint golden checked")
    print("round-9 regressions: asset owner/empty references, epoch/lifecycle validity, atomic reading status and queue-tag casing passed")
    rng = random.Random(56905)
    reducers = sorted(KINDS)
    for case in range(2400):
        kind = reducers[case % len(reducers)]
        atoms = []
        for i in range(rng.randrange(1, 8)):
            val = rng.randrange(1, 20)
            if kind == "RK-GROW":
                val = [val, (val + 1) % 20]
            if kind == "RK-VALUE":
                val = {"pinnedAt": f"2026-01-{val:02}T00:00:00Z", "value": val}
            atoms.append({"reducer": kind, "id": f"f{case}-{i}",
                          "stamp": [rng.randrange(1, 12), "inc-a" if i % 2 else "inc-b", i + 1],
                          "key": "K", "group": "seriesPosition" if kind == "RK-MAX" else "g",
                          "value": val, **({"source": {"kind": kind, "id": i}}
                                       if kind not in {"RK-LWW", "RK-MAX", "RK-VALUE", "RK-ENTRY", "RK-GROW"} else {})})
        if kind in {"RK-LIFECYCLE", "RK-EPOCH", "RK-ANNOTATION"}:
            def sample_op(id, stamp, op_kind, payload=None, observed=None):
                return {"id": id, "writer": "inc-a", "seq": stamp,
                        "stamp": [stamp, "inc-a", stamp], "kind": op_kind,
                        "target": "K", "payload": payload or {}, "observed": observed or {}}
            if kind == "RK-LIFECYCLE":
                source = [sample_op("d", 1, "work.delete"),
                          sample_op("r0", 2, "work.restore", observed={"deletions": ["d"]}),
                          sample_op("r1", 3, "work.restore", observed={"deletions": ["d"]})]
            elif kind == "RK-EPOCH":
                source = [sample_op("a", 1, "queue.membership.add"),
                          sample_op("m0", 2, "queue.membership.move", {"rank": 4}, {"epochs": ["a"]}),
                          sample_op("m1", 3, "queue.membership.move", {"rank": 2}, {"epochs": ["a"]})]
            else:
                source = [sample_op("a", 1, "annotation.add", {"note": "initial"}),
                          sample_op("e0", 2, "annotation.edit", {"note": "earlier"}),
                          sample_op("e1", 3, "annotation.edit", {"note": "later"})]
            atoms = [atom(op, kind, value=op["payload"]) for op in source]
            assert len(retain(atoms)) == 2, (case, kind, "semantic reduction")
        expected = oracle_project(atoms)
        assert project(atoms + atoms) == expected, (case, kind, "duplicate reduction")
        for order in (atoms, list(reversed(atoms)), rng.sample(atoms, len(atoms))):
            assert project(order) == expected, (case, "arrival")
            for cut in range(len(order) + 1):
                assert project(retain(order[:cut]) + order[cut:]) == expected, (case, cut)
    assert set(reducers) == KINDS
    print(f"seeded fuzz: 2400 cases, {len(KINDS)} reducer kinds explicitly summarized, duplicate delivery, all cuts and 3 arrival orders equal (seed 56905)")


if __name__ == "__main__":
    main()
