#let _baseFont = (
  "Gentium", "Charis SIL", "Noto Serif",
  "Amiri", "Scheherazade", "Noto Naskh Arabic", "Noto Sans Arabic",
  "Ezra SIL", "Frank Ruehl CLM", "Noto Serif Hebrew", "Noto Sans Hebrew",
  "AR PL UMing", "AR PL UKai",
  "Baekmuk Batang",
  "Noto Sans",
)

#let _roleFonts = state("role-fonts", (
  body: _baseFont, header: _baseFont, transcription: _baseFont, translation: _baseFont, strong: _baseFont, emph: _baseFont,
))

#let _sourceDir = state("source-dir", ltr)

// SPECS §8.2/§8.3: the full parsed font.css slot table (script/extension/
// field/style-qualified families, keyed by the SAME canonical join
// pkg/ebook's FontTable uses), populated once in book(). #_resolveFont
// below is the Typst-side mirror of FontTable.resolve (typst.go) — it MUST
// stay algorithmically identical to it (ASR-4/Major-2), since only this
// template sees each block's own script/extension/field at compile time.
#let _fontSlots = state("font-slots", (:))

// book-script is passed through for forward-compat/debugging ONLY (SPECS
// A2: resolution keys exclusively on each block's OWN resolved script,
// never the book's) — #_resolveFont deliberately never reads this state.
#let _bookScript = state("book-script", "")

// largeScriptCodes mirror (typst.go's largeScriptCodes, kept in sync by
// hand — a small, rarely-changing closed set): scripts whose synthetic
// bold/italic renders poorly, so strong/emph substitute a distinct role
// font at normal weight/style instead (SPECS §8.4).
#let _largeScripts = (
  "hans", "hant", "hani", "arab", "hebr", "kore", "hang", "jpan", "hira", "kana",
)
// Defensively lowercase/trim before the set-membership check, matching the
// Go-side `resolve`'s `strings.ToLower(strings.TrimSpace(...))` normalization
// (SPECS §8.4 FIX-4/minor): a caller passing e.g. "Arab" (author-cased
// script= attribute) must gate identically to "arab".
#let _isLargeScript(script) = lower(script.trim()) in _largeScripts

// _slotKey joins the non-empty (script,ext,field,style) parts with a single
// space — the SAME canonical key shape typst.go's slotKey produces, so a
// family classified there and looked up here always agree.
#let _slotKey(..parts) = parts.pos().filter(p => p != "").join(" ")

// _baseRoleFor mirrors typst.go's baseRoleForField (SPECS §4's "BaseRole(F)
// map"): Source/Content/Main/Question/Answer/Phrase -> Body (or Translation
// when as-translation); Transcription -> Transcription; Translation/
// Secondary/Grammar -> Translation; Tag/Header -> Header.
#let _baseRoleFor(field, as-translation) = {
  if field in ("source", "content", "main", "question", "answer", "phrase") {
    if as-translation { "translation" } else { "body" }
  } else if field == "transcription" {
    "transcription"
  } else if field in ("translation", "secondary", "grammar") {
    "translation"
  } else if field in ("tag", "header") {
    "header"
  } else {
    "body"
  }
}

// _roleFontsKey maps a style name to _roleFonts' pre-existing dict field
// name: the legacy state uses "emph", not "emphasis" (ASR-1, unchanged).
#let _roleFontsKey(style) = if style == "emphasis" { "emph" } else { style }

// _resolveFont implements SPECS §4's field -> extension -> script ->
// base-role chain (mirrors FontTable.resolve, pkg/ebook/typst.go). It
// returns a font ARRAY ready for `text(font: ...)`: the most-specific
// declared family (if any) followed by the legacy base-role's already-
// assembled stack (font-<role> arg + the base multi-script font, i.e.
// exactly what _roleFonts.get() already carries) — so an undeclared
// qualified slot falls through to today's behavior with no visible change
// (ASR-1). Must be called from within `context` (reads state).
//
// style selects the Strong/Emphasis sub-axis ("strong"/"emphasis"; "" =
// regular). as-translation mirrors {start-text as=translation}: primary
// fields resolve base role Translation instead of Body. An empty script
// SKIPS the script-qualified levels (SPECS §6: no book-Script inheritance,
// G1 deferred) and resolves via the base role directly — this is also how
// callers realize Major-2's fixed-script fields (pass script: "latn" for
// transcription, script: "" for translation/grammar/secondary, regardless
// of the block's own foreign `script` param).
#let _resolveFont(script: "", ext: "", field: "", style: "", as-translation: false) = {
  // Defensively lowercase/trim every axis before building candidate keys
  // (SPECS §8.4 FIX-4/minor), matching the Go-side FontTable.resolve
  // normalization — so an author-cased attribute (e.g. script="Arab") or a
  // caller passing a not-yet-normalized field/style still joins the SAME
  // canonical _slotKey a differently-cased classifyFontFamily entry would.
  let script = lower(script.trim())
  let ext = lower(ext.trim())
  let field = lower(field.trim())
  let style = lower(style.trim())
  let slots = _fontSlots.get()
  let base-role = _baseRoleFor(field, as-translation)

  if style != "" {
    let candidates = ()
    if script != "" {
      candidates = (
        _slotKey(script, ext, field, style),
        _slotKey(script, ext, style),
        _slotKey(script, style),
      )
    }
    candidates.push(style)
    for c in candidates {
      if c in slots {
        return (slots.at(c),) + _roleFonts.get().at(_roleFontsKey(style))
      }
    }
    // None declared: fall through to the regular (unstyled) chain below —
    // book.typ's per-block gate (§8.4) already decided the regular font is
    // an acceptable substitute here.
  }

  let candidates = ()
  if script != "" {
    candidates = (
      _slotKey(script, ext, field),
      _slotKey(script, ext),
      _slotKey(script),
    )
  }
  for c in candidates {
    if c in slots {
      return (slots.at(c),) + _roleFonts.get().at(base-role)
    }
  }
  _roleFonts.get().at(base-role)
}

#let textblock(role: "source", dir: ltr, script: "", body) = {
  show heading.where(level: 1): set align(center)
  show heading.where(level: 2): set align(center)
  show heading.where(level: 3): set align(center)
  set text(dir: dir)

  // SPECS Major-2: transcription/translation/grammar resolve their FAMILY
  // with their own fixed script (transcription -> latn, translation/
  // grammar -> base ""), decoupled from this block's foreign `script`
  // param, so a bare `Font <Script>` catch-all in font.css can't hijack
  // e.g. a Polish translation column inside an Arabic block.
  let familyScript = if role == "transcription" { "latn" } else if role == "translation" or role == "grammar" { "" } else { script }

  // SPECS §8.4 (review-amended 2026-07-31): the Strong/Emphasis GATE MUST use
  // the SAME script as this field's family resolution (familyScript), NOT the
  // raw block `script`. Using the raw script here was the code-review defect:
  // for role=translation/grammar, familyScript is fixed ("" / base) but the
  // raw `script` is still the block's own foreign script — gating on the raw
  // script would re-enter the large-script substitution branch whenever that
  // foreign script is large, hijacking this field's base/Latin bold into the
  // large-script Strong font even though the REGULAR (non-bold) text in the
  // same field correctly resolves the base/Translation family. Gating on
  // familyScript instead keeps regular vs bold in the SAME resolved script
  // (transcription's familyScript is already "latn", so it is unaffected;
  // role=source's familyScript already equals `script`, also unaffected).
  // Per-block gate scoped to THIS block's own resolved script rather than the
  // book-level `large-script` flag (book()'s global show-rule still governs
  // plain prose outside any of these 6 blocks). F3-safe: `text(font:)` sits
  // INSIDE the show rule's `it.body`, never wrapping the strong/emph element
  // from outside.
  //
  // The "else" branch finalizes via `text(weight:/style:, it.body)` rather
  // than returning `it` verbatim: Typst's show-rule chaining still offers an
  // unmodified `it` to any ENCLOSING show-strong/emph rule (verified via
  // isolated `typst query` metadata probes), so a bare `else { it }` would
  // let book()'s own book-level large-script gate re-substitute this field's
  // bold/emph whenever the BOOK itself is large-script — even though THIS
  // field's own familyScript isn't (the exact "regular vs bold land in
  // different scripts" defect, just re-introduced one level out). Explicitly
  // re-emitting via `text()` (confirmed visually identical to Typst's native
  // default strong/emph rendering) stops that leak.
  show strong: it => if _isLargeScript(familyScript) {
    context text(font: _resolveFont(script: familyScript, ext: "text", field: role, style: "strong"), weight: "regular", it.body)
  } else { text(weight: "bold", it.body) }
  show emph: it => if _isLargeScript(familyScript) {
    context text(font: _resolveFont(script: familyScript, ext: "text", field: role, style: "emphasis"), style: "normal", it.body)
  } else { text(style: "italic", it.body) }

  if role == "grammar" {
    show table: it => block(width: 100%, context text(dir: _sourceDir.get(), font: _roleFonts.get().body)[#it])
    context text(font: _resolveFont(script: "", ext: "text", field: "grammar"), body)
  } else if role == "transcription" {
    context text(font: _resolveFont(script: "latn", ext: "text", field: "transcription"), body)
  } else if role == "translation" {
    context text(font: _resolveFont(script: "", ext: "text", field: "translation"), body)
  } else {
    context text(font: _resolveFont(script: script, ext: "text", field: "source"), body)
  }
}

#let vocabulary(dir: ltr, script: "", ..items) = {
  set text(dir: dir)
  block(width: 100%, grid(
    columns: (1fr, 1fr),
    column-gutter: 1em,
    stroke: (y: 0.5pt + luma(220)),
    align: (start + top, start + top),
    inset: (x: 2pt, y: 4pt),
    ..items.pos().map(it => (
      {
        // Phrase is the foreign/target field (SPECS §6): large-script gate
        // per this block's OWN script (no Major-2 decoupling — phrase is
        // always the block's own foreign field). The non-large branch
        // FINALIZES via `text(weight: "bold", ...)` rather than a bare
        // `strong(...)` call (SPECS §8.4 fix pass, residual item): a bare
        // strong() creates a fresh element still visible to any ENCLOSING
        // show-strong rule (book()'s own book-level large-script gate), so a
        // non-large-script phrase nested in a large-script BOOK would
        // otherwise get re-substituted with the book's Strong font — the
        // same "unfinalized element leaks to the outer gate" defect fixed
        // for textblock/dialog/parallel above, visually identical output to
        // Typst's native bold for the common (non-large-script book) case.
        if _isLargeScript(script) {
          context text(font: _resolveFont(script: script, ext: "vocabulary", field: "phrase", style: "strong"), weight: "regular", it.at("phrase", default: ""))
        } else {
          text(weight: "bold", it.at("phrase", default: ""))
        }
        if it.at("grammar", default: "") != "" {
          [ ]; context text(font: _resolveFont(script: "latn", ext: "vocabulary", field: "tag"), dir: ltr, size: 0.85em, fill: gray)[#it.at("grammar")]
        }
        if it.at("transcription", default: "") != "" {
          [ ]; emph[#context text(font: _resolveFont(script: "latn", ext: "vocabulary", field: "transcription"), dir: ltr)[\[#it.at("transcription")\]]]
        }
      },
      context text(font: _resolveFont(script: "", ext: "vocabulary", field: "translation"), dir: ltr)[#it.at("translation", default: "")],
    )).flatten()
  ))
}

#let models(dir: ltr, script: "", ..items) = {
  set text(dir: dir)
  block(width: 100%, grid(
    columns: (1fr, 1fr),
    column-gutter: 1em,
    align: (start + top, start + top),
    inset: (x: 2pt, y: 4pt),
    ..items.pos().map(it => {
      let phrase = it.at("phrase", default: "")
      let transcription = it.at("transcription", default: "")
      let translation = it.at("translation", default: "")
      // Phrase is the foreign/target field (SPECS §6): large-script gate per
      // this block's OWN script (no Major-2 decoupling). Non-large branch
      // FINALIZES via `text(weight: "bold", ...)` rather than a bare
      // `strong(...)` call — see vocabulary()'s matching comment above for
      // why (SPECS §8.4 fix pass, residual item).
      let phraseContent = if _isLargeScript(script) {
        context text(font: _resolveFont(script: script, ext: "models", field: "phrase", style: "strong"), weight: "regular", phrase)
      } else {
        text(weight: "bold", phrase)
      }
      if transcription == "" and translation == "" {
        (grid.cell(colspan: 2, phraseContent),)
      } else {
        (
          {
            phraseContent
            if transcription != "" and translation != "" {
              linebreak()
              emph[#context text(font: _resolveFont(script: "latn", ext: "models", field: "transcription"), dir: ltr)[\[#transcription\]]]
            }
          },
          if translation != "" {
            context text(font: _resolveFont(script: "", ext: "models", field: "translation"), dir: ltr)[#translation]
          } else if transcription != "" {
            emph[#context text(font: _resolveFont(script: "latn", ext: "models", field: "transcription"), dir: ltr)[\[#transcription\]]]
          } else { [] },
        )
      }
    }).flatten()
  ))
}

// role: carries the block's as= attribute value ("source"/"translation");
// named `role`, not `as`, because `as` is a reserved Typst keyword (mirrors
// textblock's pre-existing role: convention for the same reason).
#let questions(dir: ltr, script: "", role: "source", ..items) = {
  set text(dir: dir)
  set par(first-line-indent: 0pt)
  // SPECS §5: questions accepts as=source|translation; as=translation
  // resolves question/answer via the Translation base role (Major-2: fixed
  // script, decoupled from this block's own foreign `script` param).
  let asTranslation = role == "translation"
  let familyScript = if asTranslation { "" } else { script }
  let run = ()
  for it in items.pos() {
    let question = it.at("question", default: "")
    let answer = it.at("answer", default: "")
    if answer != "" {
      run += (
        context text(font: _resolveFont(script: familyScript, ext: "questions", field: "question", as-translation: asTranslation), question),
        context text(font: _resolveFont(script: familyScript, ext: "questions", field: "answer", as-translation: asTranslation), answer),
      )
    } else {
      if run.len() > 0 {
        grid(columns: (auto, 1fr), column-gutter: 1em, row-gutter: 0.5em, align: (start + top, start + top), ..run)
        run = ()
      }
      context text(font: _resolveFont(script: familyScript, ext: "questions", field: "question", as-translation: asTranslation), question)
      parbreak()
    }
  }
  if run.len() > 0 {
    grid(columns: (auto, 1fr), column-gutter: 1em, row-gutter: 0.5em, align: (start + top, start + top), ..run)
  }
}

// role: see questions' comment above (named `role`, not `as` — reserved).
#let dialog(dir: ltr, script: "", role: "source", ..turns) = {
  set text(dir: dir)
  // SPECS §5: dialog accepts as=source|translation; as=translation
  // resolves header/content via the Translation base role (Major-2: fixed
  // script for the FAMILY chain only — the Strong gate below still reads
  // this block's own `script`, since a translated dialogue can still be
  // written in a large script).
  let asTranslation = role == "translation"
  let familyScript = if asTranslation { "" } else { script }

  // SPECS §8.4 (review-amended 2026-07-31): gate on familyScript, not the raw
  // block `script` — otherwise an as=translation dialog's header/content bold
  // (fixed-script/base family, familyScript=="") would still enter the
  // large-script substitution branch whenever the block's OWN foreign script
  // is large, picking up the large-script Strong font for what should be a
  // base/Translation-role field (the code-review defect: regular content and
  // bold landing in different scripts). The "else" branch finalizes via
  // `text(weight:/style:, ...)` rather than `it`/a fresh `strong(...)` call,
  // for the same reason documented in textblock above: an unfinalized strong
  // element is still visible to book()'s OWN book-level large-script gate,
  // which would otherwise re-substitute whenever the BOOK itself is large
  // script, regardless of this field's own (decoupled) familyScript.
  show strong: it => if _isLargeScript(familyScript) {
    context text(font: _resolveFont(script: familyScript, ext: "dialog", field: "content", style: "strong", as-translation: asTranslation), weight: "regular", it.body)
  } else { text(weight: "bold", it.body) }
  show emph: it => if _isLargeScript(familyScript) {
    context text(font: _resolveFont(script: familyScript, ext: "dialog", field: "content", style: "emphasis", as-translation: asTranslation), style: "normal", it.body)
  } else { text(style: "italic", it.body) }

  block(width: 100%, grid(
    columns: (auto, 1fr), column-gutter: 0.8em, row-gutter: 0.5em,
    ..turns.pos().map(t => (
      if _isLargeScript(familyScript) {
        context text(font: _resolveFont(script: familyScript, ext: "dialog", field: "header", style: "strong", as-translation: asTranslation), weight: "regular", t.at("header", default: ""))
      } else {
        text(weight: "bold", t.at("header", default: ""))
      },
      context text(font: _resolveFont(script: familyScript, ext: "dialog", field: "content", as-translation: asTranslation))[#t.at("content", default: [])],
    )).flatten()
  ))
}

#let parallel(secondary-dir: ltr, script: "", ..rows) = {
  // SPECS §8.4 (review-amended 2026-07-31): parallel needs per-COLUMN gate
  // scopes, not one block-scoped rule — installing a single show strong/emph
  // rule for the whole parallel() scope (the code-review defect) rewrote
  // bold text in the MAIN column too (e.g. a bold Latin word in main got the
  // secondary column's Arabic Strong font, bold lost). Each row below wraps
  // ONLY the secondary cell in its own local scope.
  block(width: 100%, grid(
    columns: (1fr, 1fr), column-gutter: 1.2em, row-gutter: 0.5em,
    stroke: (x: 0.5pt + luma(230)),
    align: (start + top, start + top),
    ..rows.pos().map(r => (
      // Main is the book's OWN column (SPECS §6: "inherits the book's
      // language, script, direction, and body font — it has no
      // marker-derived override"). No show rule is installed here for it —
      // its bold/emph therefore falls through unaffected to book()'s own
      // book-level Strong/Emphasis gate ("parallel main -> book"), which
      // already uses the book's own script/font. That IS main's per-column
      // gate: deliberately absent, not a separate mechanism.
      r.at("main", default: []),
      {
        // Secondary is always the Translation-role column (Major-2: fixed
        // base script for the FAMILY chain, decoupled from this block's own
        // foreign `script`, since main/secondary already carry both
        // languages — as= is not accepted here). This show rule is scoped to
        // ONLY this cell's own code block, so it can never rewrite the MAIN
        // column's bold in the same row. The Strong gate uses the column's
        // own `script`, so a genuinely large-script secondary column still
        // substitutes correctly even in a small-script book. The "else"
        // branch finalizes via `text(weight:/style:, ...)` (not `it`) so a
        // non-large secondary column's bold can't leak out to book()'s own
        // book-level large-script gate when the book itself IS large script
        // (same reasoning as textblock/dialog above).
        show strong: it => if _isLargeScript(script) {
          context text(font: _resolveFont(script: "", ext: "parallel", field: "secondary", style: "strong"), weight: "regular", it.body)
        } else { text(weight: "bold", it.body) }
        show emph: it => if _isLargeScript(script) {
          context text(font: _resolveFont(script: "", ext: "parallel", field: "secondary", style: "emphasis"), style: "normal", it.body)
        } else { text(style: "italic", it.body) }
        context text(dir: secondary-dir, font: _resolveFont(script: "", ext: "parallel", field: "secondary"))[#r.at("secondary", default: [])]
      },
    )).flatten()
  ))
}

#let book(
  title: none,
  author: none,
  description: none,
  lang: "en",
  dir: ltr,
  cover: none,
  paper: "a5",
  size: 12pt,
  size-large: 16pt,
  large-script: false,
  margin: (inside: 1.8cm, outside: 1.4cm, top: 1.7cm, bottom: 2cm),
  font: _baseFont,
  font-body: (),
  font-header: (),
  font-transcription: (),
  font-translation: (),
  font-strong: (),
  font-emph: (),
  font-slots: (:),
  book-script: "",
  contents-title: [Contents],
  body,
) = {
  let headerFont = font-header + font
  let strongFont = font-strong + font
  let emphFont = font-emph + font
  _roleFonts.update((
    body: font-body + font,
    header: headerFont,
    transcription: font-transcription + font,
    translation: font-translation + font,
    strong: strongFont,
    emph: emphFont,
  ))
  _sourceDir.update(dir)
  _fontSlots.update(font-slots)
  _bookScript.update(book-script)

  set document(title: title, author: if author == none or author == "" { () } else { author })
  set text(
    lang: lang,
    dir: dir,
    size: if large-script { size-large } else { size },
    font: font-body + font,
    hyphenate: true,
  )
  set page(paper: paper, margin: margin, numbering: "1")
  set par(justify: true, leading: 0.7em, spacing: 0.7em, first-line-indent: (amount: 1.2em, all: false))
  show heading: set par(justify: false, first-line-indent: 0pt)
  set terms(separator: [: ], tight: true, hanging-indent: 1em)
  set table(
    stroke: (x: none, y: 0.7pt + luma(180)),
    inset: (x: 8pt, y: 5pt),
    align: (_, y) => if y == 0 { center } else { left },
    fill: (_, y) => if y == 0 { luma(235) } else { none },
  )
  show heading: set block(above: 1.5em, below: 0.75em)
  show heading: set text(font: headerFont)
  show heading.where(level: 1): set text(size: 1.7em)
  show heading.where(level: 2): set text(size: 1.4em)
  show heading.where(level: 3): set text(size: 1.2em)
  show heading.where(level: 4): set text(size: 1.1em)
  show heading.where(level: 5): set text(size: 1.05em)
  show heading.where(level: 6): set text(size: 1em)
  // Book-level gate: governs plain prose OUTSIDE any of the 6 custom
  // blocks above (each of which now installs its OWN per-block gate,
  // SPECS §8.4/INC2.5, that supersedes this one within its own scope).
  show strong: it => if large-script { text(font: strongFont, weight: "regular", it.body) } else { it }
  show emph: it => if large-script { text(font: emphFont, style: "normal", it.body) } else { it }
  show heading: it => if large-script { set text(weight: "regular"); it } else { it }
  show quote.where(block: true): it => block(inset: (left: 1em, y: 0.3em), stroke: (left: 2pt + luma(180)))[#emph(it.body)]

  set page(numbering: none)

  if cover != none {
    page(margin: 0pt, numbering: none, {
      if type(cover) == str {
        image(cover, width: 100%, height: 100%, fit: "cover")
      } else { cover }
    })
  }

  {
    set par(justify: false)
    set text(hyphenate: false)
    align(center + horizon, {
      if large-script {
        text(size: 2.4em, font: strongFont, title)
      } else {
        text(size: 2.4em, weight: "bold", title)
      }
      if author != none and author != "" { v(1.2em); text(size: 1.3em, author) }
      if description != none and description != "" {
        v(1.6em)
        if large-script {
          text(font: emphFont, fill: luma(90%), description)
        } else {
          text(style: "italic", fill: luma(90%), description)
        }
      }
    })
  }
  pagebreak()

  set page(numbering: "i")
  counter(page).update(1)
  show outline.entry.where(level: 1): strong
  outline(title: contents-title, indent: auto)
  pagebreak()

  set page(numbering: "1")
  counter(page).update(1)

  body
}

#show: book.with(
  title: "Język łaciński (publiczne)",
  author: "D. Purge",
  description: "Teksty i notatki do nauki języka łacińskiego.\n",
  lang: "la",
  dir: ltr,
  cover: "/cover.svg",
  font-body: ("Noto Serif", "Gentium"),
  font-header: ("Noto Sans", "Noto Sans"),
  font-transcription: ("Noto Sans", "DejaVu Sans"),
  font-translation: ("Noto Serif", "Gentium"),
  font-strong: ("Gentium",),
  font-emph: ("Gentium",),
  font-slots: ("body": "Noto Serif", "header": "Noto Sans", "latn dialog header": "Noto Sans", "latn questions answer": "Noto Sans", "latn questions question": "Noto Serif", "latn text transcription": "Noto Sans Mono", "latn vocabulary phrase": "Noto Serif Display", "latn vocabulary transcription": "Noto Sans", "transcription": "Noto Sans", "translation": "Noto Serif"),
  book-script: "latn",
)

= Początki nauki języka łacińskiego

Tadeusz Marian Lewicki

(1924)


#pagebreak(weak: true)

= Żaba stara i młoda

#vocabulary(dir: ltr, script: "latn",
  (phrase: "rana", grammar: "N f", transcription: "", translation: "żaba"),
  (phrase: "aqua", grammar: "N f", transcription: "", translation: "woda"),
  (phrase: "ripa", grammar: "N f", transcription: "", translation: "brzeg (rzeki)"),
  (phrase: "ciconia", grammar: "N f", transcription: "", translation: "bocian"),
  (phrase: "filia", grammar: "N f", transcription: "", translation: "córka"),
  (phrase: "herba", grammar: "N f", transcription: "", translation: "trawa, zioło"),
  (phrase: "figura", grammar: "N f", transcription: "", translation: "postać, kształt"),
  (phrase: "sapientia", grammar: "N f", transcription: "", translation: "mądrość"),
  (phrase: "stultitia", grammar: "N f", transcription: "", translation: "głupota"),
  (phrase: "poena", grammar: "N f", transcription: "", translation: "kara"),
  (phrase: "magnus", grammar: "Adj", transcription: "", translation: "wielki, duży"),
  (phrase: "parvus", grammar: "Adj", transcription: "", translation: "mały"),
  (phrase: "saevus", grammar: "Adj", transcription: "", translation: "okrutny, dziki"),
  (phrase: "stultus", grammar: "Adj", transcription: "", translation: "głupi"),
  (phrase: "amare", grammar: "V", transcription: "", translation: "kochać, lubić"),
  (phrase: "vituperare", grammar: "V", transcription: "", translation: "ganić, łajać"),
  (phrase: "vitare", grammar: "V", transcription: "", translation: "unikać"),
  (phrase: "occultare", grammar: "V", transcription: "", translation: "ukrywać"),
  (phrase: "devorare", grammar: "V", transcription: "", translation: "pożerać"),
  (phrase: "ego", grammar: "Pron", transcription: "", translation: "ja"),
  (phrase: "est", grammar: "V", transcription: "", translation: "jest"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "rana", transcription: "", translation: "żaba"),
  (phrase: "aqua", transcription: "", translation: "woda"),
  (phrase: "Ranae aquam amant.", transcription: "", translation: "Żaby kochają wodę."),
  (phrase: "magna rana", transcription: "", translation: "wielka żaba"),
  (phrase: "parva rana", transcription: "", translation: "mała żaba"),
  (phrase: "Magna rana parvam ranam vituperat.", transcription: "", translation: "Wielka żaba gani małą żabę."),
  (phrase: "ripa", transcription: "", translation: "brzeg"),
  (phrase: "ripas ciconiae amant", transcription: "", translation: "bociany kochają brzegi"),
  (phrase: "Ripam vita, filia!", transcription: "", translation: "Unikaj brzegu, córko!"),
  (phrase: "Saevas ciconias vita!", transcription: "", translation: "Unikaj okrutnych bocianów!"),
  (phrase: "herba", transcription: "", translation: "trawa"),
  (phrase: "herbae riparum", transcription: "", translation: "trawy brzegów"),
  (phrase: "Ego herbas riparum amo.", transcription: "", translation: "Ja kocham trawy brzegów."),
  (phrase: "Herbae parvas ranarum figuras occultant.", transcription: "", translation: "Trawy ukrywają małe postacie żab."),
  (phrase: "poena stultitiae", transcription: "", translation: "kara za głupotę"),
  (phrase: "poena magna est", transcription: "", translation: "kara jest wielka"),
  (phrase: "Poena stultitiae magna est.", transcription: "", translation: "Kara za głupotę jest wielka."),
  (phrase: "Stultam ranam ciconia devorat.", transcription: "", translation: "Głupią żabę bocian pożera."),
)

#line(length: 100%)
#textblock(role: "source", dir: ltr, script: "latn", [
== Tekst

Ranae aquam amant\.

Magna rana parvam ranam vituperat: “Ripam vita, filia! Ripas ciconiae amant\. Saevas ciconias vita!”

Sapientiam magnae ranae filia vituperat: “Ego herbas riparum amo\. Herbae parvas ranarum figuras occultant\.”

Poena stultitiae magna est\.

Stultam ranam ciconia devorat\.

])

#line(length: 100%)
#textblock(role: "translation", dir: ltr, script: "latn", [
== Tłumaczenie

Żaby kochają wodę\.

Wielka żaba gani małą żabę: „Unikaj brzegu, córko! Bociany kochają brzegi\. Unikaj okrutnych bocianów!”

Mądrość wielkiej żaby córka gani: „Ja kocham trawy brzegów\. Trawy ukrywają małe postacie żab\.”

Kara za głupotę jest wielka\.

Głupią żabę bocian pożera\.

])


#pagebreak(weak: true)

= Na podwórzu

#vocabulary(dir: ltr, script: "latn",
  (phrase: "puella", grammar: "N f", transcription: "", translation: "dziewczynka"),
  (phrase: "agna", grammar: "N f", transcription: "", translation: "jagnię (samica)"),
  (phrase: "domina", grammar: "N f", transcription: "", translation: "pani (domu)"),
  (phrase: "cena", grammar: "N f", transcription: "", translation: "posiłek; obiad"),
  (phrase: "aqua", grammar: "N f", transcription: "", translation: "woda"),
  (phrase: "bestia", grammar: "N f", transcription: "", translation: "zwierzę"),
  (phrase: "parvus", grammar: "Adj", transcription: "", translation: "mały"),
  (phrase: "gratus", grammar: "Adj", transcription: "", translation: "miły; drogi"),
  (phrase: "parare", grammar: "V", transcription: "", translation: "przygotowywać"),
  (phrase: "imperare", grammar: "V", transcription: "", translation: "rozkazywać (z celownikiem)"),
  (phrase: "portare", grammar: "V", transcription: "", translation: "nieść; nosić"),
  (phrase: "obtemperare", grammar: "V", transcription: "", translation: "być posłusznym (z celownikiem)"),
  (phrase: "esse", grammar: "V", transcription: "", translation: "być"),
  (phrase: "et", grammar: "Conj", transcription: "", translation: "i"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "parva puella", transcription: "", translation: "mała dziewczynka"),
  (phrase: "parvae puellae", transcription: "", translation: "małej dziewczynce"),
  (phrase: "agna grata", transcription: "", translation: "miłe jagnię"),
  (phrase: "Parvae puellae agna grata est.", transcription: "", translation: "Małej dziewczynce jagnię jest miłe."),
  (phrase: "cena", transcription: "", translation: "posiłek"),
  (phrase: "agnae cenam", transcription: "", translation: "posiłek dla jagnięcia"),
  (phrase: "cenam parat", transcription: "", translation: "przygotowuje posiłek"),
  (phrase: "Puella agnae cenam parat.", transcription: "", translation: "Dziewczynka przygotowuje posiłek dla jagnięcia."),
  (phrase: "domina", transcription: "", translation: "pani"),
  (phrase: "puellis imperat", transcription: "", translation: "rozkazuje dziewczynkom"),
  (phrase: "Domina puellis imperat.", transcription: "", translation: "Pani rozkazuje dziewczynkom."),
  (phrase: "aquam portate", transcription: "", translation: "nieście wodę"),
  (phrase: "Agnis aquam portate, puellae!", transcription: "", translation: "Nieście wodę jagniętom, dziewczynki!"),
  (phrase: "dominae", transcription: "", translation: "pani (komu)"),
  (phrase: "obtemperant", transcription: "", translation: "są posłuszne"),
  (phrase: "Puellae dominae obtemperant.", transcription: "", translation: "Dziewczynki są posłuszne pani."),
  (phrase: "bestiis aquam", transcription: "", translation: "wodę zwierzętom"),
  (phrase: "Bestiis aquam portant.", transcription: "", translation: "Niosą zwierzętom wodę."),
)

#line(length: 100%)
#textblock(role: "source", dir: ltr, script: "latn", [
Parvae puellae agna grata est\. Puella agnae cenam parat\.

Domina puellis imperat: “Agnis aquam portate, puellae!”

Puellae dominae obtemperant\. Bestiis aquam portant\.

])

#line(length: 100%)
#textblock(role: "translation", dir: ltr, script: "latn", [
Małej dziewczynce miłe jest jagnię\. Dziewczynka przygotowuje jagnięciu posiłek\.

Pani rozkazuje dziewczynkom: „Nieście wodę jagniętom, dziewczynki!”

Dziewczynki są posłuszne pani\. Niosą zwierzętom wodę\.

])


#pagebreak(weak: true)

= Bogini Minerwa

#vocabulary(dir: ltr, script: "latn",
  (phrase: "silva", grammar: "f", transcription: "", translation: "las"),
  (phrase: "statua", grammar: "f", transcription: "", translation: "posąg"),
  (phrase: "Minerva", grammar: "f", transcription: "", translation: "Minerwa"),
  (phrase: "dea", grammar: "f", transcription: "", translation: "bogini"),
  (phrase: "galea", grammar: "f", transcription: "", translation: "hełm"),
  (phrase: "puella", grammar: "f", transcription: "", translation: "dziewczyna"),
  (phrase: "corona", grammar: "f", transcription: "", translation: "wieniec"),
  (phrase: "ara", grammar: "f", transcription: "", translation: "ołtarz"),
  (phrase: "ornatus", grammar: "", transcription: "", translation: "ozdobiony"),
  (phrase: "armatus", grammar: "", transcription: "", translation: "uzbrojony"),
  (phrase: "ornare", grammar: "", transcription: "", translation: "ozdabiać"),
  (phrase: "properare", grammar: "", transcription: "", translation: "śpieszyć się"),
  (phrase: "collocare", grammar: "", transcription: "", translation: "umieszczać, kłaść"),
  (phrase: "esse", grammar: "", transcription: "", translation: "być"),
  (phrase: "in", grammar: "Prep", transcription: "", translation: "w (z abl.); do (z acc.)"),
  (phrase: "ubi", grammar: "Adv", transcription: "", translation: "gdzie"),
  (phrase: "quo", grammar: "Adv", transcription: "", translation: "dokąd"),
  (phrase: "est", grammar: "V", transcription: "", translation: "jest"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "silva", transcription: "", translation: "las"),
  (phrase: "statua Minervae", transcription: "", translation: "posąg Minerwy"),
  (phrase: "statua Minervae deae", transcription: "", translation: "posąg bogini Minerwy"),
  (phrase: "Silva ornata est statua Minervae deae.", transcription: "", translation: "Las jest ozdobiony posągiem bogini Minerwy."),
  (phrase: "galea", transcription: "", translation: "hełm"),
  (phrase: "galea armata", transcription: "", translation: "uzbrojona w hełm"),
  (phrase: "Minerva galea armata est.", transcription: "", translation: "Minerwa jest uzbrojona w hełm."),
  (phrase: "corona", transcription: "", translation: "wieniec"),
  (phrase: "coronis deae", transcription: "", translation: "wieńcami bogini"),
  (phrase: "aram ornant", transcription: "", translation: "ozdabiają ołtarz"),
  (phrase: "Puellae coronis deae aram ornant.", transcription: "", translation: "Dziewczęta ozdabiają wieńcami ołtarz bogini."),
  (phrase: "Ubi est statua Minervae?", transcription: "", translation: "Gdzie jest posąg Minerwy?"),
  (phrase: "Statua Minervae in silva est.", transcription: "", translation: "Posąg Minerwy jest w lesie."),
  (phrase: "Quo properant puellae?", transcription: "", translation: "Dokąd śpieszą się dziewczęta?"),
  (phrase: "Puellae in silvam properant.", transcription: "", translation: "Dziewczęta śpieszą do lasu."),
  (phrase: "Coronas in ara collocant.", transcription: "", translation: "Wieńce kładą na ołtarzu."),
)

#line(length: 100%)
#textblock(role: "source", dir: ltr, script: "latn", [
Silva ornata est statua Minervae deae\. Minerva galea armata est\. Puellae coronis deae aram ornant\.

Ubi est statua Minervae?

Statua Minervae in silva est\.

Quo properant puellae?

Puellae in silvam properant\. Coronas in ara collocant\.

])

#line(length: 100%)
#textblock(role: "translation", dir: ltr, script: "latn", [
Las jest ozdobiony posągiem bogini Minerwy\. Minerwa jest uzbrojona w hełm\. Dziewczęta ozdabiają wieńcami ołtarz bogini\.

Gdzie jest posąg Minerwy?

Posąg Minerwy jest w lesie\.

Dokąd śpieszą się dziewczęta?

Dziewczęta śpieszą do lasu\. Wieńce kładą na ołtarzu\.

])


#pagebreak(weak: true)

= Bogini łowów Diana

#vocabulary(dir: ltr, script: "latn",
  (phrase: "Minerva", grammar: "N f sg", transcription: "", translation: "Minerwa"),
  (phrase: "Diana", grammar: "N f sg", transcription: "", translation: "Diana"),
  (phrase: "dea", grammar: "N f sg", transcription: "", translation: "bogini"),
  (phrase: "domina", grammar: "N f sg", transcription: "", translation: "pani; władczyni"),
  (phrase: "patrona", grammar: "N f sg", transcription: "", translation: "patronka; opiekunka"),
  (phrase: "puella", grammar: "N f sg", transcription: "", translation: "dziewczyna"),
  (phrase: "silva", grammar: "N f sg", transcription: "", translation: "las"),
  (phrase: "pugna", grammar: "N f sg", transcription: "", translation: "walka; bitwa"),
  (phrase: "sagitta", grammar: "N f sg", transcription: "", translation: "strzała"),
  (phrase: "bestia", grammar: "N f sg", transcription: "", translation: "zwierzę; bestia"),
  (phrase: "cerva", grammar: "N f sg", transcription: "", translation: "łania"),
  (phrase: "ara", grammar: "N f sg", transcription: "", translation: "ołtarz"),
  (phrase: "ferus", grammar: "Adj", transcription: "", translation: "dziki"),
  (phrase: "bonus", grammar: "Adj", transcription: "", translation: "dobry"),
  (phrase: "amare", grammar: "V", transcription: "", translation: "kochać"),
  (phrase: "necare", grammar: "V", transcription: "", translation: "zabijać"),
  (phrase: "ornare", grammar: "V", transcription: "", translation: "zdobić"),
  (phrase: "adorare", grammar: "V", transcription: "", translation: "czcić; uwielbiać"),
  (phrase: "collocare", grammar: "V", transcription: "", translation: "umieszczać; kłaść"),
  (phrase: "properare", grammar: "V", transcription: "", translation: "śpieszyć (się)"),
  (phrase: "esse", grammar: "V", transcription: "", translation: "być"),
  (phrase: "non", grammar: "Adv", transcription: "", translation: "nie"),
  (phrase: "autem", grammar: "Conj", transcription: "", translation: "zaś; natomiast"),
  (phrase: "sed", grammar: "Conj", transcription: "", translation: "lecz; ale"),
  (phrase: "in", grammar: "Prep", transcription: "", translation: "w; do (z biernikiem — kierunek)"),
  (phrase: "quis", grammar: "Pron", transcription: "", translation: "kto"),
  (phrase: "quid", grammar: "Pron", transcription: "", translation: "co"),
  (phrase: "quem", grammar: "Pron", transcription: "", translation: "kogo (biernik od quis)"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "Minerva", transcription: "", translation: "Minerwa"),
  (phrase: "patrona", transcription: "", translation: "patronka"),
  (phrase: "patrona pugnarum", transcription: "", translation: "patronka walk"),
  (phrase: "Minerva pugnarum patrona est.", transcription: "", translation: "Minerwa jest patronką walk."),
  (phrase: "Diana", transcription: "", translation: "Diana"),
  (phrase: "domina", transcription: "", translation: "pani"),
  (phrase: "silvarum domina", transcription: "", translation: "pani lasów"),
  (phrase: "Diana autem est silvarum domina.", transcription: "", translation: "Diana zaś jest panią lasów."),
  (phrase: "ferae bestiae", transcription: "", translation: "dzikie zwierzęta"),
  (phrase: "feras bestias", transcription: "", translation: "dzikie zwierzęta (biernik)"),
  (phrase: "Feras bestias Diana non amat.", transcription: "", translation: "Diana nie kocha dzikich zwierząt."),
  (phrase: "sagittis", transcription: "", translation: "strzałami"),
  (phrase: "Dea sagittis feras bestias necat.", transcription: "", translation: "Bogini strzałami zabija dzikie zwierzęta."),
  (phrase: "cervae bonae", transcription: "", translation: "dobre łanie"),
  (phrase: "cervae bonae bestiae sunt", transcription: "", translation: "łanie są dobrymi zwierzętami"),
  (phrase: "Sed cervae bonae bestiae sunt.", transcription: "", translation: "Lecz łanie są dobrymi zwierzętami."),
  (phrase: "Diana est patrona cervarum.", transcription: "", translation: "Diana jest patronką łań."),
  (phrase: "quis", transcription: "", translation: "kto"),
  (phrase: "in silvam", transcription: "", translation: "do lasu"),
  (phrase: "Quis in silvam properat?", transcription: "", translation: "Kto śpieszy do lasu?"),
  (phrase: "Quem puellae adorant?", transcription: "", translation: "Kogo czczą dziewczęta?"),
  (phrase: "Quid puellae in ara collocant?", transcription: "", translation: "Co dziewczęta kładą na ołtarzu?"),
)

#line(length: 100%)
#textblock(role: "source", dir: ltr, script: "latn", [
Minerva pugnarum patrona est\. Diana autem est silvarum domina\.

Feras bestias Diana non amat\. Dea sagittis feras bestias necat\.

Sed cervae bonae bestiae sunt\. Cervas Diana non necat\. Diana est patrona cervarum\.

])

#line(length: 100%)
#textblock(role: "translation", dir: ltr, script: "latn", [
Minerwa jest patronką walk\. Diana zaś jest panią lasów\.

Diana nie kocha dzikich zwierząt\. Bogini strzałami zabija dzikie zwierzęta\.

Lecz łanie są dobrymi zwierzętami\. Łań Diana nie zabija\. Diana jest patronką łań\.

])


#pagebreak(weak: true)

= Ogród

#vocabulary(dir: ltr, script: "latn",
  (phrase: "hortus", grammar: "m", transcription: "", translation: "ogród"),
  (phrase: "amicus", grammar: "m", transcription: "", translation: "przyjaciel"),
  (phrase: "pila", grammar: "f", transcription: "", translation: "piłka"),
  (phrase: "meus", grammar: "", transcription: "", translation: "mój"),
  (phrase: "tuus", grammar: "", transcription: "", translation: "twój"),
  (phrase: "gratus", grammar: "", transcription: "", translation: "miły, mile widziany"),
  (phrase: "molestus", grammar: "", transcription: "", translation: "uciążliwy, kłopotliwy"),
  (phrase: "invitare", grammar: "", transcription: "", translation: "zapraszać"),
  (phrase: "obtemperare", grammar: "", transcription: "", translation: "być posłusznym, ulegać"),
  (phrase: "exspectare", grammar: "", transcription: "", translation: "oczekiwać, czekać"),
  (phrase: "delectare", grammar: "", transcription: "", translation: "cieszyć, zachwycać"),
  (phrase: "properare", grammar: "", transcription: "", translation: "spieszyć się, pospieszać"),
  (phrase: "sum", grammar: "V", transcription: "", translation: "jestem"),
  (phrase: "esse", grammar: "", transcription: "", translation: "być"),
  (phrase: "ego", grammar: "Pron", transcription: "", translation: "ja"),
  (phrase: "tu", grammar: "Pron", transcription: "", translation: "ty"),
  (phrase: "nos", grammar: "Pron", transcription: "", translation: "my"),
  (phrase: "vos", grammar: "Pron", transcription: "", translation: "wy"),
  (phrase: "me", grammar: "Pron acc", transcription: "", translation: "mnie"),
  (phrase: "te", grammar: "Pron acc", transcription: "", translation: "ciebie"),
  (phrase: "in", grammar: "Prep", transcription: "", translation: "w, do"),
  (phrase: "at", grammar: "Conj", transcription: "", translation: "ale, lecz"),
  (phrase: "libenter", grammar: "Adv", transcription: "", translation: "chętnie"),
  (phrase: "magnopere", grammar: "Adv", transcription: "", translation: "bardzo, wielce"),
  (phrase: "non", grammar: "Adv", transcription: "", translation: "nie"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "hortus", transcription: "", translation: "ogród"),
  (phrase: "hortus meus", transcription: "", translation: "mój ogród"),
  (phrase: "in hortum meum", transcription: "", translation: "do mojego ogrodu"),
  (phrase: "In hortum meum invito te, Tite!", transcription: "", translation: "Zapraszam cię do mojego ogrodu, Tytusie!"),
  (phrase: "amici", transcription: "", translation: "przyjaciele"),
  (phrase: "amici mei", transcription: "", translation: "moi przyjaciele"),
  (phrase: "In horti amici mei sunt.", transcription: "", translation: "W ogrodzie są moi przyjaciele."),
  (phrase: "libenter", transcription: "", translation: "chętnie"),
  (phrase: "obtempero", transcription: "", translation: "jestem posłuszny"),
  (phrase: "Libenter obtempero.", transcription: "", translation: "Chętnie się zgadzam."),
  (phrase: "molestus non sum", transcription: "", translation: "nie jestem uciążliwy"),
  (phrase: "Amicis tuis molestus non sum?", transcription: "", translation: "Czy nie jestem uciążliwy twoim przyjaciołom?"),
  (phrase: "gratus es", transcription: "", translation: "jesteś mile widziany"),
  (phrase: "At tu gratus es amicis.", transcription: "", translation: "Ale ty jesteś mile widziany przyjaciołom."),
  (phrase: "Amici mei et me et te exspectant.", transcription: "", translation: "Moi przyjaciele czekają i na mnie, i na ciebie."),
  (phrase: "pila", transcription: "", translation: "piłka"),
  (phrase: "pila vos delectat", transcription: "", translation: "piłka was cieszy"),
  (phrase: "Pila-ne vos delectat?", transcription: "", translation: "Czy piłka was cieszy?"),
  (phrase: "Magnopere nos pila delectat.", transcription: "", translation: "Bardzo cieszy nas piłka."),
  (phrase: "Propera, amice!", transcription: "", translation: "Spiesz się, przyjacielu!"),
)

#line(length: 100%)
#dialog(dir: ltr, script: "latn", role: "source",
  (header: "Marcus:", content: [In hortum meum invito te, Tite! In horti amici mei sunt\.

]),
  (header: "Titus:", content: [Libenter obtempero\. Amicis tuis molestus non sum?

]),
  (header: "Marcus:", content: [At tu gratus es amicis\. Amici mei et me et te exspectant\.

]),
  (header: "Titus:", content: [Pila\-ne vos delectat?

]),
  (header: "Marcus:", content: [Magnopere nos pila delectat\. Propera, amice!

]),
)

#line(length: 100%)
#dialog(dir: ltr, script: "latn", role: "translation",
  (header: "Marek:", content: [Zapraszam cię do mojego ogrodu, Tytusie! W ogrodzie są moi przyjaciele\.

]),
  (header: "Tytus:", content: [Chętnie się zgadzam\. Czy nie jestem uciążliwy dla twoich przyjaciół?

]),
  (header: "Marek:", content: [Ale ty jesteś mile widziany przez przyjaciół\. Moi przyjaciele czekają i na mnie, i na ciebie\.

]),
  (header: "Tytus:", content: [Czy piłka was cieszy?

]),
  (header: "Marek:", content: [Bardzo cieszy nas piłka\. Spiesz się, przyjacielu!

]),
)


#pagebreak(weak: true)

= Świątynia

#vocabulary(dir: ltr, script: "latn",
  (phrase: "templum", grammar: "N n", transcription: "", translation: "świątynia"),
  (phrase: "deus", grammar: "N m", transcription: "", translation: "bóg"),
  (phrase: "columna", grammar: "N f", transcription: "", translation: "kolumna"),
  (phrase: "domicilium", grammar: "N n", transcription: "", translation: "mieszkanie; siedziba"),
  (phrase: "oppidum", grammar: "N n", transcription: "", translation: "miasto; gród"),
  (phrase: "donum", grammar: "N n", transcription: "", translation: "dar"),
  (phrase: "turba", grammar: "N f", transcription: "", translation: "tłum"),
  (phrase: "vestimentum", grammar: "N n", transcription: "", translation: "szata; ubranie"),
  (phrase: "corona", grammar: "N f", transcription: "", translation: "wieniec; korona"),
  (phrase: "copia", grammar: "N f", transcription: "", translation: "mnóstwo; obfitość"),
  (phrase: "sacrificium", grammar: "N n", transcription: "", translation: "ofiara"),
  (phrase: "gratia", grammar: "N f", transcription: "", translation: "łaska; przychylność"),
  (phrase: "magnificus", grammar: "Adj", transcription: "", translation: "wspaniały"),
  (phrase: "magnus", grammar: "Adj", transcription: "", translation: "wielki"),
  (phrase: "multus", grammar: "Adj", transcription: "", translation: "liczny"),
  (phrase: "clarus", grammar: "Adj", transcription: "", translation: "sławny; jasny"),
  (phrase: "propitius", grammar: "Adj", transcription: "", translation: "przychylny; łaskawy"),
  (phrase: "albus", grammar: "Adj", transcription: "", translation: "biały"),
  (phrase: "cunctus", grammar: "Adj", transcription: "", translation: "cały; wszyscy razem"),
  (phrase: "patrius", grammar: "Adj", transcription: "", translation: "ojczysty"),
  (phrase: "suus", grammar: "Adj", transcription: "", translation: "swój"),
  (phrase: "ornare", grammar: "V", transcription: "", translation: "ozdabiać"),
  (phrase: "superare", grammar: "V", transcription: "", translation: "przewyższać"),
  (phrase: "properare", grammar: "V", transcription: "", translation: "śpieszyć się"),
  (phrase: "portare", grammar: "V", transcription: "", translation: "nieść"),
  (phrase: "conciliare", grammar: "V", transcription: "", translation: "zjednywać"),
  (phrase: "ad", grammar: "Prep", transcription: "", translation: "do (z biernikiem)"),
  (phrase: "in", grammar: "Prep", transcription: "", translation: "w (z ablativem)"),
  (phrase: "et", grammar: "Conj", transcription: "", translation: "i"),
  (phrase: "nam", grammar: "Conj", transcription: "", translation: "bowiem"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "templum", transcription: "", translation: "świątynia"),
  (phrase: "templum dei", transcription: "", translation: "świątynia boga"),
  (phrase: "templum dei magnificum", transcription: "", translation: "wspaniała świątynia boga"),
  (phrase: "Templum dei magnificum est.", transcription: "", translation: "Świątynia boga jest wspaniała."),
  (phrase: "columna", transcription: "", translation: "kolumna"),
  (phrase: "columnae", transcription: "", translation: "kolumny"),
  (phrase: "Templum columnae ornant.", transcription: "", translation: "Kolumny ozdabiają świątynię."),
  (phrase: "turba", transcription: "", translation: "tłum"),
  (phrase: "turba magna", transcription: "", translation: "wielki tłum"),
  (phrase: "ad templum properat", transcription: "", translation: "śpieszy do świątyni"),
  (phrase: "Ad templum turba magna properat.", transcription: "", translation: "Wielki tłum śpieszy do świątyni."),
  (phrase: "vestimentis albis", transcription: "", translation: "w białych szatach"),
  (phrase: "vestimentis albis et coronis", transcription: "", translation: "w białych szatach i wieńcach"),
  (phrase: "ornati sunt", transcription: "", translation: "są ozdobieni"),
  (phrase: "Cuncti vestimentis albis et coronis ornati sunt.", transcription: "", translation: "Wszyscy są ozdobieni białymi szatami i wieńcami."),
  (phrase: "gratiam dei", transcription: "", translation: "łaskę boga"),
  (phrase: "sacrificiis et donis", transcription: "", translation: "ofiarami i darami"),
  (phrase: "oppido patrio et domiciliis suis", transcription: "", translation: "ojczystemu miastu i swoim domom"),
  (phrase: "Sacrificiis et donis gratiam dei oppido patrio et domiciliis suis conciliant.", transcription: "", translation: "Ofiarami i darami zjednują łaskę boga ojczystemu miastu i swoim domom."),
)

#line(length: 100%)
#textblock(role: "source", dir: ltr, script: "latn", [
Templum dei magnificum est\. Templum columnae ornant\. Domicilia oppidi templum superat\. Multa dona sunt in templo\. Nam deus claro oppido propitius est\. Ad templum turba magna properat\.

Cuncti vestimentis albis et coronis ornati sunt\. Magnam copiam donorum portant\. Sacrificiis et donis gratiam dei oppido patrio et domiciliis suis conciliant\.

])

#line(length: 100%)
#textblock(role: "translation", dir: ltr, script: "latn", [
Świątynia boga jest wspaniała\. Kolumny ozdabiają świątynię\. Świątynia przewyższa domy miasta\. W świątyni jest wiele darów\. Bowiem bóg jest przychylny sławnemu miastu\. Wielki tłum śpieszy do świątyni\.

Wszyscy są ozdobieni białymi szatami i wieńcami\. Niosą wielką ilość darów\. Ofiarami i darami zjednują łaskę boga ojczystemu miastu i swoim domom\.

])


#pagebreak(weak: true)

= Rzymianin

#vocabulary(dir: ltr, script: "latn",
  (phrase: "vir", grammar: "N m", transcription: "", translation: "mąż; mężczyzna"),
  (phrase: "forum", grammar: "N n", transcription: "", translation: "forum; rynek"),
  (phrase: "vestimentum", grammar: "N n", transcription: "", translation: "szata; ubranie"),
  (phrase: "toga", grammar: "N f", transcription: "", translation: "toga"),
  (phrase: "curia", grammar: "N f", transcription: "", translation: "kuria; sala obrad senatu"),
  (phrase: "patria", grammar: "N f", transcription: "", translation: "ojczyzna"),
  (phrase: "sapientia", grammar: "N f", transcription: "", translation: "mądrość"),
  (phrase: "constantia", grammar: "N f", transcription: "", translation: "stałość; wytrwałość"),
  (phrase: "gloria", grammar: "N f", transcription: "", translation: "chwała; sława"),
  (phrase: "Romanus", grammar: "Adj", transcription: "", translation: "rzymski"),
  (phrase: "albus", grammar: "Adj", transcription: "", translation: "biały"),
  (phrase: "magnus", grammar: "Adj", transcription: "", translation: "wielki; duży"),
  (phrase: "properare", grammar: "V", transcription: "", translation: "śpieszyć (się)"),
  (phrase: "ornare", grammar: "V", transcription: "", translation: "zdobić; ozdabiać"),
  (phrase: "deliberare", grammar: "V", transcription: "", translation: "naradzać się; rozważać"),
  (phrase: "parare", grammar: "V", transcription: "", translation: "przygotowywać; zapewniać"),
  (phrase: "esse", grammar: "V", transcription: "", translation: "być"),
  (phrase: "in", grammar: "Prep", transcription: "", translation: "w; do; na (z abl. lub acc.)"),
  (phrase: "de", grammar: "Prep", transcription: "", translation: "o; na temat (z abl.)"),
  (phrase: "et", grammar: "Conj", transcription: "", translation: "i"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "vir", transcription: "", translation: "mąż"),
  (phrase: "vir Romanus", transcription: "", translation: "Rzymianin; mąż rzymski"),
  (phrase: "in forum", transcription: "", translation: "na forum"),
  (phrase: "properare", transcription: "", translation: "śpieszyć"),
  (phrase: "Vir Romanus in forum properat.", transcription: "", translation: "Rzymianin śpieszy na forum."),
  (phrase: "vestimentum", transcription: "", translation: "szata"),
  (phrase: "vestimentum viri", transcription: "", translation: "szata męża"),
  (phrase: "vestimentum viri Romani", transcription: "", translation: "szata Rzymianina"),
  (phrase: "toga alba", transcription: "", translation: "biała toga"),
  (phrase: "Vestimentum viri Romani toga alba est.", transcription: "", translation: "Szatą Rzymianina jest biała toga."),
  (phrase: "constantia", transcription: "", translation: "stałość"),
  (phrase: "virum Romanum", transcription: "", translation: "Rzymianina (acc.)"),
  (phrase: "Virum Romanum constantia ornat.", transcription: "", translation: "Rzymianina zdobi stałość."),
  (phrase: "in foro", transcription: "", translation: "na forum"),
  (phrase: "in curia", transcription: "", translation: "w kurii"),
  (phrase: "de patria", transcription: "", translation: "o ojczyźnie"),
  (phrase: "deliberare", transcription: "", translation: "naradzać się"),
  (phrase: "In foro et in curia viri Romani de patria deliberant.", transcription: "", translation: "Na forum i w kurii Rzymianie naradzają się o ojczyźnie."),
  (phrase: "sapientia et constantia", transcription: "", translation: "mądrość i stałość"),
  (phrase: "virorum Romanorum", transcription: "", translation: "Rzymian (gen. pl.)"),
  (phrase: "gloriam magnam", transcription: "", translation: "wielką chwałę"),
  (phrase: "patriae", transcription: "", translation: "ojczyźnie (dat.)"),
  (phrase: "Sapientia et constantia virorum Romanorum patriae gloriam magnam parant.", transcription: "", translation: "Mądrość i stałość Rzymian zapewniają ojczyźnie wielką chwałę."),
)

#line(length: 100%)
#textblock(role: "source", dir: ltr, script: "latn", [
Vir Romanus in forum properat\. Vestimentum viri Romani toga alba est\. Virum Romanum constantia ornat\. In foro et in curia viri Romani de patria deliberant\. Sapientia et constantia virorum Romanorum patriae gloriam magnam parant\.

])

#line(length: 100%)
#textblock(role: "translation", dir: ltr, script: "latn", [
Rzymianin śpieszy na forum\. Szatą Rzymianina jest biała toga\. Rzymianina zdobi stałość\. Na forum i w kurii Rzymianie naradzają się o ojczyźnie\. Mądrość i stałość Rzymian zapewniają ojczyźnie wielką chwałę\.

])


#pagebreak(weak: true)

= Marek, chłopiec rzymski

#vocabulary(dir: ltr, script: "latn",
  (phrase: "Marcus", grammar: "N m sg", transcription: "", translation: "Marek"),
  (phrase: "puer", grammar: "N m sg", transcription: "", translation: "chłopiec"),
  (phrase: "schola", grammar: "N f sg", transcription: "", translation: "szkoła"),
  (phrase: "vestimentum", grammar: "N n sg", transcription: "", translation: "ubranie; szata"),
  (phrase: "toga", grammar: "N f sg", transcription: "", translation: "toga"),
  (phrase: "tunica", grammar: "N f sg", transcription: "", translation: "tunika"),
  (phrase: "servus", grammar: "N m sg", transcription: "", translation: "niewolnik; sługa"),
  (phrase: "tabula", grammar: "N f sg", transcription: "", translation: "tabliczka (do pisania)"),
  (phrase: "fortuna", grammar: "N f sg", transcription: "", translation: "los; dola"),
  (phrase: "vir", grammar: "N m sg", transcription: "", translation: "mąż; mężczyzna"),
  (phrase: "Romanus", grammar: "Adj", transcription: "", translation: "rzymski"),
  (phrase: "multus", grammar: "Adj", transcription: "", translation: "liczny; wielu"),
  (phrase: "miser", grammar: "Adj", transcription: "", translation: "nędzny; nieszczęsny"),
  (phrase: "fidus", grammar: "Adj", transcription: "", translation: "wierny"),
  (phrase: "liber", grammar: "Adj", transcription: "", translation: "wolny"),
  (phrase: "carus", grammar: "Adj", transcription: "", translation: "drogi; miły"),
  (phrase: "properare", grammar: "V", transcription: "", translation: "śpieszyć"),
  (phrase: "adproperare", grammar: "V", transcription: "", translation: "przybiegać; nadbiegać"),
  (phrase: "portare", grammar: "V", transcription: "", translation: "nosić; zanosić"),
  (phrase: "esse", grammar: "V", transcription: "", translation: "być"),
  (phrase: "etiam", grammar: "Adv", transcription: "", translation: "także; również"),
  (phrase: "sed", grammar: "Conj", transcription: "", translation: "lecz; ale"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "Marcus", transcription: "", translation: "Marek"),
  (phrase: "in scholam", transcription: "", translation: "do szkoły"),
  (phrase: "properat", transcription: "", translation: "śpieszy"),
  (phrase: "Marcus in scholam properat.", transcription: "", translation: "Marek śpieszy do szkoły."),
  (phrase: "puer Romanus", transcription: "", translation: "chłopiec rzymski"),
  (phrase: "Marcus puer Romanus est.", transcription: "", translation: "Marek jest chłopcem rzymskim."),
  (phrase: "multi pueri", transcription: "", translation: "liczni chłopcy"),
  (phrase: "Multi pueri adproperant.", transcription: "", translation: "Liczni chłopcy nadbiegają."),
  (phrase: "vestimentum pueri", transcription: "", translation: "ubranie chłopca"),
  (phrase: "toga", transcription: "", translation: "toga"),
  (phrase: "Vestimentum pueri Romani toga est.", transcription: "", translation: "Ubraniem chłopca rzymskiego jest toga."),
  (phrase: "tunicae puerorum", transcription: "", translation: "tuniki chłopców"),
  (phrase: "Etiam tunicae puerorum Romanorum vestimenta sunt.", transcription: "", translation: "Także tuniki chłopców rzymskich są ubraniami."),
  (phrase: "servi", transcription: "", translation: "niewolnicy"),
  (phrase: "tabulas portant", transcription: "", translation: "noszą tabliczki"),
  (phrase: "Servi pueris tabulas portant.", transcription: "", translation: "Niewolnicy noszą chłopcom tabliczki."),
  (phrase: "fortuna servorum", transcription: "", translation: "los niewolników"),
  (phrase: "Fortuna servorum misera est.", transcription: "", translation: "Los niewolników jest nieszczęsny."),
  (phrase: "fidi servi", transcription: "", translation: "wierni niewolnicy"),
  (phrase: "viris liberis", transcription: "", translation: "wolnym mężom"),
  (phrase: "cari sunt", transcription: "", translation: "są drodzy"),
  (phrase: "Sed fidi servi viris liberis cari sunt.", transcription: "", translation: "Lecz wierni niewolnicy są drodzy wolnym mężom."),
)

#line(length: 100%)
#textblock(role: "source", dir: ltr, script: "latn", [
Marcus in scholam properat\. Marcus puer Romanus est\. Multi pueri adproperant\. Vestimentum pueri Romani toga est\. Etiam tunicae puerorum Romanorum vestimenta sunt\. Servi pueris tabulas portant\. Fortuna servorum misera est\. Sed fidi servi viris liberis cari sunt\.

])

#line(length: 100%)
#textblock(role: "translation", dir: ltr, script: "latn", [
Marek śpieszy do szkoły\. Marek jest chłopcem rzymskim\. Liczni chłopcy nadbiegają\. Ubraniem chłopca rzymskiego jest toga\. Także tuniki chłopców rzymskich są ubraniami\. Niewolnicy noszą chłopcom tabliczki\. Los niewolników jest nieszczęsny\. Lecz wierni niewolnicy są drodzy wolnym mężom\.

])


#pagebreak(weak: true)

= Nauczyciel

#vocabulary(dir: ltr, script: "latn",
  (phrase: "liber", grammar: "N m", transcription: "", translation: "książka"),
  (phrase: "magister", grammar: "N m", transcription: "", translation: "nauczyciel"),
  (phrase: "puer", grammar: "N m", transcription: "", translation: "chłopiec"),
  (phrase: "donum", grammar: "N n", transcription: "", translation: "dar; podarunek"),
  (phrase: "schola", grammar: "N f", transcription: "", translation: "szkoła"),
  (phrase: "fabula", grammar: "N f", transcription: "", translation: "opowieść; bajka"),
  (phrase: "vir", grammar: "N m", transcription: "", translation: "mąż; mężczyzna"),
  (phrase: "animus", grammar: "N m", transcription: "", translation: "dusza; umysł"),
  (phrase: "corona", grammar: "N f", transcription: "", translation: "wieniec; korona"),
  (phrase: "pulcher", grammar: "Adj", transcription: "", translation: "piękny"),
  (phrase: "bonus", grammar: "Adj", transcription: "", translation: "dobry"),
  (phrase: "gratus", grammar: "Adj", transcription: "", translation: "miły; wdzięczny"),
  (phrase: "doctus", grammar: "Adj", transcription: "", translation: "uczony"),
  (phrase: "noster", grammar: "Adj", transcription: "", translation: "nasz"),
  (phrase: "vester", grammar: "Adj", transcription: "", translation: "wasz"),
  (phrase: "meus", grammar: "Adj", transcription: "", translation: "mój"),
  (phrase: "tuus", grammar: "Adj", transcription: "", translation: "twój"),
  (phrase: "multus", grammar: "Adj", transcription: "", translation: "liczny; wiele"),
  (phrase: "donare", grammar: "V", transcription: "", translation: "darować; obdarowywać"),
  (phrase: "delectare", grammar: "V", transcription: "", translation: "cieszyć; sprawiać radość"),
  (phrase: "esse", grammar: "V", transcription: "", translation: "być"),
  (phrase: "in", grammar: "Prep", transcription: "", translation: "w (z abl.)"),
  (phrase: "et", grammar: "Conj", transcription: "", translation: "i"),
  (phrase: "quam", grammar: "Adv", transcription: "", translation: "jak; jakże"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "liber", transcription: "", translation: "książka"),
  (phrase: "liber tuus", transcription: "", translation: "twoja książka"),
  (phrase: "pulcher liber", transcription: "", translation: "piękna książka"),
  (phrase: "Quam pulcher est liber tuus!", transcription: "", translation: "Jakże piękna jest twoja książka!"),
  (phrase: "donum", transcription: "", translation: "dar"),
  (phrase: "magistri nostri", transcription: "", translation: "naszego nauczyciela"),
  (phrase: "donum magistri", transcription: "", translation: "dar nauczyciela"),
  (phrase: "Liber magistri nostri donum est.", transcription: "", translation: "Książka jest darem naszego nauczyciela."),
  (phrase: "boni pueri", transcription: "", translation: "dobrzy chłopcy"),
  (phrase: "grati magistro", transcription: "", translation: "wdzięczni nauczycielowi"),
  (phrase: "Boni pueri magistro nostro grati sunt.", transcription: "", translation: "Dobrzy chłopcy są wdzięczni naszemu nauczycielowi."),
  (phrase: "coronis et libris", transcription: "", translation: "wieńcami i książkami"),
  (phrase: "bonos pueros", transcription: "", translation: "dobrych chłopców"),
  (phrase: "Bonos pueros magister coronis et libris pulchris donat.", transcription: "", translation: "Nauczyciel obdarowuje dobrych chłopców wieńcami i pięknymi książkami."),
  (phrase: "vir doctus", transcription: "", translation: "uczony mąż"),
  (phrase: "animos nostros", transcription: "", translation: "nasze dusze"),
  (phrase: "fabulis pulchris", transcription: "", translation: "pięknymi opowieściami"),
  (phrase: "Magister, vir doctus, fabulis pulchris animos nostros delectat.", transcription: "", translation: "Nauczyciel, mąż uczony, cieszy nasze dusze pięknymi opowieściami."),
)

#line(length: 100%)
#dialog(dir: ltr, script: "latn", role: "source",
  (header: "Quintus:", content: [Quam pulcher est liber tuus, Marce!

]),
  (header: "Marcus:", content: [Liber magistri nostri donum est\. Boni pueri magistro nostro grati sunt\. Bonos pueros magister coronis et libris pulchris donat\. In libro meo multae et pulchrae fabulae sunt\.

]),
  (header: "Quintus:", content: [Gratane tibi est schola vestra?

]),
  (header: "Marcus:", content: [Schola nostra mihi grata est\. Magister, vir doctus, fabulis pulchris animos nostros delectat\.

]),
)

#line(length: 100%)
#dialog(dir: ltr, script: "latn", role: "translation",
  (header: "Kwintus:", content: [Jakże piękna jest twoja książka, Marku!

]),
  (header: "Marek:", content: [Książka jest darem naszego nauczyciela\. Dobrzy chłopcy są wdzięczni naszemu nauczycielowi\. Nauczyciel obdarowuje dobrych chłopców wieńcami i pięknymi książkami\. W mojej książce jest wiele pięknych opowieści\.

]),
  (header: "Kwintus:", content: [Czy miła ci jest wasza szkoła?

]),
  (header: "Marek:", content: [Nasza szkoła jest mi miła\. Nauczyciel, mąż uczony, cieszy nasze dusze pięknymi opowieściami\.

]),
)


#pagebreak(weak: true)

= Rolnik Kamillus i żeglarz Mamerkus

#vocabulary(dir: ltr, script: "latn",
  (phrase: "nauta", grammar: "N m", transcription: "", translation: "żeglarz"),
  (phrase: "agricola", grammar: "N m", transcription: "", translation: "rolnik"),
  (phrase: "fortuna", grammar: "N f", transcription: "", translation: "los; szczęście; pomyślność"),
  (phrase: "vita", grammar: "N f", transcription: "", translation: "życie"),
  (phrase: "ager", grammar: "N m", transcription: "", translation: "pole; rola"),
  (phrase: "periculum", grammar: "N n", transcription: "", translation: "niebezpieczeństwo"),
  (phrase: "poeta", grammar: "N m", transcription: "", translation: "poeta"),
  (phrase: "divitiae", grammar: "N f pl", transcription: "", translation: "bogactwa"),
  (phrase: "navigium", grammar: "N n", transcription: "", translation: "statek; okręt"),
  (phrase: "frumentum", grammar: "N n", transcription: "", translation: "zboże"),
  (phrase: "aurum", grammar: "N n", transcription: "", translation: "złoto"),
  (phrase: "argentum", grammar: "N n", transcription: "", translation: "srebro"),
  (phrase: "beatus", grammar: "Adj", transcription: "", translation: "szczęśliwy"),
  (phrase: "iucundus", grammar: "Adj", transcription: "", translation: "przyjemny; miły"),
  (phrase: "clarus", grammar: "Adj", transcription: "", translation: "sławny; znakomity"),
  (phrase: "patrius", grammar: "Adj", transcription: "", translation: "ojcowski; ojczysty"),
  (phrase: "peritus", grammar: "Adj", transcription: "", translation: "biegły; doświadczony"),
  (phrase: "magnus", grammar: "Adj", transcription: "", translation: "wielki; duży"),
  (phrase: "liber", grammar: "Adj", transcription: "", translation: "wolny (od czegoś)"),
  (phrase: "laudare", grammar: "V", transcription: "", translation: "chwalić"),
  (phrase: "arare", grammar: "V", transcription: "", translation: "orać"),
  (phrase: "parare", grammar: "V", transcription: "", translation: "przygotowywać; gotować sobie"),
  (phrase: "portare", grammar: "V", transcription: "", translation: "nieść; wieźć"),
  (phrase: "quam", grammar: "Adv", transcription: "", translation: "jak; jakże"),
  (phrase: "etiam", grammar: "Adv", transcription: "", translation: "także; również"),
  (phrase: "tum", grammar: "Adv", transcription: "", translation: "wtedy; wówczas"),
  (phrase: "sibi", grammar: "Pron", transcription: "", translation: "sobie"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "nauta", transcription: "", translation: "żeglarz"),
  (phrase: "agricola", transcription: "", translation: "rolnik"),
  (phrase: "fortuna agricolae", transcription: "", translation: "los rolnika"),
  (phrase: "Mamercus nauta fortunam laudat.", transcription: "", translation: "Żeglarz Mamerkus chwali los."),
  (phrase: "Mamercus nauta Camilli agricolae fortunam laudat.", transcription: "", translation: "Żeglarz Mamerkus chwali los rolnika Kamillusa."),
  (phrase: "beatus es", transcription: "", translation: "jesteś szczęśliwy"),
  (phrase: "agricola beatus", transcription: "", translation: "szczęśliwy rolnik"),
  (phrase: "vita iucunda", transcription: "", translation: "przyjemne życie"),
  (phrase: "Quam iucunda est agricolarum vita!", transcription: "", translation: "Jakże przyjemne jest życie rolników!"),
  (phrase: "agros arant", transcription: "", translation: "orzą pola"),
  (phrase: "agros patrios arant", transcription: "", translation: "orzą ojczyste pola"),
  (phrase: "a periculis liberi", transcription: "", translation: "wolni od niebezpieczeństw"),
  (phrase: "Beati agricolae agros patrios arant, a periculis liberi sunt.", transcription: "", translation: "Szczęśliwi rolnicy orzą ojczyste pola, są wolni od niebezpieczeństw."),
  (phrase: "poetae clari", transcription: "", translation: "sławni poeci"),
  (phrase: "fortunam vestram laudant", transcription: "", translation: "chwalą wasz los"),
  (phrase: "Etiam poetae clari fortunam vestram laudant.", transcription: "", translation: "Także sławni poeci chwalą wasz los."),
  (phrase: "nautae periti", transcription: "", translation: "biegli żeglarze"),
  (phrase: "magnas divitias", transcription: "", translation: "wielkie bogactwa"),
  (phrase: "sibi parant", transcription: "", translation: "gotują sobie"),
  (phrase: "Nautae periti magnas sibi divitias parant.", transcription: "", translation: "Biegli żeglarze gotują sobie wielkie bogactwa."),
  (phrase: "Navigia nautis beatis frumentum, aurum, argentum portant.", transcription: "", translation: "Statki wiozą szczęśliwym żeglarzom zboże, złoto, srebro."),
)

#line(length: 100%)
#textblock(role: "source", dir: ltr, script: "latn", [
Mamercus nauta Camilli agricolae fortunam laudat: „Beatus es, agricola! Quam iucunda est agricolarum vita! Beati agricolae agros patrios arant, a periculis liberi sunt\. Etiam poetae clari fortunam vestram laudant, agricolae beati\.”

Tum Camillus: „Ego tuam, nauta beate, fortunam laudo\. Nautae periti magnas sibi divitias parant\. Navigia nautis beatis frumentum, aurum, argentum portant\.”

])

#line(length: 100%)
#textblock(role: "translation", dir: ltr, script: "latn", [
Żeglarz Mamerkus chwali los rolnika Kamillusa: „Szczęśliwy jesteś, rolniku! Jakże przyjemne jest życie rolników! Szczęśliwi rolnicy orzą ojczyste pola, są wolni od niebezpieczeństw\. Także sławni poeci chwalą wasz los, szczęśliwi rolnicy\.”

Wtedy Kamillus: „Ja chwalę twój los, szczęśliwy żeglarzu\. Biegli żeglarze gotują sobie wielkie bogactwa\. Statki wiozą szczęśliwym żeglarzom zboże, złoto, srebro\.”

])


#pagebreak(weak: true)

= Bóg Merkury

#vocabulary(dir: ltr, script: "latn",
  (phrase: "Mercurius", grammar: "N m sg", transcription: "", translation: "Merkury"),
  (phrase: "misero", grammar: "Adj m sg", transcription: "", translation: "nieszczęśliwy, biedny"),
  (phrase: "incola", grammar: "N m sg", transcription: "", translation: "mieszkaniec"),
  (phrase: "mandatum", grammar: "N n sg", transcription: "", translation: "rozkaz, polecenie"),
  (phrase: "nuntio", grammar: "V", transcription: "", translation: "zwiadamiam, oznajmiam"),
  (phrase: "specto", grammar: "V", transcription: "", translation: "patrzę, przyglądam się"),
  (phrase: "stultus", grammar: "Adj m sg", transcription: "", translation: "głupi"),
  (phrase: "fortuna", grammar: "N f sg", transcription: "", translation: "los, fortuna"),
  (phrase: "ignoro", grammar: "V", transcription: "", translation: "nie znam, nie wiem"),
  (phrase: "laudo", grammar: "V", transcription: "", translation: "chwalę"),
  (phrase: "propero", grammar: "V", transcription: "", translation: "śpieszę się, pośpieszam"),
  (phrase: "nauta", grammar: "N m sg", transcription: "", translation: "żeglarz, marynarz"),
  (phrase: "agricola", grammar: "N m sg", transcription: "", translation: "rolnik"),
  (phrase: "salvus", grammar: "Adj m sg", transcription: "", translation: "zdrowy, cali (powitanie)"),
  (phrase: "patronus", grammar: "N m sg", transcription: "", translation: "patron, opiekun"),
  (phrase: "propitius", grammar: "Adj m sg", transcription: "", translation: "łaskawy, przychylny"),
  (phrase: "muto", grammar: "V", transcription: "", translation: "zmieniam"),
  (phrase: "donum", grammar: "N n sg", transcription: "", translation: "dar"),
  (phrase: "navigium", grammar: "N n sg", transcription: "", translation: "okręt, statek"),
  (phrase: "socius", grammar: "N m sg", transcription: "", translation: "towarzysz"),
  (phrase: "peritus", grammar: "Adj m sg", transcription: "", translation: "biegły, doświadczony"),
  (phrase: "maestus", grammar: "Adj m sg", transcription: "", translation: "smutny"),
  (phrase: "opulentus", grammar: "Adj m sg", transcription: "", translation: "bogaty, zamożny"),
  (phrase: "praeda", grammar: "N f sg", transcription: "", translation: "łup, grabież"),
  (phrase: "imploro", grammar: "V", transcription: "", translation: "błagam, wzywam"),
  (phrase: "frustra", grammar: "Adv", transcription: "", translation: "na próżno"),
)

#line(length: 100%)
#models(dir: ltr, script: "latn",
  (phrase: "Mercurius deus", transcription: "", translation: "bóg Merkury"),
  (phrase: "de caelo spectat", transcription: "", translation: "patrzy z nieba"),
  (phrase: "Salvi este!", transcription: "", translation: "Bądźcie zdrowi!"),
  (phrase: "Tu quoque salvus es!", transcription: "", translation: "I ty bądź zdrów!"),
  (phrase: "Mercurius deus sum.", transcription: "", translation: "Jestem bogiem Merkurym."),
  (phrase: "Estisne beati?", transcription: "", translation: "Czy jesteście szczęśliwi?"),
  (phrase: "Propitius es nobis!", transcription: "", translation: "Bądź dla nas łaskawy!"),
  (phrase: "Muta fortunam nostram!", transcription: "", translation: "Zmień nasz los!"),
  (phrase: "En! muto fortunam vestram.", transcription: "", translation: "Oto zmieniam wasz los."),
  (phrase: "Neque eratis neque eritis beati.", transcription: "", translation: "Ani byliście, ani będziecie szczęśliwi."),
)

#line(length: 100%)
#textblock(role: "source", dir: ltr, script: "latn", [
Mercurius miseris terrarum incolis beatorum deorum mandata nuntiat\.

Mercurius deus de caelo spectat\. “Quam stulti” inquit, “sunt viri! Suam fortunam ignorant, alienam laudant\.” Et de caelo deus in terram properat, nautae et agricolae adpropinquat\.

“Salvi este!” Mercurius inquit\.

“Tu quoque salvus es!” et nauta inquit et agricola\. “Quis es, pulcher vir?”

“Mercurius deus sum\. Estisne beati?”

Tum nauta: “O patrone” inquit “noster! Propitius es nobis! Muta fortunam nostram! Nam miseri sumus\.”

At Mercurius: “Stulti estis, viri\. Sed ego vobis propitius et eram et ero\. En! muto fortunam vestram\. Tu, Camille, agricola eras: iam nauta eris\. Mamercus autem agricola erit\. Te, Mamerce, agris pulchris dono\. Tibi, Camille, navigium magnum el socii periti erunt\.”

Et Mamercus: “Tandem aliquando erimus beati\.”

At deus: “Neque eratis neque eritis beati\.”

Multo post Camillus nauta Mamercum agricolam spectat\. Et Mamercus: “Cur” inquit “maestus es, Camille? Ubi fuisti?”

“In multis terris et oppidis fui, Mamerce\.”

“Ubi socii tui sunt? Beatine fuistis?”

“Initio fortuna nobis prospera fuit\. Opulenti fuimus et beati\. Sed et divitiae meae et socii undarum praeda fuerunt\.”

Tum Mamercus: “Quam stultus olim fueram! Quam vera dei verba fuerant! Nam ego quoque miser sum\.

Tum Mamereus Mercurium implorat: “O patrone noster! Muta fortunam nostram! Si ego rursus nauta fuero, Camillus autem si fuerit agricola, templum tuum donorum plenum erit\.”

Sed frustra deum implorant\.

])

#line(length: 100%)
#textblock(role: "translation", dir: ltr, script: "latn", [
Merkury zawiadamia nieszczęśliwych mieszkańców ziem o rozkazach błogosławionych bogów\.

Merkury, bóg, patrzy z nieba\. „Jacyż głupi — mówi — są ludzie! Nie znają własnego losu, cudzy chwalą\.” I z nieba bóg śpieszy na ziemię, zbliża się do żeglarza i rolnika\.

„Bądźcie zdrowi!” — mówi Merkury\.

„I ty bądź zdrów!” — mówią żeglarz i rolnik\. „Kim jesteś, piękny mężu?”

„Jestem bogiem Merkurym\. Czy jesteście szczęśliwi?”

Wtedy żeglarz: „O nasz patronie! — mówi — Bądź dla nas łaskawy! Zmień nasz los! Jesteśmy bowiem nieszczęśliwi\.”

Lecz Merkury: „Głupi jesteście, ludzie\. Lecz ja dla was byłem i będę łaskawy\. Oto! zmieniam wasz los\. Ty, Kamillus, byłeś rolnikiem: już będziesz żeglarzem\. Mamerkus zaś będzie rolnikiem\. Tobie, Mamerkusie, daruję piękne pola\. Tobie, Kamillusie, będzie duży statek i biegli towarzysze\.”

I Mamerkus: „Wreszcie kiedyś będziemy szczęśliwi\.”

Lecz bóg: „Ani byliście, ani będziecie szczęśliwi\.”

Długo potem Kamillus żeglarz patrzy na Mamerka rolnika\. I Mamerkus: „Dlaczego — mówi — jesteś smutny, Kamillus? Gdzie byłeś?”

„Byłem w wielu krainach i miastach, Mamerkusie\.”

„Gdzie są twoi towarzysze? Czy byliście szczęśliwi?”

„Na początku los nam sprzyjał\. Byliśmy bogaci i szczęśliwi\. Lecz i moje bogactwa, i towarzysze stali się łupem fal\.”

Wtedy Mamerkus: „Jakże byłem głupi dawniej! Jakże prawdziwe były słowa boga! Bo i ja jestem nieszczęśliwy\.”

Wtedy Mamerkus wzywa Merkurego: „O nasz patronie! Zmień nasz los! Jeśli ja znów będę żeglarzem, a Kamillus będzie rolnikiem, twa świątynia będzie pełna darów\.”

Lecz na próżno wzywają boga\.

])


