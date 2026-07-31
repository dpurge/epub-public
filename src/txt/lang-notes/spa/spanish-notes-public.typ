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
  title: "Język hiszpański (publiczne)",
  author: "D. Purge",
  description: "Notatki do nauki języka hiszpańskiego\n",
  lang: "es",
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

= All Spanish Method

Guillermo Hall

(1918)


#pagebreak(weak: true)

= LECCIÓN PRIMERA

== CONVERSACIÓN

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [El limón es una fruta\.

¿Qué es el limón?

]),
  (header: "—", content: [Es una fruta\.

]),
  (header: "—", content: [¿Es la rosa una fruta?

]),
  (header: "—", content: [No, señor; la rosa no es una fruta\.

]),
  (header: "—", content: [¿Qué es la rosa?

]),
  (header: "—", content: [La rosa es una flor\.

]),
  (header: "—", content: [¿Es la naranja una fruta?

]),
  (header: "—", content: [Sí, señor\.

]),
  (header: "—", content: [El limón es una fruta y la naranja es una fruta; el melón es úna fruta también\. El limón, la naranja, y el melón son frutas\.

¿Es la violeta una fruta?

]),
  (header: "—", content: [No, señor; no es una fruta\.

]),
  (header: "—", content: [¿Qué es la violeta?

]),
  (header: "—", content: [Es una flor\.

]),
  (header: "—", content: [¿Y la rosa?

]),
  (header: "—", content: [También\.

]),
  (header: "—", content: [¿Qué son la rosa y la violeta?

]),
  (header: "—", content: [Son flores\.

]),
  (header: "—", content: [Y la magnolia, ¿qué es?

]),
  (header: "—", content: [Es una flor también\.

]),
  (header: "—", content: [¿Es olorosa la magnolia?

]),
  (header: "—", content: [Sí, señor\.

]),
  (header: "—", content: [La magnolia es muy fragante, es de mucha fragancia\.

¿Son fragantes las rosas?

]),
  (header: "—", content: [Sí, señor; son muy fragantes\.

]),
  (header: "—", content: [El color de la magnolia es blanco\.

¿De qué color es la magnolia?

]),
  (header: "—", content: [La magnolia es blanca\.

]),
  (header: "—", content: [¿Es el limón también blanco?

]),
  (header: "—", content: [No, señor: el limón no es blanco, es amarillo\.

]),
  (header: "—", content: [Sí; el color del limón es amarillo\.

¿De qué color son las rosas?

]),
  (header: "—", content: [Las rosas son de varios colores\. Son blancas, y rojas, y amarillas\.

]),
  (header: "—", content: [El limón es ácido\.

¿Cómo es el vinagre?

]),
  (header: "—", content: [También es ácido, o agrio\.

]),
  (header: "—", content: [¿Es ácida la naranja?

]),
  (header: "—", content: [No, señor; la naranja no es ácida\.

]),
  (header: "—", content: [¿Cómo es la naranja?

]),
  (header: "—", content: [Es dulce\.

]),
  (header: "—", content: [Los limones son ácidos\. Las naranjas son dulces\.

¿Qué substancia es muy dulce y de mucho uso con el te y el café?

]),
  (header: "—", content: [El azúcar\.

]),
  (header: "—", content: [¿De qué color es el azúcar?

]),
  (header: "—", content: [Es blanco\.

]),
  (header: "—", content: [¿Es blanca la quinina?

]),
  (header: "—", content: [Sí, señor\.

]),
  (header: "—", content: [¿Es dulce?

]),
  (header: "—", content: [No, señor; la quinina no es dulce, es amarga\.

]),
  (header: "—", content: [¿Qué es la quinina?

]),
  (header: "—", content: [Es una medicina\.

]),
  (header: "—", content: [La quinina es un remedio muy común para curar las fiebres o calenturas\. El médico cura la fiebre amarilla con quinina y otras medicinas\. ¿Quién cura las fiebres y otras enfermedades?

]),
  (header: "—", content: [El médico o doctor\.

]),
)

#line(length: 100%)
== PREGUNTAS

#questions(dir: ltr, script: "latn", role: "source",
  (question: "¿Qué es el limón?", answer: ""),
  (question: "¿Es la violeta una fruta?", answer: ""),
  (question: "¿Qué es la magnolia?", answer: ""),
  (question: "¿Es el melón una fruta?", answer: ""),
  (question: "¿Qué son la rosa y la violeta?", answer: ""),
  (question: "¿Es olorosa la violeta?", answer: ""),
  (question: "¿Qué flor es muy fragante?", answer: ""),
  (question: "¿De qué color es la magnolia?", answer: ""),
  (question: "¿Es blanco también el limón?", answer: ""),
  (question: "¿Es dulce el vinagre?", answer: ""),
  (question: "¿Cómo es el vinagre?", answer: ""),
  (question: "¿Cómo son los limones?", answer: ""),
  (question: "¿Cómo son las naranjas?", answer: ""),
  (question: "¿Qué substancia se usa mucho con el te y el café?", answer: ""),
  (question: "¿De qué color es el azúcar?", answer: ""),
  (question: "¿Es amarilla la quinina?", answer: ""),
  (question: "¿Es agria la quinina?", answer: ""),
  (question: "¿Qué es la quinina?", answer: ""),
  (question: "¿Quién cura las fiebres?", answer: ""),
  (question: "¿Con qué remedio se curan las fiebres?", answer: ""),
)


#pagebreak(weak: true)

= LECCIÓN SEGUNDA

== CONVERSACIÓN

#textblock(role: "source", dir: ltr, script: "latn", [
La lámpara es un utensilio doméstico\. La lámpara se compone de varias partes\. Las partes esenciales de la lámpara son el tubo (bombilla en Méjico), el mechero (quemador), la mecha y el depósito\. La lámpara es de vidrio\. El mechero es de latón\. La mecha es de algodón\. El tubo es de vidrio\.

])

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [¿Qué es la lámpara?

]),
  (header: "—", content: [La lámpara es un utensilio doméstico\.

]),
  (header: "—", content: [¿Qué partes de la lámpara son esenciales?

]),
  (header: "—", content: [Las partes esenciales de la lámpara son el depósito, el tubo de vidrio y la mecha\.

]),
  (header: "—", content: [¿Qué partes de la lámpara son de vidrio?

]),
  (header: "—", content: [El depósito y el tubo son de vidrio\.

]),
  (header: "—", content: [¿Qué parte es metálica?

]),
  (header: "—", content: [El mechero es metálico\.

]),
  (header: "—", content: [¿De qué metal es el mechero?

]),
  (header: "—", content: [El mechero es de latón\.

]),
  (header: "—", content: [El latón es un metal útil en las artes\.

¿De qué material es la mecha?

]),
  (header: "—", content: [La mecha es de algodón\.

]),
  (header: "—", content: [¿Qué es algodón?

]),
  (header: "—", content: [El algodón es producto de una planta\.

]),
  (header: "—", content: [La lámpara contiene petróleo\. El petróleo es líquido; es de origen mineral, es producto mineral\.

¿Es el algodón de origen mineral?

]),
  (header: "—", content: [No, señor; el algodón es de origen vegetal\.

]),
  (header: "—", content: [¿Es líquido el vidrio?

]),
  (header: "—", content: [No, señor; no es líquido; en la condición natural el vidrio es sólido\.

]),
  (header: "—", content: [¿Es el vidrio de origen mineral?

]),
  (header: "—", content: [Sí, señor; el vidrio es de origen mineral\.

]),
)

#line(length: 100%)
== PREGUNTAS

#questions(dir: ltr, script: "latn", role: "source",
  (question: "¿Qué es la lámpara?", answer: ""),
  (question: "¿Qué partes de la lámpara son esenciales?", answer: ""),
  (question: "¿De qué material es el tubo?", answer: ""),
  (question: "¿Qué partes de la lámpara son de vidrio?", answer: ""),
  (question: "¿Qué parte de la lámpara es metálica?", answer: ""),
  (question: "¿Qué parte de la lámpara es de origen vegetal?", answer: ""),
  (question: "¿De qué metal es el mechero de la lámpara?", answer: ""),
  (question: "¿De qué material es la mecha?", answer: ""),
  (question: "¿Qué es el algodón?", answer: ""),
  (question: "¿Es el algodón de origen mineral?", answer: ""),
  (question: "¿Es el vidrio de origen mineral?", answer: ""),
  (question: "¿Qué es el petróleo?", answer: ""),
  (question: "¿Es el petróleo de origen vegetal?", answer: ""),
  (question: "¿Es sólido el petróleo?", answer: ""),
  (question: "¿Qué partes de la lámpara son de origen mineral?", answer: ""),
  (question: "¿Qué es el latón?", answer: ""),
  (question: "¿Es líquido el latón en el estado natural?", answer: ""),
  (question: "¿Es metálico el vidrio?", answer: ""),
  (question: "¿Es el vidrio un material natural o un producto fabricado?", answer: ""),
  (question: "¿De qué se fabrica la mecha?", answer: ""),
)


#pagebreak(weak: true)

= LECCIÓN TERCERA

== CONVERSACIÓN

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [La residencia de una familia es una casa\.

¿Qué es una casa?

]),
  (header: "—", content: [Una casa es la residencia de una familia\.

]),
  (header: "—", content: [¿Qué es la residencia de una familia?

]),
  (header: "—", content: [Una casa\.

]),
  (header: "—", content: [La Casa Blanca es la residencia del (de el) presidente de los Estados Unidos\.

¿Cuál es la residencia del presidente?

]),
  (header: "—", content: [La Casa Blanca\.

]),
  (header: "—", content: [¿De qué color es la casa?

]),
  (header: "—", content: [Es blanca\.

]),
  (header: "—", content: [¿De qué presidente es la casa?

]),
  (header: "—", content: [Es del presidente de los Estados Unidos\.

]),
  (header: "—", content: [¿Quién es el presidente de los Estados Unidos?

]),
  (header: "—", content: [El señor Wilson es el presidente actual\.

]),
  (header: "—", content: [¿De qué país o nación es presidente el Sr\. Wilson?

]),
  (header: "—", content: [De los Estados Unidos\.

]),
  (header: "—", content: [¿En qué viven Vds\. (ustedes)?

]),
  (header: "—", content: [Nosotros vivimos en casas\.

]),
  (header: "—", content: [¿Es Francia una república?

]),
  (header: "—", content: [Sí, señor\.

]),
  (header: "—", content: [¿Cuál es la capital de España?

]),
  (header: "—", content: [Madrid\.

]),
  (header: "—", content: [¿Quién es el rey de España?

]),
  (header: "—", content: [Alfonso\.

]),
  (header: "—", content: [¿De qué nación es Berlín la capital?

]),
  (header: "—", content: [De Alemania\.

]),
  (header: "—", content: [¿Es mejicano el Sr\. Wilson?

]),
  (header: "—", content: [No, señor; el Sr\. Wilson no es mejicano\.

]),
  (header: "—", content: [¿Qué es el Sr\. Wilson?

]),
  (header: "—", content: [Él es americano\.

]),
  (header: "—", content: [¿Qué es el Sr\. Díaz?

]),
  (header: "—", content: [Es mejicano\.

]),
  (header: "—", content: [El Sr\. Taft es americano y el Sr\. Roosevelt es americano\.

¿Qué son los señores Taft y Róosevelt?

]),
  (header: "—", content: [Son americanos\.

]),
  (header: "—", content: [¿Son Méjico y Guatemala países de Europa?

]),
  (header: "—", content: [No, señor; no son países de Europa, son de América\.

]),
  (header: "—", content: [¿Es Vd\. (usted) francés?

]),
  (header: "—", content: [No, señor; no soy francés\.

]),
  (header: "—", content: [¿De qué país es Vd\.?

]),
  (header: "—", content: [Soy de Inglaterra, soy inglés\.

]),
  (header: "—", content: [¿Qué es la señorita?

]),
  (header: "—", content: [Es española\.

]),
  (header: "—", content: [¿Son Vds\. americanos?

]),
  (header: "—", content: [No, señor; no somos americanos, somos europeos\.

]),
  (header: "—", content: [¿Cuántos son Vds\. en la clase?

]),
  (header: "—", content: [Somos cinco\.

]),
  (header: "—", content: [Uno, dos, tres, cuatro, cinco: sí; Vds\. son cinco\. La clase es de cinco discípulos\.

¿Cuántos son dos y tres?

]),
  (header: "—", content: [Dos y tres son cinco\.

]),
  (header: "—", content: [¿Cuántos son dos y cuatro?

]),
  (header: "—", content: [Dos y cuatro son seis\.

]),
  (header: "—", content: [María; cuente Vd\. de seis a diez\.

]),
  (header: "—", content: [Seis, siete, ocho, nueve, diez\.

]),
  (header: "—", content: [Pedro; cuente Vd\. de uno a diez\.

]),
  (header: "—", content: [Uno, dos, tres, cuatro, cinco, seis, siete, ocho, nueve, diez\.

]),
)

#line(length: 100%)
== PREGUNTAS

#questions(dir: ltr, script: "latn", role: "source",
  (question: "¿Qué es la residencia de una familia?", answer: ""),
  (question: "¿Quién vive en la Casa Blanca?", answer: ""),
  (question: "¿Qué es una casa?", answer: ""),
  (question: "¿Quién es el presidente de los Estados Unidos?", answer: ""),
  (question: "¿Quién es el rey de Inglaterra? (Jorge.)", answer: ""),
  (question: "¿Quién es la reina de Holanda? (Guillermina.)", answer: ""),
  (question: "¿De qué nación es París la capital?", answer: ""),
  (question: "¿De qué nación es Berlín la capital?", answer: ""),
  (question: "¿Cuáles son las repúblicas principales de América?", answer: ""),
  (question: "¿De qué color es la residencia oficial del presidente de los Estados Unidos?", answer: ""),
  (question: "¿De qué continente son los negros?", answer: ""),
  (question: "¿Vive Vd. en una casa blanca?", answer: ""),
  (question: "¿En qué viven Vds.?", answer: ""),
  (question: "¿Es Vd. alemán?", answer: ""),
  (question: "¿Qué soy yo?", answer: ""),
  (question: "¿Qué es Vd.?", answer: ""),
  (question: "¿En qué país viven los ingleses?", answer: ""),
  (question: "¿Son españoles los señores Édison y Wilson?", answer: ""),
  (question: "¿Somos discípulos de la clase de francés?", answer: ""),
  (question: "¿De qué país son los alemanes?", answer: ""),
)


#pagebreak(weak: true)

= LECCIÓN CUARTA

== CONVERSACIÓN

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [El níquel es un metal\. ¿Es el cinc un metal?

]),
  (header: "—", content: [Sí, señor; el cinc es un metal\.

]),
  (header: "—", content: [El níquel y el cinc son metales\. ¿De qué color es el níquel?

]),
  (header: "—", content: [Es blanco\.

]),
  (header: "—", content: [¿Es blanco el cinc?

]),
  (header: "—", content: [Sí, señor\.

]),
  (header: "—", content: [La plata es un metal de mucho valor\. ¿De qué color es la plata?

]),
  (header: "—", content: [Es blanca\.

]),
  (header: "—", content: [El níquel, el cinc y la plata son metales\. El oro es un metal también\. ¿Es blanco el oro?

]),
  (header: "—", content: [No, señor; el oro no es blanco\.

]),
  (header: "—", content: [¿De qué color es el oro?

]),
  (header: "—", content: [Es amarillo\.

]),
  (header: "—", content: [¿Es de mucho valor el oro?

]),
  (header: "—", content: [Sí, señor; es de mucho valor; es un metal precioso\.

]),
)

#textblock(role: "source", dir: ltr, script: "latn", [
El níquel, la plata y el oro son de mucho uso en el comercio\.

Las monedas mejicanas de oro son: la moneda de veinte pesos, la de diez pesos y la de cinco pesos\. De plata son el peso, el medio peso o tostón (cincuenta centavos o cuatro reales), la moneda de dos reales o una peseta (veinticinco centavos), el décimo (diez centavos) y el vigésimo (cinco centavos)\. También hay un vigésimo de níquel y una pieza de plata de veinte centavos\. El peso vale cincuenta centavos dinero americano\.

En España la unidad monetaria es la peseta de plata, equivalente a dieciocho centavos oro, poco más o menos\. El duro es de cinco pesetas\. También hay otras monedas: la pieza de dos pesetas de plata y el centén de veinticinco pesetas de oro\. Como suelto o dinero menudo tenemos de plata el décimo o media peseta y las monedas de cobre\. En Méjico la moneda fraccionaria o menuda es la feria\.

])

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [¿De qué metal son los centavos?

]),
  (header: "—", content: [Son de cobre\.

]),
)

#textblock(role: "source", dir: ltr, script: "latn", [
Las monedas españolas de cobre son de uno, dos, cinco y diez céntimos de peseta\. En Méjico los centavos son céntimos de peso\. Las monedas americanas son de oro, de plata, de níquel y de cobre\.

])

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [¿De qué metal son los billetes de banco?

]),
  (header: "—", content: [No son de metal; son de papel\.

]),
  (header: "—", content: [¿Cuáles son los valores de los billetes mejicanos?

]),
  (header: "—", content: [Son de cinco, de diez, de veinte, de cincuenta, de cien, de quinientos y de mil pesos\.

]),
)

#textblock(role: "source", dir: ltr, script: "latn", [
Las monedas son de metal, los billetes son de papel\. El dinero se compone de monedas y billetes\.

])

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [¿Prefiere Vd\. billetes o monedas?

]),
  (header: "—", content: [Prefiero los billetes, que son más cómodos o convenientes, pero las monedas son de mucho uso para pesos o duros y fracciones de peso\.

]),
  (header: "—", content: [¿Cuántos centavos hay en un décimo?

]),
  (header: "—", content: [En un décimo hay diez centavos\.

]),
  (header: "—", content: [¿Cuántos centavos hay en una peseta mejicana?

]),
  (header: "—", content: [Veinticinco\.

]),
  (header: "—", content: [Cuéntelos (cuente los centavos)\.

]),
  (header: "—", content: [Uno, dos, tres, cuatro, cinco, seis, siete, ocho, nueve, diez, once, doce, trece, catorce, quince, dieciséis, diecisiete, dieciocho, diecinueve, veinte, veintiuno, veintidós, veintitrés, veinticuatro, veinticinco\.

]),
  (header: "—", content: [¿Cuántos centavos hay en un tostón o cuatro reales mejicanos?

]),
  (header: "—", content: [Cincuenta\.

]),
  (header: "—", content: [¿Cuántos en un peso?

]),
  (header: "—", content: [Ciento\.

]),
  (header: "—", content: [Señorita Cárdenas, ¿es Vd\. americana?

]),
  (header: "—", content: [No, señor; yo soy española\.

]),
  (header: "—", content: [Señor Stein y señor Moore, ¿son Vds\. americanos?

]),
  (header: "—", content: [No, señor; somos europeos\.

]),
  (header: "—", content: [¿Son franceses los señores Stein y Moore?

]),
  (header: "—", content: [No, señor; uno es alemán y el otro es inglés\.

]),
  (header: "—", content: [¿Es cubana la señorita Villaverde?

]),
  (header: "—", content: [Sí, señor; es cubana\.

]),
  (header: "—", content: [¿De qué nación o país es el señor Moore?

]),
  (header: "—", content: [Es de Inglaterra; es inglés\.

]),
  (header: "—", content: [¿Y qué soy yo?

]),
  (header: "—", content: [Vd\. es cubano\.

]),
  (header: "—", content: [¿Qué dinero circula en Cuba?

]),
  (header: "—", content: [Cuba no tiene dinero propio; usa el de tres naciones: Francia, España y los Estados Unidos\.

]),
  (header: "—", content: [¿Tiene Vd\. monedas españolas?

]),
  (header: "—", content: [Sí, señor; tengo varias\.

]),
  (header: "—", content: [¿Cuánto dinero español tiene Vd\.?

]),
  (header: "—", content: [Tengo dos duros y una peseta\.

]),
)

#line(length: 100%)
== PREGUNTAS

#questions(dir: ltr, script: "latn", role: "source",
  (question: "¿Qué es el níquel?", answer: ""),
  (question: "¿Cuáles de los metales son blancos?", answer: ""),
  (question: "¿Cuántas pesetas hay en un duro español?", answer: ""),
  (question: "¿Qué metal es de mucho valor?", answer: ""),
  (question: "¿Es amarilla la plata?", answer: ""),
  (question: "¿Cuáles son las monedas de oro?", answer: ""),
  (question: "¿Cuáles son las monedas de plata?", answer: ""),
  (question: "¿Cuáles son las monedas de cobre?", answer: ""),
  (question: "Cuente Vd. de uno a veinte.", answer: ""),
  (question: "¿De qué material son los billetes de banco?", answer: ""),
  (question: "¿De qué valor son los diferentes billetes de banco?", answer: ""),
  (question: "¿Prefiere Vd. dinero en billetes o en monedas?", answer: ""),
  (question: "¿Hay bancos nacionales en los Estados Unidos?", answer: ""),
  (question: "¿Es Vd. francés?", answer: ""),
  (question: "¿Son Vds. europeos?", answer: ""),
  (question: "¿Qué es María?", answer: ""),
  (question: "¿Qué es Pedro?", answer: ""),
  (question: "¿Qué son Pedro y Juan?", answer: ""),
  (question: "¿De qué país es Vd.?", answer: ""),
  (question: "¿Son Vds. ingleses?", answer: ""),
)


#pagebreak(weak: true)

= LECCIÓN QUINTA

== CONVERSACIÓN

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [La naranja es una fruta redonda o esférica\. ¿De qué forma es el melón?

]),
  (header: "—", content: [Es oval u ovalado\.

]),
  (header: "—", content: [¿De qué forma es el limón?

]),
  (header: "—", content: [También es ovalado\.

]),
  (header: "—", content: [¿Es redondo el plátano o banana?

]),
  (header: "—", content: [No, señor; no es redondo\.

]),
  (header: "—", content: [El limón es fruto de árbol\. Un árbol es una planta muy grande\. ¿Es la naranja de un árbol?

]),
  (header: "—", content: [Sí, señor; la naranja también es fruto de árbol\.

]),
  (header: "—", content: [¿Es la rosa flor de un árbol?

]),
  (header: "—", content: [No, señor\.

]),
  (header: "—", content: [¿La violeta?

]),
  (header: "—", content: [Tampoco\.

]),
  (header: "—", content: [El árbol tiene tronco, ramas, hojas y raíces\. ¿Cuál es el tronco?

]),
  (header: "—", content: [Es la parte perpendicular\.

]),
  (header: "—", content: [¿Cuáles son las ramas?

]),
  (header: "—", content: [Son las partes laterales, o divisiones del tronco en la parte superior\.

]),
  (header: "—", content: [¿Cuáles son las hojas?

]),
  (header: "—", content: [Las ramas se dividen en ramos y los ramos terminan en hojas; los árboles tienen muchas hojas\.

]),
  (header: "—", content: [¿De qué color son las hojas?

]),
  (header: "—", content: [Son verdes\.

]),
  (header: "—", content: [¿Son permanentes las hojas?

]),
  (header: "—", content: [No, señor; no son permanentes\.

]),
  (header: "—", content: [¿Qué es la corteza?

]),
  (header: "—", content: [La corteza es la parte exterior del tronco y de las ramas, etc\.

]),
  (header: "—", content: [Las partes inferiores del árbol, que están en la tierra, son los raíces\. ¿Para qué sirven las raíces?

]),
  (header: "—", content: [Sirven para sostener el árbol\.

]),
  (header: "—", content: [¿Cuál es la parte más importante del árbol?

]),
  (header: "—", content: [La raíz\.

]),
)

#textblock(role: "source", dir: ltr, script: "latn", [
Las frutas tienen semillas\. La semilla sembrada en la tierra produce las raíces y las otras partes de la planta\.

])

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [¿Cuál tiene más semillas, el melón o la naranja?

]),
  (header: "—", content: [El melón tiene muchas más\.

]),
)

#textblock(role: "source", dir: ltr, script: "latn", [
En el interior o por dentro el melón es amarillo\. La sandía es una fruta parecida al melón\. Por dentro la sandía es generalmente de color rojo o colorado, con semillas negras o blancas\.

])

#dialog(dir: ltr, script: "latn", role: "source",
  (header: "—", content: [¿De qué color es la sandía por fuera?

]),
  (header: "—", content: [Verde\.

]),
  (header: "—", content: [¿Es agria la sandía?

]),
  (header: "—", content: [No, señor; es dulce\.

]),
  (header: "—", content: [¿Cuál es más grande, la naranja o la sandía?

]),
  (header: "—", content: [La sandía\.

]),
  (header: "—", content: [¿Cuál es más pequeña?

]),
  (header: "—", content: [La naranja\.

]),
  (header: "—", content: [¿De qué color es el melón por dentro?

]),
  (header: "—", content: [Amarillo salmón\.

]),
  (header: "—", content: [¿Cuál es más grande, el melón o la sandía?

]),
  (header: "—", content: [La sandía es más grande que el melón\.

]),
  (header: "—", content: [¿Cuál es más dulce, el limón o la naranja?

]),
  (header: "—", content: [La naranja es más dulce que el limón\.

]),
  (header: "—", content: [¿Cuánto vale una sandía?

]),
  (header: "—", content: [Vale generalmente de veinte a veinticinco centavos\.

]),
  (header: "—", content: [¿Cuánto vale la docena de limones?

]),
  (header: "—", content: [Actualmente la docena vale veinticinco centavos o dos reales\.

]),
  (header: "—", content: [¿Cuántos limones hay en una docena?

]),
  (header: "—", content: [Doce\.

]),
  (header: "—", content: [¿Cuántos limones hay en la media docena?

]),
  (header: "—", content: [Seis\.

]),
)

#line(length: 100%)
== PREGUNTAS

#questions(dir: ltr, script: "latn", role: "source",
  (question: "¿De qué forma es la sandía?", answer: ""),
  (question: "¿Cuál de las frutas es redonda?", answer: ""),
  (question: "¿Cuáles son las frutas de árbol?", answer: ""),
  (question: "¿Cuál es la fruta más ácida?", answer: ""),
  (question: "¿Cuántos plátanos hay en una docena?", answer: ""),
  (question: "Cuéntelos (los plátanos).", answer: ""),
  (question: "La docena de plátanos vale veinte centavos, ¿cuánto vale la media docena?", answer: ""),
  (question: "¿Qué es lo contrario de también?", answer: ""),
  (question: "¿Qué fruta es más grande que la naranja?", answer: ""),
  (question: "¿Cuál animal es más chico, la rata o el elefante?", answer: ""),
  (question: "¿Qué es un árbol?", answer: ""),
  (question: "¿Qué partes tiene un árbol?", answer: ""),
  (question: "¿Qué parte del árbol no es permanente?", answer: ""),
  (question: "¿Cuál es la parte que la planta tiene en la tierra?", answer: ""),
  (question: "¿En qué terminan los ramos?", answer: ""),
  (question: "¿Qué tienen las frutas por dentro?", answer: ""),
  (question: "¿Para qué sirven las semillas de las plantas?", answer: ""),
  (question: "¿Quién cultiva la tierra?", answer: ""),
  (question: "¿Cuál produce más, la tierra fértil o la tierra que no es fértil?", answer: ""),
  (question: "¿Cuál es más dulce, la piña o el limón?", answer: ""),
  (question: "Mencione Vd. una cosa verde, una blanca y una roja.", answer: ""),
)


