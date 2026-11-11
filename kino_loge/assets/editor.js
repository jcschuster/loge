import { collab, getSyncedVersion, receiveUpdates, sendableUpdates } from "@codemirror/collab";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { HighlightStyle, bracketMatching, syntaxHighlighting, syntaxTree } from "@codemirror/language";
import { lintGutter, setDiagnostics } from "@codemirror/lint";
import { highlightSelectionMatches, search, searchKeymap } from "@codemirror/search";
import { ChangeSet, Compartment, EditorState, RangeSetBuilder } from "@codemirror/state";
import {
  Decoration,
  EditorView,
  ViewPlugin,
  drawSelection,
  highlightActiveLine,
  keymap,
  lineNumbers,
} from "@codemirror/view";
import { tags as t } from "@lezer/highlight";
import { tptp } from "codemirror-lang-tptp";

const languages = { tptp };

// https://github.com/livebook-dev/livebook/blob/main/assets/js/hooks/cell_editor/live_editor/codemirror/theme.js
const colors = {
  text: "#c8ccd4",
  background: "#282c34",
  backgroundLighter: "#2f343e",
  backgroundLightest: "#454a56",
  border: "#363c46",
  cursor: "#73ade8",
  activeLine: "#2d323b",
  selection: "#394c5f",
  inactiveSelection: "#29333d",
  selectionMatch: "#343f4d",
  searchMatch: "#4c6582",
  searchMatchActive: "#54789e",
  lineNumber: "#60646c",
  lightRed: "#e06c75",
  blue: "#61afef",
  gray: "#8c92a3",
  green: "#98c379",
  purple: "#c678dd",
  teal: "#56b6c2",
  peach: "#d19a66",
  yellow: "#e5c07b",
};

const bracketColors = [colors.yellow, colors.purple, colors.blue];

const theme = EditorView.theme(
  {
    "&": {
      color: colors.text,
      backgroundColor: colors.background,
      fontSize: "14px",
      fontFamily: "JetBrains Mono, monospace",
    },
    "&.cm-focused": { outline: "none" },
    ".cm-scroller": { fontFamily: "inherit", padding: "0.75rem 0" },
    ".cm-content": { caretColor: colors.cursor, padding: "0" },
    ".cm-cursor": { borderLeftColor: colors.cursor },
    ".cm-activeLine": { backgroundColor: "transparent" },
    "&.cm-focused .cm-activeLine": { backgroundColor: colors.activeLine },
    ".cm-selectionBackground": { backgroundColor: colors.inactiveSelection },
    "&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground": {
      backgroundColor: colors.selection,
    },
    ".cm-gutters": { backgroundColor: colors.background, color: colors.lineNumber, border: "none" },
    ".cm-activeLineGutter": { backgroundColor: "transparent" },
    ".cm-tooltip": {
      backgroundColor: colors.backgroundLighter,
      color: colors.text,
      border: `1px solid ${colors.border}`,
    },
    ".cm-selectionMatch": { backgroundColor: colors.selectionMatch },
    ".cm-searchMatch": { backgroundColor: colors.searchMatch },
    ".cm-searchMatch.cm-searchMatch-selected": { backgroundColor: colors.searchMatchActive },
    ".cm-panels": { backgroundColor: colors.backgroundLighter, color: colors.text },
    ".cm-panels.cm-panels-top": { borderBottom: `1px solid ${colors.border}` },
    ".cm-panel.cm-search": { fontFamily: "Inter, sans-serif", padding: "6px 8px" },
    ".cm-panel.cm-search label": { fontSize: "12px" },
    ".cm-textfield": {
      color: colors.text,
      backgroundColor: colors.background,
      border: `1px solid ${colors.backgroundLightest}`,
      borderRadius: "4px",
    },
    ".cm-button": {
      color: colors.text,
      backgroundImage: "none",
      backgroundColor: colors.backgroundLightest,
      border: "none",
      borderRadius: "4px",
    },
    ...Object.fromEntries(bracketColors.map((color, depth) => [`.cm-bracket-${depth}`, { color }])),
  },
  { dark: true }
);

const highlighting = HighlightStyle.define([
  { tag: [t.keyword, t.modifier], color: colors.purple },
  { tag: [t.number, t.bool, t.atom, t.standard(t.variableName)], color: colors.blue },
  { tag: t.function(t.variableName), color: colors.blue },
  { tag: t.string, color: colors.green },
  { tag: t.variableName, color: colors.text },
  { tag: [t.special(t.variableName), t.labelName], color: colors.lightRed },
  { tag: t.typeName, color: colors.teal },
  { tag: [t.operator, t.logicOperator], color: colors.peach },
  { tag: t.comment, color: colors.gray },
]);

const grammar = (name) => languages[name]?.() ?? [];

const closing = { "(": ")", "[": "]", "{": "}" };
const opening = new Set(Object.keys(closing));
const closers = new Set(Object.values(closing));
const bracketMarks = bracketColors.map((_color, depth) => Decoration.mark({ class: `cm-bracket-${depth}` }));

const nestedBrackets = (state) => {
  const marks = new RangeSetBuilder();
  const open = [];
  syntaxTree(state).iterate({
    enter({ name, from, to }) {
      if (opening.has(name)) {
        marks.add(from, to, bracketMarks[open.length % bracketMarks.length]);
        open.push(closing[name]);
      } else if (closers.has(name) && open.at(-1) === name) {
        open.pop();
        marks.add(from, to, bracketMarks[open.length % bracketMarks.length]);
      }
    },
  });
  return marks.finish();
};

const rainbowBrackets = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = nestedBrackets(view.state);
    }

    update(update) {
      if (syntaxTree(update.startState) !== syntaxTree(update.state))
        this.decorations = nestedBrackets(update.state);
    }
  },
  { decorations: (plugin) => plugin.decorations }
);

const offset = (doc, line, column, fallback) => {
  if (line < 1 || line > doc.lines) return null;
  const { from, to, text } = doc.line(line);
  return column ? Math.min(from + column - 1, to) : fallback(from, text);
};

const diagnostic = (doc) => (d) => {
  const from = offset(doc, d.line, d.column, (start, text) => start + text.search(/\S|$/));
  const to = offset(doc, d.end_line ?? d.line, d.end_column, (start, text) => start + text.trimEnd().length);
  return from === null || to === null
    ? []
    : [{ from, to: Math.max(from, to), severity: d.severity, message: d.description, source: d.code }];
};

const scrolling = EditorView.theme({ "&": { maxHeight: "300px" }, ".cm-scroller": { overflow: "auto" } });

export function viewer(parent, text, language) {
  return new EditorView({
    parent,
    state: EditorState.create({
      doc: text,
      extensions: [
        EditorState.readOnly.of(true),
        lineNumbers(),
        drawSelection(),
        bracketMatching(),
        highlightSelectionMatches(),
        search({ top: true }),
        rainbowBrackets,
        keymap.of([...defaultKeymap, ...searchKeymap]),
        grammar(language),
        syntaxHighlighting(highlighting),
        theme,
        scrolling,
      ],
    }),
  });
}

export function editor(parent, { source, version, editor_language }, push) {
  const language = new Compartment();
  let pushing = false;
  let waiting = [];

  const settle = (state) => {
    if (sendableUpdates(state).length > 0) return;
    waiting.forEach((resolve) => resolve());
    waiting = [];
  };

  const flush = (state) => {
    const updates = sendableUpdates(state);
    if (pushing || updates.length === 0) return;
    pushing = true;
    push({
      version: getSyncedVersion(state),
      updates: updates.map((u) => ({ clientID: u.clientID, changes: u.changes.toJSON() })),
    });
  };

  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc: source,
      extensions: [
        lineNumbers(),
        history(),
        drawSelection(),
        bracketMatching(),
        highlightActiveLine(),
        highlightSelectionMatches(),
        search({ top: true }),
        lintGutter(),
        rainbowBrackets,
        keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap, indentWithTab]),
        collab({ startVersion: version }),
        language.of(grammar(editor_language)),
        syntaxHighlighting(highlighting),
        theme,
        EditorView.updateListener.of((update) => update.docChanged && flush(update.state)),
      ],
    }),
  });

  return {
    receive(updates) {
      pushing = false;
      view.dispatch(
        receiveUpdates(
          view.state,
          updates.map((u) => ({ clientID: u.clientID, changes: ChangeSet.fromJSON(u.changes) }))
        )
      );
      flush(view.state);
      settle(view.state);
    },
    synced() {
      return new Promise((resolve) => {
        waiting.push(resolve);
        settle(view.state);
      });
    },
    setLanguage(name) {
      view.dispatch({ effects: language.reconfigure(grammar(name)) });
    },
    setDiagnostics(diagnostics) {
      view.dispatch(setDiagnostics(view.state, diagnostics.flatMap(diagnostic(view.state.doc))));
    },
  };
}
