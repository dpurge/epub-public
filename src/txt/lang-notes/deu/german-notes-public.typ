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
  title: "Język niemiecki (publiczne)",
  author: "D. Purge",
  description: "Teksty i notatki do nauki języka niemieckiego.\n",
  lang: "de",
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

= Najlepsza metoda języka niemieckiego

Plato v\. Reussner

(1892)


#pagebreak(weak: true)

= Erste Lektion

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [Haben Sie Brot?

]),
  (header: "—", content: [Ich habe Brot\.

]),
  (header: "—", content: [Haben Sie Wasser?

]),
  (header: "—", content: [Ich habe Wasser\.

]),
  (header: "—", content: [Haben Sie Butter?

]),
  (header: "—", content: [Ich habe Butter\.

]),
  (header: "—", content: [Haben Sie Kaffee?

]),
  (header: "—", content: [Ich habe Kaffee\.

]),
)

#line(length: 100%)
#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [Haben Sie Wasser?

]),
  (header: "—", content: [Ich habe Wasser\.

]),
  (header: "—", content: [Haben Sie Butter?

]),
  (header: "—", content: [Ich habe Butter\.

]),
  (header: "—", content: [Haben Sie Kaffee?

]),
  (header: "—", content: [Ich habe Kaffee\.

]),
  (header: "—", content: [Haben Sie Brot?

]),
  (header: "—", content: [Ich habe Brot\.

]),
)


#pagebreak(weak: true)

= Zweite Lektion

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [Haben Sie Thee?

]),
  (header: "—", content: [Ich habe Thee\.

]),
  (header: "—", content: [Kaufen Sie Wein?

]),
  (header: "—", content: [Ich kaufe Wein\.

]),
  (header: "—", content: [Kaufen wir Käse?

]),
  (header: "—", content: [Wir kaufen Käse\.

]),
  (header: "—", content: [Kaufen Sie Zucker?

]),
  (header: "—", content: [Ich kaufe Zucker\.

]),
  (header: "—", content: [Kaufen Sie Brot?

]),
  (header: "—", content: [Ich kaufe Brot\.

]),
)

#line(length: 100%)
#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [Kaufen Sie Thee?

]),
  (header: "—", content: [Ich kaufe Thee\.

]),
  (header: "—", content: [Kaufen Sie Wein?

]),
  (header: "—", content: [Ich kaufe Wein\.

]),
  (header: "—", content: [Haben Sie Zucker?

]),
  (header: "—", content: [Wir haben Zucker\.

]),
  (header: "—", content: [Kaufen Sie Brot?

]),
  (header: "—", content: [Wir kaufen Brot\.

]),
)


#pagebreak(weak: true)

= Dritte Lektion

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [Essen Sie Kuchen?

]),
  (header: "—", content: [Ich esse Kuchen und Brot\.

]),
  (header: "—", content: [Essen wir Braten?

]),
  (header: "—", content: [Wir essen Braten\.

]),
  (header: "—", content: [Essen Sie Fleisch?

]),
  (header: "—", content: [Ich esse Fleisch und Braten\.

]),
  (header: "—", content: [Trinken Sie Wasser?

]),
  (header: "—", content: [Wir trinken Wasser und Wein\.

]),
  (header: "—", content: [Kaufen Sie Pfeffer?

]),
  (header: "—", content: [Wir kaufen Pfeffer und Essig\.

]),
  (header: "—", content: [Trinken wir Thee?

]),
  (header: "—", content: [Wir trinken Thee und Kaffee\.

]),
)

#line(length: 100%)
#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [Essen Sie Braten?

]),
  (header: "—", content: [Ich esse Braten und Fleisch\.

]),
  (header: "—", content: [Essen Sie Kuchen?

]),
  (header: "—", content: [Ich esse Kuchen und Brot\.

]),
  (header: "—", content: [Essen Sie Fleisch?

]),
  (header: "—", content: [Ich esse Fleisch und Käse\.

]),
  (header: "—", content: [Trinken Sie Wasser?

]),
  (header: "—", content: [Ich trinke Wasser und Wein\.

]),
  (header: "—", content: [Kaufen Sie Pfeffer?

]),
  (header: "—", content: [Ich kaufe Pfeffer und Essig\.

]),
  (header: "—", content: [Trinken Sie Kaffee?

]),
  (header: "—", content: [Ich trinke Kaffee, Thee und Wasser\.

]),
)


