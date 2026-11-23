#!/usr/bin/env python3
"""Regenerates the byte fixtures and cases.json (both platforms' manifest-staging tests read them). Run from this folder."""
import hashlib, json

src = json.load(open('../../KudosTests/Fixtures/cross-platform/android-sync-folder/KudosLibrary/manifest.json'))
base = {k: src[k] for k in ['version', 'exportedAt', 'works', 'bookmarks', 'fonts', 'settings', 'exportedBy', 'pronunciations'] if k in src}
base['works'] = base['works'][:1]
base['bookmarks'] = []
base['fonts'] = []
text = json.dumps(base, indent=2, ensure_ascii=False) + '\n'
open('base.json', 'w').write(text)
work = base['works'][0]
OMITTED = ['annotations', 'collections', 'readingQueues', 'savedSearches']

def digest(works, version=8, omitted=OMITTED):
    proj = 'version=%d;works=%s;omitted=%s' % (version, ','.join('%s|%s' % w for w in works), ','.join(sorted(omitted)))
    return proj, hashlib.sha256(proj.encode()).hexdigest()

BASE_WORKS = [(work['id'].lower(), work['title'])]
cases = []

def add(cid, input_, outcome, note, works=BASE_WORKS, version=8):
    c = {'id': cid, 'input': input_, 'outcome': outcome, 'note': note}
    if outcome == 'ok':
        c['projection'], c['digest'] = digest(works, version)
    cases.append(c)

def splice(members='', **rep):
    d = {'splice': {'members': members}}
    if rep: d['splice']['repeat'] = rep
    return d

def write(name, data):
    open(name, 'wb').write(data)
    return {'file': name}

b = text.encode()
add('base-ok', {'file': 'base.json'}, 'ok', 'a minimal valid manifest; the four omittable arrays are missing')
add('bom', write('bom.json', b'\xef\xbb\xbf' + b), 'ok', 'leading UTF-8 BOM accepted')
add('trailing-comma-object', write('trailing-comma-object.json', text.rstrip().rstrip('}').rstrip().encode() + b',\n}\n'), 'ok', 'a trailing comma in an object')
add('trailing-comma-array', write('trailing-comma-array.json', text.replace('"works": [', '"works": [', 1).replace('"fonts": []', '"fonts": [,]', 1).encode()), 'notJSON', 'a lone comma in an array is not a trailing comma')
add('root-duplicate-first-wins', splice('"version":99'), 'ok', 'a later duplicate root key is ignored (first wins), even with a different value')
add('nested-duplicate-first-wins', {'file': 'nested-duplicate-first-wins.json'}, 'ok', 'inside a record the first of two equal keys wins')
open('nested-duplicate-first-wins.json', 'w').write(text.replace('"title": "%s"' % work['title'], '"title": "%s", "title": "SECOND"' % work['title'], 1))
add('nested-escaped-duplicate-first-wins', {'file': 'nested-escaped-duplicate-first-wins.json'}, 'ok', 'an escaped spelling of the same key is the same key')
open('nested-escaped-duplicate-first-wins.json', 'w').write(text.replace('"title": "%s"' % work['title'], '"title": "%s", "\\u0074itle": "SECOND"' % work['title'], 1))
add('unicode-keys-not-normalised', splice('"\u00e9":1,"e\u0301":2'), 'ok', 'a precomposed and a decomposed key are different keys (exact UTF-16, no normalisation)')
add('raw-lf-in-string', splice('"x":"a\nb"'), 'notJSON', 'raw control characters inside a string are syntax errors')
add('raw-nul-in-string', splice('"x":"a\u0000b"'), 'notJSON', 'raw U+0000 inside a string')
add('invalid-utf8-byte', write('invalid-utf8-byte.json', text.rstrip().rstrip('}').encode() + b',"x":"a\xffb"}\n'), 'notJSON', 'malformed UTF-8 is a syntax error (never replaced)')
add('fullwidth-hex-escape', splice('"x":"\\u\uff10\uff10\uff14\uff11"'), 'notJSON', 'escape hex digits are ASCII only')
add('lone-surrogate-escape', splice('"x":"\\ud800"'), 'notJSON', 'a lone surrogate escape is rejected')
add('leading-zero-number', splice('"x":08'), 'notJSON', 'JSON number grammar: no leading zero')
add('missing-comma', splice('"x":1 "y":2'), 'notJSON', 'a missing separator is a syntax error')
add('trailing-content', {'file': 'trailing-content.json'}, 'notJSON', 'anything but whitespace after the root')
open('trailing-content.json', 'w').write(text + 'x')
add('scalar-root', write('scalar-root.json', b'5'), 'notJSON', 'a top-level scalar is not JSON for this reader')
add('unsupported-version', {'file': 'unsupported-version.json'}, 'unsupportedVersion', 'version outside 1...8, everything else valid')
open('unsupported-version.json', 'w').write(text.replace('"version": 8', '"version": 9', 1))
add('works-missing', {'file': 'works-missing.json'}, 'schema', 'a required array is missing')
d = dict(base); del d['works']
open('works-missing.json', 'w').write(json.dumps(d, indent=2) + '\n')
add('works-wrong-kind', {'file': 'works-wrong-kind.json'}, 'schema', 'a required array holds an object')
d = dict(base); d['works'] = {}
open('works-wrong-kind.json', 'w').write(json.dumps(d, indent=2) + '\n')
add('documents-wrong-kind-is-absent', splice('"documents":"x"'), 'ok', 'a lossy section with the wrong kind is absent, not a failure')
add('depth-512-containers', splice('"x":', prefix='', unit='[', count=511, suffix=']' * 511) if False else {'splice': {'members': '"x":' + '[' * 511 + ']' * 511}}, 'ok', 'the root plus 511 arrays = 512 containers, the last accepted')
add('depth-513-containers', {'splice': {'members': '"x":' + '[' * 512 + ']' * 512}}, 'depth', 'the root plus 512 arrays = 513 containers: policy rejection; never eligible for .bak replacement')
add('key-65536-units', {'splice': {'repeat': {'prefix': '"', 'unit': 'k', 'count': 65536, 'suffix': '":1'}}}, 'ok', 'a key of exactly 65,536 UTF-16 units')
add('key-65537-units', {'splice': {'repeat': {'prefix': '"', 'unit': 'k', 'count': 65537, 'suffix': '":1'}}}, 'resource', 'one unit over')
add('key-emoji-65536-units', {'splice': {'repeat': {'prefix': '"', 'unit': '\U0001f600', 'count': 32768, 'suffix': '":1'}}}, 'ok', '32,768 emoji are 65,536 UTF-16 units (not graphemes, not bytes)')
add('key-emoji-65537-units', {'splice': {'repeat': {'prefix': '"', 'unit': '\U0001f600', 'count': 32768, 'suffix': 'a":1'}}}, 'resource', 'one unit over, in a key')
add('members-262144', {'splice': {'members': '"x":', 'repeat': {'prefix': '{', 'unit': '"a":0', 'separator': ',', 'count': 262144, 'suffix': '}'}}}, 'ok', 'a nested object with exactly 262,144 source members (equal keys count)')
add('members-262145', {'splice': {'members': '"x":', 'repeat': {'prefix': '{', 'unit': '"a":0', 'separator': ',', 'count': 262145, 'suffix': '}'}}}, 'resource', 'one over: source members are counted before first-wins dedupe, at every depth')
add('number-65536-digits', {'splice': {'members': '"x":', 'repeat': {'prefix': '', 'unit': '1', 'count': 65536, 'suffix': ''}}}, 'ok', 'a number token of exactly 65,536 characters')
add('number-65537-digits', {'splice': {'members': '"x":', 'repeat': {'prefix': '', 'unit': '1', 'count': 65537, 'suffix': ''}}}, 'resource', 'one over')
add('bare-word-is-syntax', {'splice': {'members': '"x":', 'repeat': {'prefix': '', 'unit': 'a', 'count': 65537, 'suffix': ''}}}, 'notJSON', 'a bare word is a syntax error, not an oversized number')

json.dump({
    'schemaVersion': 1,
    'about': 'Shared byte fixtures for the manifest.json staging readers (iOS T-567 P2, Android A-567 P2). Regenerate with generate.py.',
    'outcomeClasses': {'ok': 'staged; `digest` is sha256 of `projection`', 'notJSON': 'syntax error (eligible for .bak replacement)',
                       'schema': 'valid JSON, not a decodable manifest', 'unsupportedVersion': 'version outside 1...8',
                       'resource': 'resource exhaustion (a ManifestLimits value exceeded)', 'depth': 'more than 512 containers, root included (policy; not .bak-eligible)'},
    'projection': 'version=<n>;works=<id lowercase>|<title>,...;omitted=<sorted names among collections, readingQueues, annotations, savedSearches that are missing or null, comma separated>',
    'input': {'file': 'bytes of that file next to cases.json',
              'splice': 'document = base.json with its final "}" replaced by "," + members + "}", where members = splice.members followed by '
                        'repeat (if present) = prefix + unit repeated count times joined by separator (default empty) + suffix; all strings UTF-8'},
    'cases': cases,
}, open('cases.json', 'w'), indent=1, ensure_ascii=False)
print(len(cases), 'cases')
