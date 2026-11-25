import { EditorState } from '@codemirror/state';
import { EditorView, keymap, lineNumbers, highlightActiveLine, drawSelection } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { languages } from '@codemirror/language-data';
import { syntaxHighlighting, HighlightStyle, bracketMatching } from '@codemirror/language';
import { tags } from '@lezer/highlight';

const leporaHighlightStyle = HighlightStyle.define([
  { tag: tags.heading1, fontWeight: '700', fontSize: '1.35em', color: 'var(--heading-color)' },
  { tag: tags.heading2, fontWeight: '650', fontSize: '1.2em', color: 'var(--heading-color)' },
  { tag: tags.heading3, fontWeight: '600', fontSize: '1.1em', color: 'var(--heading-color)' },
  { tag: [tags.heading4, tags.heading5, tags.heading6], fontWeight: '600', color: 'var(--heading-color)' },
  { tag: tags.strong, fontWeight: '700' },
  { tag: tags.emphasis, fontStyle: 'italic' },
  { tag: tags.strikethrough, textDecoration: 'line-through', opacity: '0.65' },
  { tag: tags.link, color: 'var(--accent)', textDecoration: 'underline' },
  { tag: tags.url, color: 'var(--text-muted)' },
  { tag: tags.monospace, fontFamily: 'var(--font-mono)', color: 'var(--code-inline-fg)' },
  { tag: tags.quote, color: 'var(--text-muted)', fontStyle: 'italic' },
  { tag: tags.meta, color: 'var(--accent)', opacity: '0.75' },
  { tag: tags.processingInstruction, color: 'var(--accent)' },
  { tag: tags.keyword, color: 'var(--syntax-keyword)' },
  { tag: tags.string, color: 'var(--syntax-string)' },
  { tag: tags.comment, color: 'var(--syntax-comment)', fontStyle: 'italic' },
  { tag: tags.number, color: 'var(--syntax-number)' },
]);

const leporaSourceTheme = EditorView.theme({
  '&': {
    backgroundColor: 'transparent',
    color: 'var(--text-primary)',
    fontFamily: 'var(--font-mono)',
    fontSize: 'calc(var(--editor-font-size) * 0.92)',
    lineHeight: '1.75',
    height: '100%',
  },
  '.cm-scroller': {
    fontFamily: 'var(--font-mono)',
    padding: '72px max(32px, calc((100% - var(--editor-max-width)) / 2)) 42vh',
    overflow: 'auto',
  },
  '.cm-content': {
    caretColor: 'var(--accent)',
    padding: '0',
  },
  '.cm-line': {
    padding: '1px 0',
  },
  '.cm-gutters': {
    backgroundColor: 'transparent',
    borderRight: 'none',
    color: 'var(--text-faint)',
    paddingRight: '14px',
    userSelect: 'none',
  },
  '.cm-activeLine': {
    backgroundColor: 'var(--surface-hover)',
    borderRadius: '6px',
  },
  '.cm-activeLineGutter': {
    backgroundColor: 'transparent',
    color: 'var(--text-secondary)',
  },
  '&.cm-focused': {
    outline: 'none',
  },
  '.cm-selectionBackground, ::selection': {
    backgroundColor: 'var(--selection-bg) !important',
  },
});

export interface SourceEditorController {
  setValue: (markdownText: string) => void;
  getValue: () => string;
  focus: () => void;
  insertText: (text: string) => void;
  scrollToRatio: (ratio: number) => void;
  getScrollRatio: () => number;
  findNext: (query: string, backward?: boolean) => { count: number; current: number };
  replaceCurrent: (query: string, replacement: string) => void;
  replaceAll: (query: string, replacement: string) => void;
  destroy: () => void;
}

export function createSourceEditor(
  container: HTMLElement,
  initialValue: string,
  onChange: (value: string) => void
): SourceEditorController {
  let suppressChange = false;
  let lastSearchPos = 0;

  const state = EditorState.create({
    doc: initialValue,
    extensions: [
      lineNumbers(),
      highlightActiveLine(),
      drawSelection(),
      bracketMatching(),
      history(),
      EditorView.lineWrapping,
      markdown({ base: markdownLanguage, codeLanguages: languages }),
      syntaxHighlighting(leporaHighlightStyle),
      leporaSourceTheme,
      keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
      EditorView.updateListener.of((update) => {
        if (update.docChanged && !suppressChange) {
          onChange(update.state.doc.toString());
        }
      }),
    ],
  });

  const view = new EditorView({ state, parent: container });

  return {
    setValue(text: string) {
      const current = view.state.doc.toString();
      if (current === text) return;
      suppressChange = true;
      view.dispatch({
        changes: { from: 0, to: current.length, insert: text },
      });
      suppressChange = false;
    },
    getValue() {
      return view.state.doc.toString();
    },
    focus() {
      view.focus();
    },
    insertText(text: string) {
      const sel = view.state.selection.main;
      view.dispatch({
        changes: { from: sel.from, to: sel.to, insert: text },
        selection: { anchor: sel.from + text.length },
      });
      view.focus();
    },
    scrollToRatio(ratio: number) {
      const scroller = view.scrollDOM;
      const max = Math.max(0, scroller.scrollHeight - scroller.clientHeight);
      scroller.scrollTop = max * ratio;
    },
    getScrollRatio() {
      const scroller = view.scrollDOM;
      const max = Math.max(1, scroller.scrollHeight - scroller.clientHeight);
      return scroller.scrollTop / max;
    },
    findNext(query: string, backward = false) {
      if (!query) return { count: 0, current: 0 };
      const text = view.state.doc.toString();
      const lower = text.toLowerCase();
      const q = query.toLowerCase();
      const positions: number[] = [];
      let idx = lower.indexOf(q);
      while (idx !== -1) {
        positions.push(idx);
        idx = lower.indexOf(q, idx + Math.max(1, q.length));
      }
      if (positions.length === 0) return { count: 0, current: 0 };

      let targetIdx = 0;
      if (backward) {
        targetIdx = positions.length - 1;
        for (let i = positions.length - 1; i >= 0; i--) {
          if (positions[i] < lastSearchPos) {
            targetIdx = i;
            break;
          }
        }
      } else {
        targetIdx = 0;
        for (let i = 0; i < positions.length; i++) {
          if (positions[i] > lastSearchPos) {
            targetIdx = i;
            break;
          }
        }
      }

      const from = positions[targetIdx];
      lastSearchPos = from;
      view.dispatch({
        selection: { anchor: from, head: from + query.length },
        scrollIntoView: true,
      });
      return { count: positions.length, current: targetIdx + 1 };
    },
    replaceCurrent(query: string, replacement: string) {
      const sel = view.state.selection.main;
      const selected = view.state.doc.sliceString(sel.from, sel.to);
      if (selected.toLowerCase() === query.toLowerCase()) {
        view.dispatch({
          changes: { from: sel.from, to: sel.to, insert: replacement },
          selection: { anchor: sel.from + replacement.length },
        });
      }
    },
    replaceAll(query: string, replacement: string) {
      if (!query) return;
      const text = view.state.doc.toString();
      const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const next = text.replace(new RegExp(escaped, 'gi'), replacement);
      view.dispatch({
        changes: { from: 0, to: text.length, insert: next },
      });
    },
    destroy() {
      view.destroy();
    },
  };
}
