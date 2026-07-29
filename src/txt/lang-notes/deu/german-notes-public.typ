// book.typ — DPurge language-book Typst template: the vocabulary/dialog/
// parallel blocks emitted by the markdown Typst renderer (pkg/tool/markdown)
// plus the `book` show-rule entry point. Self-contained (no imports) so it can
// be go:embed-ed and compiled standalone.

// Base multi-script stack: Typst resolves each glyph against the first family
// that covers it, so one list spans Latin plus every script. All installed in
// the project's Docker image.
#let _baseFont = (
  "Gentium", "Charis SIL", "Noto Serif",
  "Amiri", "Scheherazade", "Noto Naskh Arabic", "Noto Sans Arabic",
  "Ezra SIL", "Frank Ruehl CLM", "Noto Serif Hebrew", "Noto Sans Hebrew",
  // Arphic .ttc collections index under the base name "AR PL UMing" (not the
  // fontconfig "AR PL UMing CN"); the base face is Simplified/CN.
  "AR PL UMing", "AR PL UKai",
  "Baekmuk Batang",
  "Noto Sans",
)

// Per-role vocabulary fonts, set by `book` and read by `vocabulary`. State is
// used because `vocabulary` is a top-level function (bound by the body's
// `#vocabulary(...)` calls), so it cannot see `book`'s parameters directly.
#let _vocabFonts = state("vocab-fonts", (
  header: _baseFont, transcription: _baseFont, translation: _baseFont,
))

// #vocabulary((phrase, grammar, transcription, translation), ..)
// phrase (+ optional gray grammar tag + optional bracketed transcription), then
// translation. grammar uses the Header font, transcription the Transcription
// font, translation the Translation font — matching the EPUB vocabulary.css
// roles. `context` wraps only the styled spans (not the block) so a long list
// still page-breaks between rows. `grid` (not `table`) avoids the document-wide
// `set table` shading the first item as a header row.
#let vocabulary(..items) = block(width: 100%, grid(
  columns: (auto, 1fr),
  column-gutter: 1em,
  stroke: (y: 0.5pt + luma(220)),
  align: (left + top, left + top),
  inset: (x: 2pt, y: 4pt),
  ..items.pos().map(it => (
    {
      strong(it.at("phrase", default: ""))
      if it.at("grammar", default: "") != "" {
        [ ]; context text(font: _vocabFonts.get().header, size: 0.85em, fill: gray)[#it.at("grammar")]
      }
      if it.at("transcription", default: "") != "" {
        [ ]; context text(font: _vocabFonts.get().transcription)[#emph[\[#it.at("transcription")\]]]
      }
    },
    context text(font: _vocabFonts.get().translation)[#it.at("translation", default: "")],
  )).flatten()
))

// #dialog((header, content), ..) — one grid so speaker labels stay aligned.
#let dialog(..turns) = block(width: 100%, grid(
  columns: (auto, 1fr), column-gutter: 0.8em, row-gutter: 0.5em,
  ..turns.pos().map(t => (strong(t.at("header", default: "")), t.at("content", default: []))).flatten()
))

// #parallel((main, secondary), ..) — two columns with a faint centre rule.
#let parallel(..rows) = block(width: 100%, grid(
  columns: (1fr, 1fr), column-gutter: 1.2em, row-gutter: 0.5em,
  stroke: (x: 0.5pt + luma(230)),
  ..rows.pos().map(r => (r.at("main", default: []), r.at("secondary", default: []))).flatten()
))

// #show: book.with(title, author, description, lang, dir, cover, ...)
// paper/size/margin/font are the configurable knobs (overridable via the `Pdf`
// config section, pkg/ebook); size-large is used for scripts the exporter marks
// large-script (CJK/Arabic/Hebrew/Korean/Japanese). font-body/-header/
// -transcription/-translation are per-role prefixes (parsed from the project
// font.css by the exporter) prepended to `font`.
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
  // Binding-aware A5 margins (wider inner edge); page.binding follows dir, so
  // this is correct for double-sided and RTL. Accepts a length or per-side dict.
  margin: (inside: 1.8cm, outside: 1.4cm, top: 1.7cm, bottom: 2cm),
  font: _baseFont,
  font-body: (),
  font-header: (),
  font-transcription: (),
  font-translation: (),
  body,
) = {
  let headerFont = font-header + font
  _vocabFonts.update((
    header: headerFont,
    transcription: font-transcription + font,
    translation: font-translation + font,
  ))

  // document(author:) requires str/array, never none; exporter passes "" absent.
  set document(title: title, author: if author == none or author == "" { () } else { author })
  set text(
    lang: lang,
    dir: dir,
    size: if large-script { size-large } else { size },
    font: font-body + font,
    hyphenate: true,
  )
  set page(paper: paper, margin: margin, numbering: "1")
  // First-line indent marks paragraphs; `all: false` leaves the first paragraph
  // after a heading un-indented.
  set par(justify: true, leading: 0.7em, spacing: 0.7em, first-line-indent: (amount: 1.2em, all: false))
  show heading: set par(justify: false, first-line-indent: 0pt)
  set terms(separator: [: ], tight: true, hanging-indent: 1em)
  // Booktabs-style tables: horizontal rules only.
  set table(
    stroke: (x: none, y: 0.7pt + luma(180)),
    inset: (x: 8pt, y: 5pt),
    align: (_, y) => if y == 0 { center } else { left },
    fill: (_, y) => if y == 0 { luma(235) } else { none },
  )
  show heading: set block(above: 1.5em, below: 0.75em)
  show heading: set text(font: headerFont)
  // Heading scale tuned for A5.
  show heading.where(level: 1): set text(size: 1.7em)
  show heading.where(level: 2): set text(size: 1.4em)
  show heading.where(level: 3): set text(size: 1.2em)
  show heading.where(level: 4): set text(size: 1.1em)
  show heading.where(level: 5): set text(size: 1.05em)
  show heading.where(level: 6): set text(size: 1em)
  show quote.where(block: true): it => block(inset: (left: 1em, y: 0.3em), stroke: (left: 2pt + luma(180)))[#emph(it.body)]

  // Front matter: unnumbered title page, roman contents, then arabic body from
  // 1 (so the reader-facing "page 1" is the first chapter).
  set page(numbering: none)
  align(center + horizon, {
    // cover may be a path string (exporter contract) or pre-built content.
    if cover != none {
      if type(cover) == str { image(cover, width: 55%) } else { cover }
      v(1.2em)
    }
    text(size: 2.4em, weight: "bold", title)
    if author != none and author != "" { v(1.2em); text(size: 1.3em, author) }
    if description != none and description != "" { v(1.6em); text(style: "italic", fill: luma(90%), description) }
  })
  pagebreak()

  set page(numbering: "i")
  counter(page).update(1)
  show outline.entry.where(level: 1): strong
  outline(title: [Contents], indent: auto)
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
  paper: "a5",
  size: 12pt,
  size-large: 16pt,
  margin: (top: 1cm, bottom: 1cm, left: 1cm, right: 1cm, rest: 1.5cm),
  font: ("Gentium", "Charis SIL", "Noto Serif", "Amiri", "Scheherazade", "Noto Naskh Arabic", "Noto Sans Arabic", "Ezra SIL", "Frank Ruehl CLM", "Noto Serif Hebrew", "Noto Sans Hebrew", "AR PL UMing", "AR PL UKai", "Baekmuk Batang", "Noto Sans"),
  font-body: ("Times New Roman", "Gentium"),
  font-header: ("Helvetica", "Noto Sans"),
  font-transcription: ("Helvetica", "DejaVu Sans"),
  font-translation: ("Times New Roman", "Gentium"),
)

= Najlepsza metoda języka niemieckiego

Plato v\. Reussner

(1892)


#pagebreak(weak: true)

= Erste Lektion

#dialog(
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
#dialog(
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

#dialog(
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
#dialog(
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

#dialog(
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
#dialog(
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


