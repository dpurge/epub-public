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
  title: "Język hebrajski (publiczne)",
  author: "D. Purge",
  description: "Notatki do nauki języka hebrajskiego\n",
  lang: "en",
  dir: rtl,
  large-script: true,
  cover: "/cover.svg",
  font-body: ("Noto Serif Hebrew", "Gentium"),
  font-header: ("Noto Sans Hebrew", "Noto Sans"),
  font-transcription: ("Noto Sans", "DejaVu Sans"),
  font-translation: ("Noto Serif", "Gentium"),
  font-strong: ("Noto Sans Hebrew", "Gentium"),
  font-emph: ("Noto Rashi Hebrew", "Gentium"),
  font-slots: ("body": "Noto Serif Hebrew", "emphasis": "Noto Rashi Hebrew", "header": "Noto Sans Hebrew", "hebr dialog header": "Noto Sans Hebrew", "hebr questions answer": "Noto Sans Hebrew", "hebr questions question": "Noto Serif Hebrew", "hebr vocabulary phrase": "Noto Rashi Hebrew", "latn text transcription": "Noto Sans Mono", "latn vocabulary transcription": "Noto Sans", "strong": "Noto Sans Hebrew", "transcription": "Noto Sans", "translation": "Noto Serif"),
  book-script: "hebr",
)

= Sfat Amenu

Moses Rath

(1917)


#pagebreak(weak: true)

= 1

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "חַלּוֹן", grammar: "", transcription: "", translation: "okno"),
  (phrase: "בְּ", grammar: "", transcription: "", translation: "w; z"),
  (phrase: "וְ", grammar: "", transcription: "", translation: "i; a"),
  (phrase: "מַה?", grammar: "", transcription: "", translation: "co? jak?"),
  (phrase: "אַיֵּה?", grammar: "", transcription: "", translation: "gdzie?"),
  (phrase: "שְׁאֵלָה", grammar: "", transcription: "", translation: "pytanie"),
  (phrase: "תְּשׁוּבָה", grammar: "", transcription: "", translation: "odpowiedź"),
  (phrase: "בַּיִת", grammar: "", transcription: "", translation: "dom"),
  (phrase: "חֶדֶר", grammar: "", transcription: "", translation: "pokój"),
  (phrase: "יֵשׁ", grammar: "", transcription: "", translation: "jest; istnieje"),
  (phrase: "תִּקְרָה", grammar: "", transcription: "", translation: "powała; sufit"),
  (phrase: "רִצְפָּה", grammar: "", transcription: "", translation: "podłoga"),
  (phrase: "קִיר", grammar: "", transcription: "", translation: "ściana"),
  (phrase: "דֶּלֶת", grammar: "", transcription: "", translation: "drzwi"),
)

#line(length: 100%)
#textblock(role: "source", dir: rtl, script: "hebr", [
בַּבַּיִת יֵשׁ חֶדֶר\. הַחֶדֶר בַּבַּיִת\. בַּחֶדֶר יֵשׁ תִּקְרָה\. בַּחֶדֶר יֶשׁ רִצְפָּה\. בַּחֶדֶר יֵשׁ תִּקְרָה, רִצְפָּה וְקִיר\. הַתִּקְרָה בַּחֶדֶר\. הָרִצְפָּה בַּחֶדֶר\. בַּקִּיר יֵשׁ דֶּלֶת\. בַּקִּיר יֵשׁ חַלּוֹן\. הַדֶּלֶת וְהַחַלּוֹן בַּקִּיר\.

])

== שְׁאֵלוֹת

#questions(dir: rtl, script: "hebr", role: "source",
  (question: "מַה־יֵּשׁ בַּבַּיִת?", answer: ""),
  (question: "אַיֵּה הַחֶדֶר?", answer: ""),
  (question: "מַה־יֵּשׁ בַּחֶדֶר?", answer: ""),
  (question: "אַיֵּה הַתִּקְרָה?", answer: ""),
  (question: "אַיֵּה הָרִצְפָּה?", answer: ""),
  (question: "מַה־יֵּשׁ בַּקִּיר?", answer: ""),
  (question: "אַיֵּה הַדֶּלֶת וְהַחַלּוֹן?", answer: ""),
)


#pagebreak(weak: true)

= 2

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "פִּנָּה", grammar: "", transcription: "", translation: "kąt"),
  (phrase: "אֵיפֹה?", grammar: "", transcription: "", translation: "gdzie?"),
  (phrase: "שֶׁל־מִי?", grammar: "", transcription: "", translation: "czyj?"),
  (phrase: "לְ", grammar: "", transcription: "", translation: "do"),
  (phrase: "תַּנּוּר", grammar: "", transcription: "", translation: "piec"),
  (phrase: "עַל", grammar: "", transcription: "", translation: "na; nad"),
  (phrase: "גַּג", grammar: "", transcription: "", translation: "dach"),
  (phrase: "תְּמוּנָה", grammar: "", transcription: "", translation: "obraz"),
  (phrase: "עוֹמֵד", grammar: "", transcription: "", translation: "stoi"),
)


#pagebreak(weak: true)

= 3

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "אָב", grammar: "", transcription: "", translation: "ojciec"),
  (phrase: "אֵם", grammar: "", transcription: "", translation: "matka"),
  (phrase: "רַק", grammar: "", transcription: "", translation: "tylko"),
  (phrase: "הוּא", grammar: "", transcription: "", translation: "on"),
  (phrase: "אִישׁ", grammar: "", transcription: "", translation: "mężczyzna; człowiek"),
  (phrase: "טוֹב", grammar: "", transcription: "", translation: "dobry"),
  (phrase: "מְאֹד", grammar: "", transcription: "", translation: "bardzo"),
  (phrase: "אָח", grammar: "", transcription: "", translation: "brat"),
  (phrase: "אֲשֶׁר", grammar: "", transcription: "", translation: "który"),
  (phrase: "חָכָם", grammar: "", transcription: "", translation: "mądry"),
  (phrase: "קָטָן", grammar: "", transcription: "", translation: "mały"),
  (phrase: "גָּדוֹל", grammar: "", transcription: "", translation: "duży; wielki"),
  (phrase: "גַּם", grammar: "", transcription: "", translation: "także"),
  (phrase: "הֲ?", grammar: "", transcription: "", translation: "czy?"),
  (phrase: "הַאִם?", grammar: "", transcription: "", translation: "czy?"),
  (phrase: "כֵּן", grammar: "", transcription: "", translation: "tak; tak jest"),
  (phrase: "לֹא", grammar: "", transcription: "", translation: "nie"),
  (phrase: "מִי?", grammar: "", transcription: "", translation: "kto?"),
  (phrase: "לְמִי?", grammar: "", transcription: "", translation: "komu?"),
  (phrase: "שָׁנָה", grammar: "", transcription: "", translation: "rok"),
  (phrase: "אֲשֶׁר לְ", grammar: "", transcription: "", translation: "który należy"),
)


#pagebreak(weak: true)

= 4

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "אָנֹכִי", grammar: "", transcription: "", translation: "ja"),
  (phrase: "אוֹהֵב", grammar: "", transcription: "", translation: "kocha; lubi"),
  (phrase: "נָתַן", grammar: "", transcription: "", translation: "dał"),
  (phrase: "סֵפֶר", grammar: "", transcription: "", translation: "książka"),
  (phrase: "כָּל־", grammar: "", transcription: "", translation: "każdy; wszystek; cały"),
  (phrase: "אֶחָד", grammar: "", transcription: "", translation: "jeden"),
  (phrase: "גָּבֹהַּ", grammar: "", transcription: "", translation: "wysoki"),
  (phrase: "אֲרֻבָּה", grammar: "", transcription: "", translation: "komin"),
  (phrase: "מִן", grammar: "", transcription: "", translation: "od; z"),
  (phrase: "יוֹצֵא", grammar: "", transcription: "", translation: "wychodzi"),
  (phrase: "עָשָׁן", grammar: "", transcription: "", translation: "dym"),
  (phrase: "כִּי", grammar: "", transcription: "", translation: "bo; ponieważ"),
  (phrase: "נַעַר", grammar: "", transcription: "", translation: "chłopiec"),
  (phrase: "רַע", grammar: "", transcription: "", translation: "zły"),
  (phrase: "עוֹד", grammar: "", transcription: "", translation: "jeszcze"),
  (phrase: "כַּמָּה?", grammar: "", transcription: "", translation: "ile?"),
  (phrase: "לָמָּה?", grammar: "", transcription: "", translation: "dlaczego? na co?"),
  (phrase: "אֶת־מִי?", grammar: "", transcription: "", translation: "kogo?"),
)


#pagebreak(weak: true)

= 5

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "מוֹרֶה", grammar: "", transcription: "", translation: "nauczyciel"),
  (phrase: "תַּלְמִיד", grammar: "", transcription: "", translation: "uczeń"),
  (phrase: "מְלַמֵּד", grammar: "", transcription: "", translation: "uczy"),
  (phrase: "יוֹם", grammar: "", transcription: "", translation: "dzień"),
  (phrase: "חָרוּץ", grammar: "", transcription: "", translation: "pilny"),
  (phrase: "לוֹמֵד", grammar: "", transcription: "", translation: "uczy się"),
  (phrase: "הֵיטֵב", grammar: "", transcription: "", translation: "dobrze"),
  (phrase: "רַבִּים", grammar: "", transcription: "", translation: "wiele; liczni"),
  (phrase: "הַיּוֹם", grammar: "", transcription: "", translation: "dziś"),
  (phrase: "יַפֶה", grammar: "", transcription: "", translation: "ładny"),
  (phrase: "מַתָּנָה", grammar: "", transcription: "", translation: "dar; podarunek"),
  (phrase: "קוֹרֵא", grammar: "", transcription: "", translation: "czyta"),
  (phrase: "סִפּוּר", grammar: "", transcription: "", translation: "opowiadanie; powieść"),
  (phrase: "אֲשֶׁר", grammar: "", transcription: "", translation: "który"),
  (phrase: "מָתַי?", grammar: "", transcription: "", translation: "kiedy?"),
  (phrase: "מַדּוּעַ?", grammar: "", transcription: "", translation: "dlaczego?"),
)


#pagebreak(weak: true)

= 6

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "כּוֹתֵב", grammar: "", transcription: "", translation: "pisze"),
  (phrase: "שִׁעוּר", grammar: "", transcription: "", translation: "zadanie; lekcja"),
  (phrase: "מַחְבֶּרֶת", grammar: "", transcription: "", translation: "zeszyt"),
  (phrase: "נְיָר", grammar: "", transcription: "", translation: "papier"),
  (phrase: "עֵט", grammar: "", transcription: "", translation: "pióro"),
  (phrase: "רָהִיט", grammar: "", transcription: "", translation: "mebel"),
  (phrase: "יוֹשֵׁב", grammar: "", transcription: "", translation: "siedzi"),
  (phrase: "כִּסֵּא", grammar: "", transcription: "", translation: "krzesło"),
  (phrase: "תַּרְגּוּם", grammar: "", transcription: "", translation: "tłumaczenie"),
  (phrase: "בַּמֶּה?", grammar: "", transcription: "", translation: "czym? w czym?"),
  (phrase: "אוֹ", grammar: "", transcription: "", translation: "albo"),
  (phrase: "עִפָּרוֹן", grammar: "", transcription: "", translation: "ołówek"),
  (phrase: "לוּחַ", grammar: "", transcription: "", translation: "tablica"),
  (phrase: "קִרְטוֹן", grammar: "", transcription: "", translation: "kreda"),
  (phrase: "גִּיר", grammar: "", transcription: "", translation: "kreda"),
  (phrase: "חֶרֶט", grammar: "", transcription: "", translation: "rysik; rylec"),
  (phrase: "שֻׁלְחָן", grammar: "", transcription: "", translation: "stół"),
  (phrase: "אֲרוֹן", grammar: "", transcription: "", translation: "szafa"),
  (phrase: "מִמַּה?", grammar: "", transcription: "", translation: "z czego?"),
  (phrase: "אֵצֶל", grammar: "", transcription: "", translation: "przy; obok; u"),
  (phrase: "אֶל", grammar: "", transcription: "", translation: "do; przy; obok"),
)


#pagebreak(weak: true)

= 7

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "בֵּית־הַסֵּפֶר", grammar: "", transcription: "", translation: "szkoła"),
  (phrase: "סַפְסָל", grammar: "", transcription: "", translation: "ławka"),
  (phrase: "מְסַפֵּר", grammar: "", transcription: "", translation: "opowiada"),
  (phrase: "מוֹרָה", grammar: "", transcription: "", translation: "nauczycielka"),
  (phrase: "אִשָּׁה", grammar: "", transcription: "", translation: "niewiasta; kobieta"),
  (phrase: "אָחוֹת", grammar: "", transcription: "", translation: "siostra"),
  (phrase: "תַּלְמִידָה", grammar: "", transcription: "", translation: "uczennica"),
  (phrase: "נָתְנָה", grammar: "", transcription: "", translation: "dała"),
  (phrase: "חַיָּט", grammar: "", transcription: "", translation: "krawiec"),
  (phrase: "תּוֹפֵר", grammar: "", transcription: "", translation: "szyje"),
  (phrase: "בֶּגֶד", grammar: "", transcription: "", translation: "ubranie; odzież"),
  (phrase: "חֲלִיפָה", grammar: "", transcription: "", translation: "ubranie"),
  (phrase: "מַחַט", grammar: "", transcription: "", translation: "igła"),
  (phrase: "סַנְדְּלָר", grammar: "", transcription: "", translation: "szewc"),
  (phrase: "עוֹשֶׂה", grammar: "", transcription: "", translation: "robi"),
  (phrase: "נַעַל", grammar: "", transcription: "", translation: "but"),
  (phrase: "עוֹר", grammar: "", transcription: "", translation: "skóra"),
  (phrase: "נַגָּר", grammar: "", transcription: "", translation: "stolarz"),
  (phrase: "עֵץ", grammar: "", transcription: "", translation: "drzewo"),
  (phrase: "אֵיזֶה?", grammar: "", transcription: "", translation: "jaki? który?"),
)


#pagebreak(weak: true)

= 8

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "נַעֲרָה", grammar: "", transcription: "", translation: "dziewczyna"),
  (phrase: "אִכָּר", grammar: "", transcription: "", translation: "rolnik; wieśniak"),
  (phrase: "חוֹרֵשׁ", grammar: "", transcription: "", translation: "orze"),
  (phrase: "אֲדָמָה", grammar: "", transcription: "", translation: "rola; ziemia"),
  (phrase: "מַחֲרֵשָׁה", grammar: "", transcription: "", translation: "pług"),
  (phrase: "רוֹעֶה", grammar: "", transcription: "", translation: "pasterz"),
  (phrase: "רוֹעֶה", grammar: "", transcription: "", translation: "pasie"),
  (phrase: "עֵדֶר", grammar: "", transcription: "", translation: "trzoda"),
  (phrase: "בַּנָּאִי", grammar: "", transcription: "", translation: "murarz"),
  (phrase: "בּוֹנֶה", grammar: "", transcription: "", translation: "buduje"),
  (phrase: "לְבֵנָה", grammar: "", transcription: "", translation: "cegła"),
  (phrase: "אוֹפֶה", grammar: "", transcription: "", translation: "piekarz"),
  (phrase: "אוֹפֶה", grammar: "", transcription: "", translation: "piecze"),
  (phrase: "לֶחֶם", grammar: "", transcription: "", translation: "chleb"),
  (phrase: "קֶמַח", grammar: "", transcription: "", translation: "mąka"),
  (phrase: "אוֹכֵל", grammar: "", transcription: "", translation: "je"),
  (phrase: "עוּגָה", grammar: "", transcription: "", translation: "ciastko"),
  (phrase: "גָּר", grammar: "", transcription: "", translation: "mieszka"),
  (phrase: "כְּפָר", grammar: "", transcription: "", translation: "wieś"),
  (phrase: "דּוֹד", grammar: "", transcription: "", translation: "wuj; stryj"),
  (phrase: "עִיר", grammar: "", transcription: "", translation: "miasto"),
)


#pagebreak(weak: true)

= 9

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "אֵין", grammar: "", transcription: "", translation: "nie ma"),
  (phrase: "גַּן", grammar: "", transcription: "", translation: "ogród"),
  (phrase: "הַרְבֵּה", grammar: "", transcription: "", translation: "dużo"),
  (phrase: "עָנָף", grammar: "", transcription: "", translation: "gałąź"),
  (phrase: "עָלֶה", grammar: "", transcription: "", translation: "liść"),
  (phrase: "פְּרִי", grammar: "", transcription: "", translation: "owoc"),
  (phrase: "צוֹמֵחַ", grammar: "", transcription: "", translation: "rośnie"),
  (phrase: "נוֹתֵן", grammar: "", transcription: "", translation: "daje"),
  (phrase: "רֵיחַ", grammar: "", transcription: "", translation: "zapach; woń"),
  (phrase: "יַעַר", grammar: "", transcription: "", translation: "las"),
  (phrase: "נָעִים", grammar: "", transcription: "", translation: "przyjemny"),
  (phrase: "פֶּרַח", grammar: "", transcription: "", translation: "kwiat"),
  (phrase: "סוֹף", grammar: "", transcription: "", translation: "koniec"),
  (phrase: "פָּסוּק", grammar: "", transcription: "", translation: "zdanie; wiersz"),
)


#pagebreak(weak: true)

= 10

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "קָנָה", grammar: "", transcription: "", translation: "kupił"),
  (phrase: "חָדָשׁ", grammar: "", transcription: "", translation: "nowy"),
  (phrase: "חָצֵר", grammar: "", transcription: "", translation: "podwórze; dziedziniec"),
  (phrase: "בְּאֵר", grammar: "", transcription: "", translation: "studnia"),
  (phrase: "שׁוֹאֵב", grammar: "", transcription: "", translation: "czerpie"),
  (phrase: "שִׁפְחָה", grammar: "", transcription: "", translation: "służąca"),
  (phrase: "מַיִם", grammar: "", transcription: "", translation: "woda"),
  (phrase: "יָשָׁן", grammar: "", transcription: "", translation: "stary"),
  (phrase: "מוֹכֵר", grammar: "", transcription: "", translation: "sprzedaje"),
  (phrase: "כְּגוֹן", grammar: "", transcription: "", translation: "tak, jak; na przykład"),
  (phrase: "תַּפּוּחַ", grammar: "", transcription: "", translation: "jabłko"),
  (phrase: "אַגָּס", grammar: "", transcription: "", translation: "gruszka"),
  (phrase: "שְׁזִיף", grammar: "", transcription: "", translation: "śliwka"),
  (phrase: "מִסָּבִיב", grammar: "", transcription: "", translation: "dookoła"),
  (phrase: "גָּדֵר", grammar: "", transcription: "", translation: "płot"),
  (phrase: "מִטָה", grammar: "", transcription: "", translation: "łóżko"),
  (phrase: "אֵיזוּ", grammar: "", transcription: "", translation: "które?"),
)


#pagebreak(weak: true)

= 11

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "סוּס", grammar: "", transcription: "", translation: "koń"),
  (phrase: "עֲגָלָה", grammar: "", transcription: "", translation: "wóz"),
  (phrase: "מוֹשֵׁךְ", grammar: "", transcription: "", translation: "ciągnie"),
  (phrase: "נוֹסֵעַ", grammar: "", transcription: "", translation: "jedzie"),
  (phrase: "אֻרְוָה", grammar: "", transcription: "", translation: "stajnia"),
  (phrase: "שָׁבוּעַ", grammar: "", transcription: "", translation: "tydzień"),
  (phrase: "גַּלְגַּל", grammar: "", transcription: "", translation: "koło"),
  (phrase: "מָכַר", grammar: "", transcription: "", translation: "sprzedał"),
  (phrase: "כַּר", grammar: "", transcription: "", translation: "łąka"),
  (phrase: "עֵשֶׂב", grammar: "", transcription: "", translation: "trawa"),
  (phrase: "יָרֹק", grammar: "", transcription: "", translation: "zielony"),
  (phrase: "שֵׁם", grammar: "", transcription: "", translation: "imię"),
  (phrase: "מִסְפָּר", grammar: "", transcription: "", translation: "liczba"),
  (phrase: "שׁוֹר", grammar: "", transcription: "", translation: "wół"),
  (phrase: "אֶחָד", grammar: "", transcription: "", translation: "jeden"),
  (phrase: "אַחַת", grammar: "", transcription: "", translation: "jedna"),
  (phrase: "שְׁנַיִם", grammar: "", transcription: "", translation: "dwa"),
  (phrase: "שְׁתַּיִם", grammar: "", transcription: "", translation: "dwie"),
  (phrase: "שָׁלֹשׁ", grammar: "", transcription: "", translation: "trzy"),
  (phrase: "אַרְבַּע", grammar: "", transcription: "", translation: "cztery"),
  (phrase: "חָמֵשׁ", grammar: "", transcription: "", translation: "pięć"),
  (phrase: "שֵׁשׁ", grammar: "", transcription: "", translation: "sześć"),
  (phrase: "שֶׁבַע", grammar: "", transcription: "", translation: "siedem"),
  (phrase: "שְׁמוֹנֶה", grammar: "", transcription: "", translation: "osiem"),
  (phrase: "תֵּשַׁע", grammar: "", transcription: "", translation: "dziewięć"),
  (phrase: "עֶשֶׂר", grammar: "", transcription: "", translation: "dziesięć"),
)


#pagebreak(weak: true)

= 12

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "פָּרָה", grammar: "", transcription: "", translation: "krowa"),
  (phrase: "עֵז", grammar: "", transcription: "", translation: "koza"),
  (phrase: "חָלָב", grammar: "", transcription: "", translation: "mleko"),
  (phrase: "חֶמְאָה", grammar: "", transcription: "", translation: "masło"),
  (phrase: "גְּבִינָה", grammar: "", transcription: "", translation: "ser"),
  (phrase: "שׁוֹתֶה", grammar: "", transcription: "", translation: "pije"),
  (phrase: "חַם", grammar: "", transcription: "", translation: "ciepły"),
  (phrase: "לָבָן", grammar: "", transcription: "", translation: "biały"),
  (phrase: "רֶגֶל", grammar: "", transcription: "", translation: "noga"),
  (phrase: "קֶרֶן", grammar: "", transcription: "", translation: "róg"),
  (phrase: "שָׂדֶה", grammar: "", transcription: "", translation: "pole"),
  (phrase: "עוֹבֵד", grammar: "", transcription: "", translation: "pracuje"),
  (phrase: "שָׁעָה", grammar: "", transcription: "", translation: "godzina"),
  (phrase: "רֶפֶת", grammar: "", transcription: "", translation: "obora"),
  (phrase: "קַצָּב", grammar: "", transcription: "", translation: "rzeźnik"),
  (phrase: "בָּשָׂר", grammar: "", transcription: "", translation: "mięso"),
  (phrase: "נוֹעֵל", grammar: "", transcription: "", translation: "wkłada buty"),
  (phrase: "רֹאשׁ", grammar: "", transcription: "", translation: "głowa"),
  (phrase: "אָדָם", grammar: "", transcription: "", translation: "człowiek"),
  (phrase: "עִם", grammar: "", transcription: "", translation: "z; przy"),
)


#pagebreak(weak: true)

= 13

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "צִפּוֹר", grammar: "", transcription: "", translation: "ptak"),
  (phrase: "כָּנָף", grammar: "", transcription: "", translation: "skrzydło"),
  (phrase: "הוֹלֵךְ", grammar: "", transcription: "", translation: "idzie"),
  (phrase: "עָף", grammar: "", transcription: "", translation: "lata"),
  (phrase: "כְּלוּב", grammar: "", transcription: "", translation: "klatka"),
  (phrase: "קֵן", grammar: "", transcription: "", translation: "gniazdo"),
  (phrase: "מְזַמֵּר", grammar: "", transcription: "", translation: "śpiewa"),
  (phrase: "קוֹל", grammar: "", transcription: "", translation: "głos"),
  (phrase: "זֶה", grammar: "", transcription: "", translation: "ten"),
  (phrase: "הַזֶּה", grammar: "", transcription: "", translation: "tenże"),
  (phrase: "זֹאת", grammar: "", transcription: "", translation: "ta"),
  (phrase: "הַזֹּאת", grammar: "", transcription: "", translation: "taże"),
  (phrase: "נוֹצָה", grammar: "", transcription: "", translation: "pióro (ptasie)"),
  (phrase: "עוֹף", grammar: "", transcription: "", translation: "ptak; drób"),
  (phrase: "תַּרְנְגוֹל", grammar: "", transcription: "", translation: "kogut"),
  (phrase: "אַוָּז", grammar: "", transcription: "", translation: "gęś"),
  (phrase: "כַּר", grammar: "", transcription: "", translation: "poduszka"),
  (phrase: "כֶּסֶת", grammar: "", transcription: "", translation: "pierzyna; kołdra"),
  (phrase: "לַיְלָה", grammar: "", transcription: "", translation: "noc"),
  (phrase: "יַשֵׁן", grammar: "", transcription: "", translation: "śpi"),
  (phrase: "עַיִן", grammar: "", transcription: "", translation: "oko"),
  (phrase: "רוֹאֶה", grammar: "", transcription: "", translation: "widzi"),
)


#pagebreak(weak: true)

= 14

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "אָחוּ", grammar: "", transcription: "", translation: "łąka"),
  (phrase: "גַּנָּן", grammar: "", transcription: "", translation: "ogrodnik"),
  (phrase: "זוֹרֵעַ", grammar: "", transcription: "", translation: "sieje"),
  (phrase: "תַּפּוּחֵי־אֲדָמָה", grammar: "", transcription: "", translation: "ziemniaki"),
  (phrase: "עוֹבֵד", grammar: "", transcription: "", translation: "uprawia"),
  (phrase: "לוּל", grammar: "", transcription: "", translation: "kurnik"),
  (phrase: "גִּיס", grammar: "", transcription: "", translation: "szwagier"),
  (phrase: "זַגָּג", grammar: "", transcription: "", translation: "szklarz"),
  (phrase: "שִׁמְשָׁה", grammar: "", transcription: "", translation: "szyba"),
  (phrase: "זְכוּכִית", grammar: "", transcription: "", translation: "szkło"),
  (phrase: "כּוֹס", grammar: "", transcription: "", translation: "szklanka; kielich"),
  (phrase: "קוֹבֵעַ", grammar: "", transcription: "", translation: "wprawia; wsadza"),
  (phrase: "בַּקְבּוּק", grammar: "", transcription: "", translation: "flaszka; karafka"),
  (phrase: "מִשְׁקָפַיִם", grammar: "", transcription: "", translation: "okulary"),
  (phrase: "אֹזֶן", grammar: "", transcription: "", translation: "ucho"),
  (phrase: "שׁוֹמֵעַ", grammar: "", transcription: "", translation: "słucha; słyszy"),
  (phrase: "עִוֵּר", grammar: "", transcription: "", translation: "ślepy"),
  (phrase: "חֵרֵשׁ", grammar: "", transcription: "", translation: "głuchy"),
  (phrase: "זַיִת", grammar: "", transcription: "", translation: "oliwka"),
  (phrase: "חָנוּת", grammar: "", transcription: "", translation: "sklep"),
)


#pagebreak(weak: true)

= 15

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "יָד", grammar: "", transcription: "", translation: "ręka"),
  (phrase: "אֶצְבַּע", grammar: "", transcription: "", translation: "palec"),
  (phrase: "מְעַט", grammar: "", transcription: "", translation: "trochę"),
  (phrase: "כִּמְעַט", grammar: "", transcription: "", translation: "prawie; niemal"),
  (phrase: "מְלָאכָה", grammar: "", transcription: "", translation: "praca; dzieło"),
  (phrase: "פֶּה", grammar: "", transcription: "", translation: "usta"),
  (phrase: "אַף", grammar: "", transcription: "", translation: "nos"),
  (phrase: "מֵרִיחַ", grammar: "", transcription: "", translation: "wącha; czuje"),
  (phrase: "לוֹבֵשׁ", grammar: "", transcription: "", translation: "ubiera"),
  (phrase: "מְדַבֵּר", grammar: "", transcription: "", translation: "mówi; rozmawia"),
  (phrase: "שִׂמְלָה", grammar: "", transcription: "", translation: "suknia"),
  (phrase: "סִנָּר", grammar: "", transcription: "", translation: "fartuch"),
  (phrase: "יֶלֶד", grammar: "", transcription: "", translation: "dziecko; chłopiec"),
  (phrase: "מִכְנָסַיִם", grammar: "", transcription: "", translation: "spodnie"),
  (phrase: "חָזִיָה", grammar: "", transcription: "", translation: "kamizelka"),
  (phrase: "מְעִיל", grammar: "", transcription: "", translation: "surdut"),
  (phrase: "כֶּלֶב", grammar: "", transcription: "", translation: "pies"),
  (phrase: "שׁוֹמֵר", grammar: "", transcription: "", translation: "strzeże"),
  (phrase: "יַלְדָה", grammar: "", transcription: "", translation: "dziewczynka"),
  (phrase: "זְמָן", grammar: "", transcription: "", translation: "czas"),
)


#pagebreak(weak: true)

= 16

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "זָקֵן", grammar: "", transcription: "", translation: "stary"),
  (phrase: "שָׂב", grammar: "", transcription: "", translation: "dziadek"),
  (phrase: "לָכֵן", grammar: "", transcription: "", translation: "dlatego"),
  (phrase: "שָׂם", grammar: "", transcription: "", translation: "kładzie"),
  (phrase: "סַכִּין", grammar: "", transcription: "", translation: "nóż"),
  (phrase: "חַד", grammar: "", transcription: "", translation: "ostry"),
  (phrase: "אוֹלָר", grammar: "", transcription: "", translation: "scyzoryk"),
  (phrase: "כַּאֲשֶׁר", grammar: "", transcription: "", translation: "gdy; skoro"),
  (phrase: "גַּנָּב", grammar: "", transcription: "", translation: "złodziej"),
  (phrase: "נוֹבֵחַ", grammar: "", transcription: "", translation: "szczeka"),
  (phrase: "בַּעַל־הַבַּיִת", grammar: "", transcription: "", translation: "gospodarz"),
  (phrase: "שׁוֹלֵחַ", grammar: "", transcription: "", translation: "posyła"),
  (phrase: "מְשָׁרֵת", grammar: "", transcription: "", translation: "służący"),
  (phrase: "מְגָרֵשׁ", grammar: "", transcription: "", translation: "wypędza; oddala"),
  (phrase: "בָּא", grammar: "", transcription: "", translation: "przychodzi; przyszedł"),
)


#pagebreak(weak: true)

= 17

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "יַלקוּט", grammar: "", transcription: "", translation: "torba"),
  (phrase: "לִפְנֵי", grammar: "", transcription: "", translation: "przed"),
  (phrase: "מֻנָּח", grammar: "", transcription: "", translation: "leży"),
  (phrase: "תָּלוּי", grammar: "", transcription: "", translation: "zawieszony; wisi"),
  (phrase: "דֶּגֶל", grammar: "", transcription: "", translation: "chorągiew; sztandar"),
  (phrase: "שָׁחוֹר", grammar: "", transcription: "", translation: "czarny"),
  (phrase: "מְשַׂחֵק", grammar: "", transcription: "", translation: "gra"),
  (phrase: "כַּדּוּר", grammar: "", transcription: "", translation: "piłka; kula"),
  (phrase: "עֲשָׁשִׁית", grammar: "", transcription: "", translation: "lampa"),
  (phrase: "אוֹר", grammar: "", transcription: "", translation: "światło"),
  (phrase: "נֵר", grammar: "", transcription: "", translation: "świeca"),
  (phrase: "בֵּן", grammar: "", transcription: "", translation: "syn"),
  (phrase: "עֶרֶב", grammar: "", transcription: "", translation: "wieczór"),
  (phrase: "שָׂבָה", grammar: "", transcription: "", translation: "babka"),
  (phrase: "עִבְרִי", grammar: "", transcription: "", translation: "hebrajski"),
  (phrase: "לְאָן?", grammar: "", transcription: "", translation: "dokąd?"),
  (phrase: "שָׁם", grammar: "", transcription: "", translation: "tam"),
  (phrase: "לְאוֹר", grammar: "", transcription: "", translation: "przy świetle"),
  (phrase: "בַּיִת", grammar: "", transcription: "", translation: "dom"),
)


#pagebreak(weak: true)

= 18

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "חָבֵר", grammar: "", transcription: "", translation: "kolega; towarzysz"),
  (phrase: "אֶתְמוֹל", grammar: "", transcription: "", translation: "wczoraj"),
  (phrase: "סַל", grammar: "", transcription: "", translation: "kosz"),
  (phrase: "נָשַׁק", grammar: "", transcription: "", translation: "całował"),
  (phrase: "מְנַגֵּן", grammar: "", transcription: "", translation: "gra"),
  (phrase: "פְּסַנְטְרִין", grammar: "", transcription: "", translation: "fortepian"),
  (phrase: "פְּסַנְתֵּר", grammar: "", transcription: "", translation: "fortepian"),
  (phrase: "כִּנּוֹר", grammar: "", transcription: "", translation: "skrzypce; harfa"),
  (phrase: "יוֹדֵעַ", grammar: "", transcription: "", translation: "wie; zna; umie"),
  (phrase: "לְנַגֵּן", grammar: "", transcription: "", translation: "grać"),
  (phrase: "לָשִׁיר", grammar: "", transcription: "", translation: "śpiewać"),
  (phrase: "מְנֻמָּס", grammar: "", transcription: "", translation: "grzeczny"),
  (phrase: "שׁוֹבָב", grammar: "", transcription: "", translation: "swawolny; niegrzeczny"),
  (phrase: "שַׁבָּת", grammar: "", transcription: "", translation: "sobota"),
)


#pagebreak(weak: true)

= 19

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "נָהָר", grammar: "", transcription: "", translation: "rzeka"),
  (phrase: "דָּג", grammar: "", transcription: "", translation: "ryba"),
  (phrase: "מֵאַיִן?", grammar: "", transcription: "", translation: "skąd?"),
  (phrase: "שׁוֹנֶה", grammar: "", transcription: "", translation: "różny"),
  (phrase: "יַיִן", grammar: "", transcription: "", translation: "wino"),
  (phrase: "שֵׁכָר", grammar: "", transcription: "", translation: "piwo"),
  (phrase: "חַיָּה", grammar: "", transcription: "", translation: "zwierzę"),
  (phrase: "מְבַשֵׁל", grammar: "", transcription: "", translation: "gotuje"),
  (phrase: "מִטְבָּח", grammar: "", transcription: "", translation: "kuchnia"),
  (phrase: "גֶּרְמַנִּי", grammar: "", transcription: "", translation: "niemiecki"),
  (phrase: "שָׂפָה", grammar: "", transcription: "", translation: "warga"),
  (phrase: "שָׂפָה", grammar: "", transcription: "", translation: "mowa"),
  (phrase: "הָר", grammar: "", transcription: "", translation: "góra"),
  (phrase: "חַיָּה־רָעָה", grammar: "", transcription: "", translation: "dzikie zwierzę"),
  (phrase: "אַרְיֵה", grammar: "", transcription: "", translation: "lew"),
  (phrase: "מֶלֶךְ", grammar: "", transcription: "", translation: "król"),
)


#pagebreak(weak: true)

= 20

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "פִּיל", grammar: "", transcription: "", translation: "słoń"),
  (phrase: "שׁוּעָל", grammar: "", transcription: "", translation: "lis"),
  (phrase: "דֹּב", grammar: "", transcription: "", translation: "niedźwiedź"),
  (phrase: "זְאֵב", grammar: "", transcription: "", translation: "wilk"),
  (phrase: "חָזָק", grammar: "", transcription: "", translation: "silny"),
  (phrase: "עֲרוּם", grammar: "", transcription: "", translation: "chytry"),
  (phrase: "דּוֹמֶה", grammar: "", transcription: "", translation: "podobny"),
  (phrase: "טוֹרֵף", grammar: "", transcription: "", translation: "pożera"),
  (phrase: "מִתְפַּלֵּל", grammar: "", transcription: "", translation: "modli się"),
  (phrase: "סִדּוּר", grammar: "", transcription: "", translation: "modlitewnik"),
  (phrase: "שָׁכֹב", grammar: "", transcription: "", translation: "leżeć; położyć się"),
  (phrase: "פּוֹלַנִּית", grammar: "", transcription: "", translation: "po polsku"),
  (phrase: "חֲבֵרָה", grammar: "", transcription: "", translation: "koleżanka"),
  (phrase: "אַחֵר", grammar: "", transcription: "", translation: "inny"),
  (phrase: "שָׁעוֹן", grammar: "", transcription: "", translation: "zegar"),
  (phrase: "חָתוּל", grammar: "", transcription: "", translation: "kot"),
  (phrase: "עַכְבָּר", grammar: "", transcription: "", translation: "mysz"),
  (phrase: "יָחֵף", grammar: "", transcription: "", translation: "bosy"),
  (phrase: "אֵיךְ?", grammar: "", transcription: "", translation: "jak?"),
  (phrase: "לִישׁוֹן", grammar: "", transcription: "", translation: "spać"),
  (phrase: "כָּאֹב", grammar: "", transcription: "", translation: "boleć; chorować"),
)


#pagebreak(weak: true)

= 21

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "אַדֶּרֶת", grammar: "", transcription: "", translation: "płaszcz"),
  (phrase: "אַדֶּרֶת־שֵׂעָר", grammar: "", transcription: "", translation: "futro"),
  (phrase: "מִגְבַּעַת", grammar: "", transcription: "", translation: "kapelusz"),
  (phrase: "לִלְמֹד", grammar: "", transcription: "", translation: "uczyć się"),
  (phrase: "חֹרֶף", grammar: "", transcription: "", translation: "zima"),
  (phrase: "קַיִץ", grammar: "", transcription: "", translation: "lato"),
  (phrase: "קַר", grammar: "", transcription: "", translation: "zimny"),
  (phrase: "קַר", grammar: "", transcription: "", translation: "zimno"),
  (phrase: "הַכֹּל", grammar: "", transcription: "", translation: "wszystko; wszyscy"),
  (phrase: "מֵאֵת", grammar: "", transcription: "", translation: "z; od"),
  (phrase: "הָיָה", grammar: "", transcription: "", translation: "był"),
  (phrase: "הָיוּ", grammar: "", transcription: "", translation: "byli; były"),
  (phrase: "סֻכָּה", grammar: "", transcription: "", translation: "chata"),
  (phrase: "צָהֳרַיִם", grammar: "", transcription: "", translation: "południe"),
  (phrase: "עָצֵל", grammar: "", transcription: "", translation: "leniwy"),
  (phrase: "בֵּיצָה", grammar: "", transcription: "", translation: "jajko"),
  (phrase: "מְטִילָה", grammar: "", transcription: "", translation: "znosi (jajka)"),
  (phrase: "תַּרְנְגֹלֶת", grammar: "", transcription: "", translation: "kura"),
  (phrase: "אָבוֹת", grammar: "", transcription: "", translation: "rodzice; przodkowie"),
  (phrase: "תֵּן!", grammar: "", transcription: "", translation: "daj!"),
  (phrase: "חָבִיב", grammar: "", transcription: "", translation: "miły; kochany"),
  (phrase: "חֲבִיבָה", grammar: "", transcription: "", translation: "miła; kochana"),
)


#pagebreak(weak: true)

= 22

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "בּוֹכֶה", grammar: "", transcription: "", translation: "płacze"),
  (phrase: "יָצְאָה", grammar: "", transcription: "", translation: "wyszła"),
  (phrase: "עֲדַיִן", grammar: "", transcription: "", translation: "jeszcze"),
  (phrase: "שָׁבָה", grammar: "", transcription: "", translation: "wróciła"),
  (phrase: "יָרֵא", grammar: "", transcription: "", translation: "boi się"),
  (phrase: "לָלֶכֶת", grammar: "", transcription: "", translation: "iść"),
  (phrase: "לְבַד", grammar: "", transcription: "", translation: "sam; tylko sam"),
  (phrase: "חוֹלֶה", grammar: "", transcription: "", translation: "chory"),
  (phrase: "רֵעַ", grammar: "", transcription: "", translation: "przyjaciel; bliźni"),
  (phrase: "עָלַי", grammar: "", transcription: "", translation: "na mnie"),
  (phrase: "זֶה...", grammar: "", transcription: "", translation: "od (czasu)"),
  (phrase: "רוֹפֵא", grammar: "", transcription: "", translation: "lekarz"),
  (phrase: "פַּעַם", grammar: "", transcription: "", translation: "raz"),
  (phrase: "מְרַפֵּה", grammar: "", transcription: "", translation: "leczy"),
  (phrase: "רוֹפֵא", grammar: "", transcription: "", translation: "leczy"),
  (phrase: "תְּרוּפָה", grammar: "", transcription: "", translation: "lek; lekarstwo"),
  (phrase: "אֶל", grammar: "", transcription: "", translation: "do"),
  (phrase: "שָׁבִים", grammar: "", transcription: "", translation: "wracają"),
  (phrase: "לָשֶׁבֶת", grammar: "", transcription: "", translation: "siedzieć"),
  (phrase: "כְּבָר", grammar: "", transcription: "", translation: "już"),
)


#pagebreak(weak: true)

= 23

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "חַלָּשׁ", grammar: "", transcription: "", translation: "słaby"),
  (phrase: "פָּנִים", grammar: "", transcription: "", translation: "twarz"),
  (phrase: "חִוָּר", grammar: "", transcription: "", translation: "blady"),
  (phrase: "כֻּלָּנוּ", grammar: "", transcription: "", translation: "my wszyscy"),
  (phrase: "מְבַקֵּר", grammar: "", transcription: "", translation: "odwiedza"),
  (phrase: "אֲדֹנָי", grammar: "", transcription: "", translation: "Bóg"),
  (phrase: "אֱלֹהִים", grammar: "", transcription: "", translation: "Bóg"),
  (phrase: "שֶׁיִּשְׁלַח", grammar: "", transcription: "", translation: "żeby posłał"),
  (phrase: "רְפוּאָה", grammar: "", transcription: "", translation: "wyzdrowienie; lekarstwo"),
  (phrase: "שָׁלֵם", grammar: "", transcription: "", translation: "cały; zupełny"),
  (phrase: "בִּמְחֵרָה", grammar: "", transcription: "", translation: "natychmiast; wkrótce"),
  (phrase: "שָׂמַח", grammar: "", transcription: "", translation: "cieszył się"),
  (phrase: "כָּבוֹד", grammar: "", transcription: "", translation: "zaszczyt; cześć"),
  (phrase: "בֹּקֶר", grammar: "", transcription: "", translation: "rano"),
  (phrase: "קֶסֶת", grammar: "", transcription: "", translation: "kałamarz"),
  (phrase: "דְּיוֹ", grammar: "", transcription: "", translation: "atrament"),
  (phrase: "דְּיוֹתָה", grammar: "", transcription: "", translation: "kałamarz"),
  (phrase: "מְחִיר", grammar: "", transcription: "", translation: "cena"),
)


#pagebreak(weak: true)

= 24

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "אֲרוּחָה", grammar: "", transcription: "", translation: "uczta"),
  (phrase: "אֲרֻחַת־הַבֹּקֶר", grammar: "", transcription: "", translation: "śniadanie"),
  (phrase: "אֲרֻחַת־הַצָּהֳרַיִם", grammar: "", transcription: "", translation: "obiad"),
  (phrase: "אֲרֻחַת־הָעֶרֶב", grammar: "", transcription: "", translation: "wieczerza"),
  (phrase: "פָּגשׁ", grammar: "", transcription: "", translation: "spotkać"),
  (phrase: "רְחוֹב", grammar: "", transcription: "", translation: "ulica"),
  (phrase: "שָׁבֹר", grammar: "", transcription: "", translation: "łamać; tłuc"),
  (phrase: "אָמֹר", grammar: "", transcription: "", translation: "mówić; powiedzieć"),
  (phrase: "כָּעֹס", grammar: "", transcription: "", translation: "gniewać się"),
  (phrase: "עָנשׁ", grammar: "", transcription: "", translation: "karać"),
  (phrase: "עֹנֶשׁ", grammar: "", transcription: "", translation: "kara"),
  (phrase: "קָשֶׁה", grammar: "", transcription: "", translation: "twardy; surowy"),
  (phrase: "שִׁלְשֹׁם", grammar: "", transcription: "", translation: "przedwczoraj"),
  (phrase: "הִבְטִיחַ", grammar: "", transcription: "", translation: "przyrzekł"),
  (phrase: "יָבֹא", grammar: "", transcription: "", translation: "on przyjdzie"),
  (phrase: "עַתָּה", grammar: "", transcription: "", translation: "teraz"),
  (phrase: "שֹׁרֶשׁ", grammar: "", transcription: "", translation: "korzeń"),
  (phrase: "לִכְבוֹד־", grammar: "", transcription: "", translation: "na cześć ..."),
  (phrase: "בְּעַצְמִי", grammar: "", transcription: "", translation: "ja sam"),
  (phrase: "שָׁאֹל", grammar: "", transcription: "", translation: "pytać"),
  (phrase: "אַחֲרֵי", grammar: "", transcription: "", translation: "po"),
  (phrase: "עַד", grammar: "", transcription: "", translation: "do; aż do"),
  (phrase: "עָדַי", grammar: "", transcription: "", translation: "do mnie; ku mnie"),
  (phrase: "שֵׁם־הַפֹּעַל", grammar: "", transcription: "", translation: "bezokolicznik"),
  (phrase: "גּוּף", grammar: "", transcription: "", translation: "ciało; osoba"),
)


#pagebreak(weak: true)

= 25

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "יָדִיד", grammar: "", transcription: "", translation: "przyjaciel"),
  (phrase: "תָּמִיד", grammar: "", transcription: "", translation: "zawsze"),
  (phrase: "יַחַד", grammar: "", transcription: "", translation: "razem"),
  (phrase: "אִתִּי", grammar: "", transcription: "", translation: "ze mną"),
  (phrase: "רוּסִית", grammar: "", transcription: "", translation: "po rosyjsku"),
  (phrase: "צָרְפָתִית", grammar: "", transcription: "", translation: "po francusku"),
  (phrase: "בַּת", grammar: "", transcription: "", translation: "córka"),
  (phrase: "אֲגוֹרָה", grammar: "", transcription: "", translation: "grosz"),
  (phrase: "עָנִי", grammar: "", transcription: "", translation: "biedny"),
  (phrase: "עִם", grammar: "", transcription: "", translation: "z"),
  (phrase: "עִמִּי", grammar: "", transcription: "", translation: "ze mną"),
  (phrase: "בִּקֵּשׁ", grammar: "", transcription: "", translation: "prosił"),
  (phrase: "נְדָבָה", grammar: "", transcription: "", translation: "jałmużna"),
  (phrase: "רָעֵב", grammar: "", transcription: "", translation: "głodny"),
  (phrase: "אֹכֶל", grammar: "", transcription: "", translation: "jadło; potrawa"),
  (phrase: "חֵן, חֵן!", grammar: "", transcription: "", translation: "dziękuję"),
  (phrase: "הַהוּא", grammar: "", transcription: "", translation: "ów"),
  (phrase: "מְבַקֵּשׁ", grammar: "", transcription: "", translation: "prosi"),
  (phrase: "עָבֶה", grammar: "", transcription: "", translation: "gruby; ciężki"),
)


#pagebreak(weak: true)

= 26

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "צָחֹק", grammar: "", transcription: "", translation: "śmiać się"),
  (phrase: "בִּשְׁעַת־", grammar: "", transcription: "", translation: "podczas"),
  (phrase: "רָץ", grammar: "", transcription: "", translation: "biegnie"),
  (phrase: "קָפֹץ", grammar: "", transcription: "", translation: "skakać"),
  (phrase: "רָקֹד", grammar: "", transcription: "", translation: "skakać; tańczyć"),
  (phrase: "אִלֵּם", grammar: "", transcription: "", translation: "niemy"),
  (phrase: "מַכָּר", grammar: "", transcription: "", translation: "znajomy"),
  (phrase: "אֻמְלָל", grammar: "", transcription: "", translation: "nieszczęśliwy"),
  (phrase: "לֶאֱכֹל", grammar: "", transcription: "", translation: "jeść"),
  (phrase: "מְכַבֵּד", grammar: "", transcription: "", translation: "szanuje"),
  (phrase: "צַר לִי", grammar: "", transcription: "", translation: "żal mi"),
  (phrase: "יָשָׁר", grammar: "", transcription: "", translation: "uczciwy"),
  (phrase: "נֶאֱמָן", grammar: "", transcription: "", translation: "wierny"),
  (phrase: "עֵת", grammar: "", transcription: "", translation: "czas"),
  (phrase: "הַהִיא", grammar: "", transcription: "", translation: "owa"),
  (phrase: "נָמֵר", grammar: "", transcription: "", translation: "tygrys"),
  (phrase: "טוֹרֵף", grammar: "", transcription: "", translation: "drapieżny"),
  (phrase: "חַיָּה טוֹרֶפֶת", grammar: "", transcription: "", translation: "zwierzę drapieżne"),
  (phrase: "בְּהֵמָה", grammar: "", transcription: "", translation: "bydło"),
  (phrase: "יָכֹל", grammar: "", transcription: "", translation: "móc"),
)


#pagebreak(weak: true)

= 27

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "הָאֵלֶּה", grammar: "", transcription: "", translation: "ci; te"),
  (phrase: "מַהֵר", grammar: "", transcription: "", translation: "szybko"),
  (phrase: "מַהֵר־מַהֵר", grammar: "", transcription: "", translation: "bardzo szybko"),
  (phrase: "צְבִי", grammar: "", transcription: "", translation: "jeleń"),
  (phrase: "מַכְתֵּבָה", grammar: "", transcription: "", translation: "biurko"),
  (phrase: "קַל", grammar: "", transcription: "", translation: "lekki"),
  (phrase: "צֵל", grammar: "", transcription: "", translation: "cień"),
  (phrase: "שָׂחֹה", grammar: "", transcription: "", translation: "pływać"),
  (phrase: "דָּבָר", grammar: "", transcription: "", translation: "rzecz; słowo"),
  (phrase: "מְקַבֵּל", grammar: "", transcription: "", translation: "dostaje; otrzymuje"),
  (phrase: "תְּעוּדָה", grammar: "", transcription: "", translation: "świadectwo"),
  (phrase: "מָסָךְ", grammar: "", transcription: "", translation: "firanka; zasłonka"),
  (phrase: "בַּרְזֶל", grammar: "", transcription: "", translation: "żelazo"),
  (phrase: "רַךְ", grammar: "", transcription: "", translation: "miękki"),
  (phrase: "קָטֹף", grammar: "", transcription: "", translation: "zrywać"),
  (phrase: "לִמּוּד", grammar: "", transcription: "", translation: "nauka"),
  (phrase: "כַּאֲשֶׁר", grammar: "", transcription: "", translation: "gdy"),
  (phrase: "עַל־כֵּן", grammar: "", transcription: "", translation: "przeto"),
  (phrase: "לָכֵן", grammar: "", transcription: "", translation: "dlatego"),
  (phrase: "פֶּן", grammar: "", transcription: "", translation: "inaczej; może"),
  (phrase: "אֲשֶׁר", grammar: "", transcription: "", translation: "że; który"),
  (phrase: "אוּלַי", grammar: "", transcription: "", translation: "może"),
  (phrase: "אָז", grammar: "", transcription: "", translation: "wtedy"),
  (phrase: "אֵיךְ", grammar: "", transcription: "", translation: "jak"),
  (phrase: "אִם", grammar: "", transcription: "", translation: "jeżeli"),
  (phrase: "יַעַן", grammar: "", transcription: "", translation: "ponieważ; bo"),
  (phrase: "הַיּוֹם", grammar: "", transcription: "", translation: "dziś"),
  (phrase: "מָחָר", grammar: "", transcription: "", translation: "jutro"),
  (phrase: "אֶתְמוֹל", grammar: "", transcription: "", translation: "wczoraj"),
  (phrase: "בָּעֶרֶב", grammar: "", transcription: "", translation: "wieczorem"),
  (phrase: "בַּבֹּקֶר", grammar: "", transcription: "", translation: "rano"),
  (phrase: "בַּצָּהֳרַיִם", grammar: "", transcription: "", translation: "w południe"),
)


#pagebreak(weak: true)

= 28

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "כְּסִיל", grammar: "", transcription: "", translation: "głupi"),
  (phrase: "שֵׁם", grammar: "", transcription: "", translation: "imię; nazwa"),
  (phrase: "עַל־פֶּה", grammar: "", transcription: "", translation: "na pamięć"),
  (phrase: "רָקִיעַ", grammar: "", transcription: "", translation: "sklepienie niebieskie"),
  (phrase: "בָּרֹא", grammar: "", transcription: "", translation: "stworzyć"),
  (phrase: "בָּרָא", grammar: "", transcription: "", translation: "stworzył"),
  (phrase: "יָם", grammar: "", transcription: "", translation: "morze"),
  (phrase: "יַבָּשָׁה", grammar: "", transcription: "", translation: "sucha ziemia; stały ląd"),
  (phrase: "צֶמַח", grammar: "", transcription: "", translation: "roślina"),
  (phrase: "שֶׁמֶשׁ", grammar: "", transcription: "", translation: "słońce"),
  (phrase: "יָרֵחַ", grammar: "", transcription: "", translation: "księżyc"),
  (phrase: "כּוֹכָב", grammar: "", transcription: "", translation: "gwiazda"),
  (phrase: "יוֹם־הַכִּפּוּרִים", grammar: "", transcription: "", translation: "Sądny Dzień"),
  (phrase: "מֵאִיר", grammar: "", transcription: "", translation: "świeci"),
  (phrase: "ה'", grammar: "", transcription: "", translation: "Bóg (skrócone)"),
  (phrase: "מְאוּמָה", grammar: "", transcription: "", translation: "coś"),
  (phrase: "כְּלוּם", grammar: "", transcription: "", translation: "coś"),
  (phrase: "לֹא־מְאוּמָה", grammar: "", transcription: "", translation: "nic"),
  (phrase: "לֹא־כְלוּם", grammar: "", transcription: "", translation: "nic"),
  (phrase: "חֹדֶשׁ", grammar: "", transcription: "", translation: "miesiąc"),
  (phrase: "אֲגֻדָּה", grammar: "", transcription: "", translation: "wiązka; bukiet"),
  (phrase: "חַג", grammar: "", transcription: "", translation: "święto; uroczystość"),
  (phrase: "רִאשׁוֹן", grammar: "", transcription: "", translation: "pierwszy"),
  (phrase: "שֵׁנִי", grammar: "", transcription: "", translation: "drugi"),
  (phrase: "שְׁנִיָּה", grammar: "", transcription: "", translation: "druga"),
  (phrase: "שְׁלִישִׁי", grammar: "", transcription: "", translation: "trzeci"),
  (phrase: "שְׁלִישִׁית", grammar: "", transcription: "", translation: "trzecia"),
)


#pagebreak(weak: true)

= 29

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "קוּם", grammar: "", transcription: "", translation: "wstać; wstawać"),
  (phrase: "רָחֹץ", grammar: "", transcription: "", translation: "myć"),
  (phrase: "סִפֵּר", grammar: "", transcription: "", translation: "opowiadał"),
  (phrase: "סָרֹק", grammar: "", transcription: "", translation: "czesać"),
  (phrase: "מַשְׂרֵק", grammar: "", transcription: "", translation: "grzebień"),
  (phrase: "שַׂעֲרָה", grammar: "", transcription: "", translation: "włos"),
  (phrase: "שִׂים", grammar: "", transcription: "", translation: "wkładać; kłaść"),
  (phrase: "שָׁלוֹם!", grammar: "", transcription: "", translation: "pokój; dzień dobry!"),
  (phrase: "רִיב", grammar: "", transcription: "", translation: "kłócić się"),
  (phrase: "רוּץ", grammar: "", transcription: "", translation: "biegać"),
  (phrase: "שׁוּב", grammar: "", transcription: "", translation: "wracać"),
  (phrase: "שׁוּק", grammar: "", transcription: "", translation: "targ; rynek"),
  (phrase: "שִׁיר", grammar: "", transcription: "", translation: "śpiewać"),
  (phrase: "דֶּרֶךְ", grammar: "", transcription: "", translation: "droga"),
  (phrase: "סוּר", grammar: "", transcription: "", translation: "wstąpić; wstępować"),
  (phrase: "יַעַן־כִּי", grammar: "", transcription: "", translation: "bo; gdyż"),
  (phrase: "עַל־אוֹדוֹת", grammar: "", transcription: "", translation: "o"),
  (phrase: "זֵכֶר", grammar: "", transcription: "", translation: "pamiątka"),
  (phrase: "אֲנַחְנוּ הוֹגְגִים", grammar: "", transcription: "", translation: "obchodzimy; świętujemy"),
  (phrase: "מִצְרַיִם", grammar: "", transcription: "", translation: "Egipt"),
  (phrase: "יְצִיאָה", grammar: "", transcription: "", translation: "wyjście"),
  (phrase: "בֵּית־הַכְּנֶסֶת", grammar: "", transcription: "", translation: "bożnica"),
  (phrase: "תְּפִלָּה", grammar: "", transcription: "", translation: "modlitwa"),
  (phrase: "מִתּוֹךְ", grammar: "", transcription: "", translation: "spośród"),
  (phrase: "חַג־הַפֶּסַח", grammar: "", transcription: "", translation: "święto Pesach"),
)


#pagebreak(weak: true)

= 30

#vocabulary(dir: rtl, script: "hebr",
  (phrase: "קָרֹא", grammar: "", transcription: "", translation: "czytać"),
  (phrase: "עִתּוֹן", grammar: "", transcription: "", translation: "gazeta"),
  (phrase: "רְשׁוּת", grammar: "", transcription: "", translation: "pozwolenie"),
  (phrase: "יְהוּדִי", grammar: "", transcription: "", translation: "Żyd"),
  (phrase: "לָשֶׁבֶת", grammar: "", transcription: "", translation: "mieszkać"),
  (phrase: "מָצֹא", grammar: "", transcription: "", translation: "znaleźć"),
  (phrase: "חֶבֶל", grammar: "", transcription: "", translation: "sznur"),
  (phrase: "דַּק", grammar: "", transcription: "", translation: "cienki"),
  (phrase: "נִקְרַע", grammar: "", transcription: "", translation: "podarł się"),
  (phrase: "מַלְבּוּשׁ", grammar: "", transcription: "", translation: "ubranie"),
  (phrase: "חָמֹל", grammar: "", transcription: "", translation: "litować się"),
  (phrase: "הוֹלִיכוּ", grammar: "", transcription: "", translation: "prowadzili"),
  (phrase: "תֵּבֵל", grammar: "", transcription: "", translation: "świat"),
  (phrase: "שָׁבֹת", grammar: "", transcription: "", translation: "odpoczywać"),
  (phrase: "כָּל־", grammar: "", transcription: "", translation: "wszelki; każdy"),
  (phrase: "נָפֹל", grammar: "", transcription: "", translation: "upaść"),
  (phrase: "הֶנְוָנִי", grammar: "", transcription: "", translation: "kramarz"),
  (phrase: "עָבֹר", grammar: "", transcription: "", translation: "przejść"),
  (phrase: "אֶרֶץ", grammar: "", transcription: "", translation: "ziemia; kraj"),
)


