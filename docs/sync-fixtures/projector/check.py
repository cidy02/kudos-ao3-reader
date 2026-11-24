#!/usr/bin/env python3
"""Standard-library reference for D4 reducer retention algebra.

This checks the fixture envelope and reducer contract against an independent
naive reducer. It does not implement D5 transport or the v8 shipped merge.
"""
import itertools
import json
import random
import re
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
    "annotation.edit": "RK-ANNOTATION", "annotation.delete": "RK-ANNOTATION",
    "rec.put": "RK-RECORD", "rec.delete": "RK-RECORD",
    "font.add": "RK-FONT", "font.remove": "RK-FONT",
    "original.set": "RK-ONCE", "taglist.add": "RK-GROW",
    "setting.entry.set": "RK-ENTRY", "setting.entry.reset": "RK-ENTRY",
    "pronunciation.set": "RK-ENTRY", "pronunciation.reset": "RK-ENTRY",
    "future.thing": "RK-OPAQUE",
    "followedTag.put": "RK-RECORD", "followedTag.delete": "RK-RECORD",
}
GROUPS = {"seriesPosition": "RK-MAX", "preservationStatus": "RK-MAX",
          "preservedAt": "RK-MAX", "lastPreservationAttemptAt": "RK-MAX",
          "lastAvailabilityCheck": "RK-MAX", "coverRecipeJSON": "RK-VALUE",
          "coverPin": "RK-VALUE", "importSource": "RK-ONCE",
          "hasGivenKudos": "RK-GROW", "ao3Unavailable": "RK-GROW",
          "workTagsFetched": "RK-GROW", "workTags": "RK-GROW",
          "warnings": "RK-GROW", "categories": "RK-GROW",
          "fandoms": "RK-GROW", "characters": "RK-GROW",
          "relationships": "RK-GROW", "freeforms": "RK-GROW",
          "provenance": "RK-ONCE"}


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


def expand(op):
    facts = expand_semantic(op)
    # A covered reference still needs typed evidence after its value lost a
    # register. This compact marker models the checkpoint evidence index.
    marker = atom(op, "RK-DIAG", "@typedEvidence", {
        "kind": op["kind"], "owner": op.get("target", ""),
        "valid": True})
    marker.pop("source")
    facts.append(marker)
    if op["kind"] in {"work.create", "work.edit"} and op.get("payload", {}).get("groups"):
        facts.append(atom(op, "RK-LWW", "@greatestContent", op["id"]))
    return facts


def expand_semantic(op):
    kind = op["kind"]
    payload = op.get("payload", {})
    if kind in {"work.create", "work.edit", "queue.create", "collection.create"}:
        out = []
        if kind in {"work.create", "queue.create", "collection.create"}:
            out.append(atom(op, "RK-IDENTITY", value={
                "ao3WorkID": payload.get("ao3WorkID"), "urls": payload.get("urls", []),
                "supersedes": payload.get("supersedes"), "entityClass": kind.split(".")[0],
                "entityKind": payload.get("kind")}))
        malformed = payload.get("malformed", [])
        for group, value in payload.get("groups", {}).items():
            reducer = GROUPS.get(group, "RK-LWW")
            if group in malformed or (isinstance(value, dict) and value.get("malformed")):
                out.append(atom(op, "RK-DIAG", group, {"error": "malformedGroup"}))
            else:
                suffix = "|" + str(payload["forDigest"]) if "forDigest" in payload else ""
                out.append(atom(op, reducer, group + suffix, value))
        return out
    assert kind in DISPATCH, ("unmapped operation kind", kind)
    reducer = DISPATCH[kind]
    if payload.get("malformed") and reducer == "RK-ENTRY":
        return [atom(op, "RK-DIAG", kind, {"error": "malformedGroup"})]
    return [atom(op, reducer, kind if reducer == "RK-ENTRY" else payload.get("group", ""),
                 payload.get("value", payload))]


def rank(a):
    v = a["value"]
    if a["reducer"] == "RK-MAX":
        if a["group"] == "preservationStatus":
            v = {"notPreserved": 0, "queued": 1, "preserving": 2,
                 "preserved": 3}.get(v, -1)
        return (v, tuple(a["stamp"]), a["id"])
    if a["reducer"] == "RK-VALUE":
        pin = v.get("pinnedAt", "") if isinstance(v, dict) else ""
        return (pin, canonical(v), tuple(a["stamp"]), a["id"])
    return (tuple(a["stamp"]), a["id"])


def retain(atoms):
    winners = {}
    kept = {}
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
                key = (reducer, a["key"], a["group"], canonical(val))
                old = winners.get(key)
                single = {**a, "value": val}
                if old is None or rank(single) > rank(old):
                    winners[key] = single
        else:
            kept[canonical(a)] = a
    kept.update({canonical(a): a for a in winners.values()})
    return list(kept.values())


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
                key = (family, a["key"], a["group"], canonical(value) if family == "RK-GROW" else "")
                current = selected.get(key)
                if family == "RK-MAX":
                    domain = {"notPreserved": 0, "queued": 1,
                              "preserving": 2, "preserved": 3}
                    score = domain.get(value, -1) if a["group"] == "preservationStatus" else value
                    prior_value = current["value"] if current else None
                    prior = (domain.get(prior_value, -1) if a["group"] == "preservationStatus"
                             else prior_value)
                    wins = current is None or (score, a["stamp"], a["id"]) > (prior, current["stamp"], current["id"])
                elif family == "RK-VALUE":
                    pin = value.get("pinnedAt", "") if isinstance(value, dict) else ""
                    old = current["value"] if current else None
                    old_pin = old.get("pinnedAt", "") if isinstance(old, dict) else ""
                    wins = current is None or (pin, canonical(value), a["stamp"], a["id"]) > (
                        old_pin, canonical(old), current["stamp"], current["id"])
                else:
                    wins = current is None or (a["stamp"], a["id"]) > (current["stamp"], current["id"])
                if wins:
                    selected[key] = item
        else:
            unabridged[canonical(a)] = a
    return tuple(sorted([canonical(a) for a in selected.values()] + list(unabridged)))


def schedule_ids(universe, path):
    ops = universe["initial"].get("createHistory", []) + universe["ops"]
    known = {op["id"] for op in ops}
    source_keys = {op.get("target") for op in ops if op["kind"] == "annotation.add"}
    evidence_digests = {op.get("payload", {}).get("digest") for op in ops
                        if op["kind"] == "legacy.evidence"}
    event_ids = {event["id"] for event in universe.get("events", [])}
    schedules = universe["schedules"]

    for op in ops:
        for name in op.get("requires", []):
            assert name in known, (path, op["id"], "requires", name)
        for field, value in op.get("observed", {}).items():
            if field == "gen":
                continue
            for name in value if isinstance(value, list) else [value]:
                if field == "authority" and isinstance(name, str) and name.startswith("root:"):
                    continue
                assert name in known or (field == "sources" and name in source_keys), (
                    path, op["id"], "observed." + field, name)
        for name in op.get("payload", {}).get("observedExpiry", []):
            assert name in known, (path, op["id"], "payload.observedExpiry", name)
        legacy = op.get("payload", {}).get("legacyEvidence")
        if legacy:
            assert legacy in evidence_digests, (path, op["id"], "legacyEvidence", legacy)

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
        for field in ("cutAfter", "thenOrder", "checkpointCut"):
            check(case[field], "checkpoint." + field)
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
    by_id = {op["id"]: op for op in ops}
    if "groups" in golden:
        candidates = {}
        for op in ops:
            for group, value in op.get("payload", {}).get("groups", {}).items():
                candidates.setdefault(group, []).append((value, op["stamp"], op["id"]))
        status_order = {"notPreserved": 0, "queued": 1, "preserving": 2, "preserved": 3}
        actual = {}
        for group in golden["groups"]:
            choices = candidates[group]
            if group == "preservationStatus":
                actual[group] = max(choices, key=lambda x: (status_order[x[0]], x[1], x[2]))[0]
            else:
                actual[group] = max(choices, key=lambda x: (x[0], x[1], x[2]))[0]
        assert actual == golden["groups"], (universe["name"], "independent group golden")
        assert universe["expected"]["state"]["works"]["W-A"]["groups"].items() >= actual.items()
    if "livePutIds" in golden:
        puts = {op["id"] for op in ops if op["kind"].endswith(".put")}
        removed = {name for op in ops if op["kind"].endswith(".delete")
                   for name in op.get("observed", {}).get("puts", [])}
        live = sorted(puts - removed)
        seen = sorted({v for i in live for v in by_id[i]["payload"].get("seenIds", [])})
        assert live == golden["livePutIds"] and seen == golden["recordSeenIds"]
        assert universe["expected"]["state"]["records"]["tag:1"]["seenIds"] == seen
    if "validRestoreIds" in golden:
        restores = [op for op in ops if op["kind"] == "work.restore"]
        valid_restores = []
        for restore in restores:
            named = restore.get("observed", {}).get("deletions", [])
            expiry_ids = restore.get("observed", {}).get("observedExpiry", [])
            if named and all(by_id[i]["kind"] == "work.delete" for i in named) and all(
                    by_id[i]["kind"] == "work.purge" and
                    by_id[i]["payload"]["reason"] == "expired" and
                    by_id[i]["stamp"][0] < restore["stamp"][0] for i in expiry_ids):
                valid_restores.append(restore["id"])
        revokes = [op for op in ops if op["kind"] == "writer.revoke"]
        authorized_expiry = sorted(op["id"] for op in ops if op["kind"] == "work.purge"
                                   and op["payload"]["reason"] == "expired"
                                   and not any(r["target"] == op["writer"] and
                                               r["stamp"] < op["stamp"] for r in revokes))
        assert sorted(valid_restores) == golden["validRestoreIds"]
        assert authorized_expiry == golden["authorizedExpiryIds"]
        assert universe["expected"]["state"]["works"]["W-A"]["lifecycle"] == "live"
    return True


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


def main():
    schema = json.loads((ROOT / "_schema.json").read_text())
    matrix = (ROOT.parent / "SYNC_OPERATION_MATRIX.md").read_text()
    assert all("`" + k + "`" in matrix for k in KINDS), "matrix missing reducer kind"
    files = sorted(p for p in ROOT.glob("*.json") if not p.name.startswith("_"))
    fixture_cases = 0
    exhaustive = 0
    sampled = 0
    goldens = 0
    seen = set()
    for path in files:
        doc = json.loads(path.read_text())
        schema_check(doc, schema, schema, path.name)
        for universe in doc.get("universes", []):
            fixture_cases += 1
            ops = universe["initial"].get("createHistory", []) + universe["ops"]
            ids = [op["id"] for op in ops]
            assert len(ids) == len(set(ids)), (path.name, universe["name"], "duplicate op id")
            for op in ops:
                assert op["stamp"] == [op["stamp"][0], op["writer"], op["seq"]], op
            schedule_ids(universe, path.name + ":" + universe["name"])
            goldens += check_golden(universe)
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
                          "stamp": [i + 1, "inc-fuzz", i + 1],
                          "key": "K", "group": "seriesPosition" if kind == "RK-MAX" else "g",
                          "value": val, **({"source": {"kind": kind, "id": i}}
                                       if kind not in {"RK-LWW", "RK-MAX", "RK-VALUE", "RK-ENTRY", "RK-GROW"} else {})})
        expected = oracle_project(atoms)
        for order in (atoms, list(reversed(atoms)), rng.sample(atoms, len(atoms))):
            assert project(order) == expected, (case, "arrival")
            for cut in range(len(order) + 1):
                assert project(retain(order[:cut]) + order[cut:]) == expected, (case, cut)
    assert set(reducers) == KINDS
    print(f"seeded fuzz: 2400 cases, {len(KINDS)} reducer kinds, all cuts and 3 arrival orders equal (seed 56905)")


if __name__ == "__main__":
    main()
