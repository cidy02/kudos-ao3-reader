# Follow-up questions for the external reviewers — round 2

Round 1 is answered and closed. Every checkable claim from those replies was
verified against primary sources; the scoreboard and evidence live in
[`TTS_IMPROVEMENT_PLAN.md`](TTS_IMPROVEMENT_PLAN.md) §6.

Each section below is self-contained — paste only the section for that model.
Context is repeated deliberately because the model will not remember the thread.

---

## For Grok

Your StyleTTS 2 citation checked out: arXiv:2306.07691 Appendix B.3
"Consistent Long-Form Generation", Algorithm 1, convex combination of style
vectors. Your quote of the LibriTTS notebook was verbatim correct, including
the comment. That is twice now that a citation of yours has held up exactly, so
you are the reviewer I most want to press on sources.

**Context:** iOS fanfiction reader, offline Kokoro-82M via Core ML, model
frozen, no diffusion sampler. I already SLERP style vectors for voice blending.

**Question 1 — the paper and the code disagree, and you quoted only the code.**

| Source | Expression | α = 0.7 means |
|---|---|---|
| Paper, Algorithm 1 | `s_curr ← α·s_curr + (1−α)·s_prev` | 70% **current** |
| `Demo/Inference_LJSpeech.ipynb` | `s_pred = alpha * s_prev + (1 - alpha) * s_pred` | 70% **previous** |
| `Demo/Inference_LibriTTS.ipynb` | `s_pred = t * s_prev + (1 - t) * s_pred` | 70% **previous** |

Same symbol, same value, opposite meaning. You told me "≈ 0.7 (70% previous
style + 30% newly sampled style)", which matches the code and contradicts the
paper's own algorithm.

Which is the intended method? Specifically: is the paper's Algorithm 1 a typo
that the code corrects, is the code the deviation, or do they define `s_prev`
differently in a way that reconciles them? If you are not sure, say so — I
would rather implement it as "70% previous, following the reference code, paper
disagrees" than silently pick one.

**Question 2 — should the persistence blend treat the two halves separately?**

I verified the 256-vector splits at 128 and the halves go to different stages —
`[0..<128]` timbre into Noise/Vocoder, `[128..<256]` into duration prediction
and prosody. The LibriTTS notebook blends the halves against the reference with
**separate** weights (`alpha = 0.3` on `ref_s[:, :128]`, `beta = 0.7`–`0.9` on
`ref_s[:, 128:]`), but the persistence step you quoted applies one weight to
the whole vector.

Is that deliberate, or just convenient? For long-form continuity I would think
you want the *timbre* half strongly persistent (voice identity shouldn't drift
sentence to sentence) and the *prosody* half only weakly so (each sentence
needs its own rhythm). Did the authors consider per-half persistence weights,
and is there any evidence either way?

---

## For GPT

Two of your claims were verified, two were wrong in instructive ways, and one
verified finding changes the problem you framed. Details below, then the
questions.

**Context:** iOS fanfiction reader (Archive of Our Own client), offline
Kokoro-82M via Core ML, model frozen. You reviewed my TTS pipeline previously.

**Your 128/128 split claim was right, and it was the most useful thing in your
reply.** Confirmed in the vendored source: `[0..<128]` = timbre → Noise +
Vocoder, `[128..<256]` = `style_s` → duration + prosody. StyleTTS 2's own
LibriTTS notebook independently blends those halves with separate weights.

**Your estimator claim was backwards.** You said my chunker undercounts because
it has no stress-mark term. The term really is missing — stress marks are a
measured 12.8% of a real phoneme string — but I measured real Misaki output
(espeak fallback for OOV names) over 7,000 grouped corpus utterances and the
estimator **over**-counts: real length is 0.866× the estimate, p5 0.79, p95
0.94, stable across all 20 works. English IPA is simply shorter than English
spelling, so the 1.15× grapheme factor over-shoots. The real defect was digits
— a digit costs ~10.3 phoneme characters against a letter's ~0.92, and a
stardate line estimated 52 against a real 102. Fixed with a digit term.

**Your Thai citation was real but mislabelled.** The numbers are in
`kunato/wayu-kokoro-thai-v1` `kokoro_thai/infer.py`, but the docstring says
`(pred/true duration, 1.00 = correct)` — they are duration ratios, not
correlations. 0.76 means predicted durations are 76% of true.

**Question 1 — AO3 pre-processes linebreaks, which narrows your problem.** You
were right that `add_paragraphs_to_text` runs on stored content. But reading
`lib/paragraph_maker.rb`, the mapping is specific:

| Author typed | AO3 stores |
|---|---|
| one newline | `<br>` |
| two newlines | a new `<p>` |
| three or more | new `<p>` plus `<p>&nbsp;</p>` |
| `<br><br>` | two `<p>`s — the `<br>`s are **removed** |
| `<br>` inside an existing `<p>` | kept |

So every multi-line break has *already* been promoted to a paragraph before I
see it. A `<br>` in my EPUB is a **single** author line break, not exporter
damage. That seems to invert your conclusion: rather than provenance being
destroyed, AO3 has pre-classified the strong breaks for me, and the residual
question is only whether a given *single* break is prosodic (verse, chat,
address) or cosmetic (hard-wrapped prose pasted from a text editor).

Does that change your feature priority list? My instinct is that it promotes
your line-length-regularity signal (hard wrapping at a consistent ~76 chars is
now the main thing left to detect) and demotes most of the DOM-structure
signals. Do you agree, and is there anything in that table that should make me
*more* cautious rather than less?

**Question 2 — does the 128/128 split change your experiment design?** You
proposed testing mismatched rows on each half independently, which I can now
do. Given that `style_timbre` never reaches the duration predictor, is there
any mechanism by which mismatching *only* the timbre half could still affect
timing or intelligibility — or is that experiment as safe as it looks, and
therefore the one to run first?

---

## For DeepSeek

Your retraction on `VNCoreMLModel` and iOS 18+ was appreciated and correct. I
then verified the one novel claim, and it did not hold. Reporting it plainly
because it matters more than the individual item.

**Context:** iOS fanfiction reader, offline Kokoro-82M via Core ML, model
frozen. You reviewed my TTS pipeline previously.

**The arrow tokens are Mandarin lexical tones, not Japanese pitch accent.**
From `misaki/zh.py`, `ZHG2P.retone`:

```python
p = p.replace('˧˩˧', '↓')  # third tone
p = p.replace('˧˥',  '↗')  # second tone
p = p.replace('˥˩',  '↘')  # fourth tone
p = p.replace('˥',   '→')  # first tone
```

Chao tone letters mapped onto the arrows. Misaki's English vocabulary does not
contain them at all (`US_VOCAB`/`GB_VOCAB` in `misaki/en.py`; `EN_PHONES.md`
lists 49 phonemes with stress as `ˈ`/`ˌ`), and the Japanese path has its arrow
emission commented out in favour of `_ ^ -`. There is no heiban/kaku layer.

I also want to flag one reasoning step, because it is the kind I need to catch:
you argued that the tokens being in the vocab "proves Kokoro saw them during
training." It does not — the vocab is shared across every language Kokoro
supports, so their presence only proves *some* language uses them. That turned
out to be Mandarin.

**Question — is there an in-distribution lever for emphasis at all?** All four
reviewers told me to emit these arrows, so I now have no proposal left for
`<em>`/`<i>`, which is common in fic and currently parsed and discarded. Given
that the only inputs Kokoro actually responds to are the phoneme string,
punctuation tokens, and a style vector selected by phoneme length:

1. Is there anything in the *English* phoneme inventory that shifts perceived
   emphasis — moving or adding stress marks (`ˈ`/`ˌ`) on an emphasised word,
   for instance? Is promoting secondary to primary stress a known technique, or
   does it just corrupt the word?
2. Punctuation carries prosody in this model. Is bracketing an emphasised
   phrase with commas a real technique, or does it just insert pauses?
3. If the honest answer is "there is no good lever without retraining", say
   that. I would rather drop the feature than ship something that degrades.

Please flag which parts are established practice and which are your own
inference — that distinction is what I ended up needing most from round 1.
