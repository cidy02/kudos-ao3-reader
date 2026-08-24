# Follow-up questions for the external reviewers

Each section is self-contained — paste only the section for that model. Context
recap is deliberately included because the model will not remember the thread.

Three reviewers get questions. **Gemini gets none**: its two strongest points
(room tone under the speech and inserted pauses; condensing prolonged
vocalisations and keysmashes before G2P) are actionable as stated and need no
clarification, and its content-warning objection is a product decision for me,
not a question for it.

---

## For GPT

Two of your challenges checked out, so I'm following up on the two you raised
without a method.

**Context:** iOS fanfiction reader, offline Kokoro-82M via Core ML, model
frozen. You reviewed my TTS pipeline previously.

**Verified since your reply, in case it changes your answers:**
- You were right about the phoneme-count terminology. The style row is selected
  by the length of the *full* phoneme string (spaces, punctuation and stress
  marks all count), but my chunker targets an estimate of
  `graphemes × 1.15 + spaces + punctuation` with **no stress-mark term**. So I
  aim at 175 while the row is picked by a systematically larger number. Fixing.
- Upstream `VOICES.md` does document a "goldilocks range of 100-200 tokens",
  weakness under 10-20, and rushing over 400 — so the band is real even though,
  as you argued, 175-as-target is the wrong objective.

**Question 1 — line-break provenance.** You flagged that rejoining
renderer-induced `<br>` breaks is right but rejoining *author-intended* ones is
destructive, and that poetry, lyrics, chatfic and letters are common in this
domain. I agree, and I have chat and texting works in my corpus. You didn't
propose a way to tell them apart. What signals would you use? I have the raw
XHTML (so I can see `<br>` vs `<p>`, class names, inline styles), block length
distribution across the work, and on-device NLP. Is there a reliable
discriminator, or is this a case where I should detect *the work* as
verse/chat-formatted and switch modes wholesale rather than deciding per break?

**Question 2 — decoupling the style row from input length.** You suggested
synthesising the same text with deliberately mismatched style rows to see
whether a stable "long-form narration" region exists, and noted this is highly
experimental. Two things I want before spending time on it:
(a) What result would you consider strong enough to justify overriding the
intended `pack[len(ps)-1]` convention in shipping code — and what would you
expect to go wrong if a mismatched row is used (timbre drift, duration
mismatch, artefacts)?
(b) Are you aware of anyone actually doing this with Kokoro or another
StyleTTS2-family model, or is it purely your inference from the architecture?
I can run the experiment; I want to know what I'm looking for and whether it's
been tried.

---

## For Grok

Your `VOICES.md` citation checked out exactly — the goldilocks range, the
short-utterance weakness and the rushing threshold are all in upstream's own
documentation, quoted as you gave them. That makes you the reviewer I most want
to press on sources.

**Context:** iOS fanfiction reader, offline Kokoro-82M via Core ML, model
frozen. You reviewed my TTS pipeline previously.

**Question — style-vector persistence across utterances.** You wrote that
Kokoro cannot do true acoustic continuation "the way StyleTTS 2 long-form code
does with convex combination of generated style vectors," and separately
suggested I try SLERP between the previous chunk's length-selected style vector
and the current one.

This is directly actionable for me — I already SLERP style vectors for voice
blending, so the machinery exists.

Can you point me at the specific StyleTTS 2 long-form implementation or paper
section that does this convex combination? I want to know:
1. Is it blending the *style vectors* themselves, or something downstream
   (predicted durations, F0 contours)?
2. What blend weight does it use, and is it fixed or a decay across the
   utterance?
3. Does it blend across every consecutive utterance, or only within a
   paragraph / same-speaker run?

If the reference exists I'll implement and A/B it. If you're reasoning from the
general approach rather than a specific implementation, say so — that's still
useful, I just need to know which it is before I treat the blend weights as
having any authority.

---

## For DeepSeek

One question, and some context on why it's the only one.

**Context:** iOS fanfiction reader, offline Kokoro-82M via Core ML, model
frozen. You reviewed my TTS pipeline previously.

Two claims in your reply didn't hold up on checking: `VNCoreMLModel` is Vision
framework and isn't the reuse path for this model (I already cache the manager
instance across syntheses), and the "iOS 18+" gating for on-device LLM isn't a
constraint here since the deployment target is 26.5. That makes me want a
source for the one genuinely novel claim before I act on it.

**Question — prosodic token prior art.** You proposed mapping `<em>` emphasis
to Kokoro's `↗ ↘` tokens as pitch accents — rising on the first emphasised
word, falling on the last — and said this is "established in speech synthesis
(e.g. Festival, MaryTTS)."

Every reviewer told me to start emitting these tokens, so I'm going to. But I
want to get the mapping right rather than guess:

1. What exactly did Festival or MaryTTS do here? Those systems used ToBI-style
   pitch-accent annotation (`H*`, `L+H*`, boundary tones) driving a prosody
   model — is your suggestion that Kokoro's arrow tokens are equivalent to
   those, or is that an analogy?
2. Kokoro's arrows appear to come from Misaki's phoneme inventory rather than
   from a ToBI-style annotation layer. Do you know whether they were trained as
   *pitch-accent markers* or as something else (tone marks for other languages,
   for instance)? If the latter, injecting them into English text puts them
   outside their training distribution.
3. If you're unsure, say so plainly — I can A/B this, but I'd rather know
   whether I'm testing established practice or a plausible-sounding analogy.
