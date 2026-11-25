import { Editor } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import Table from '@tiptap/extension-table';
import TableRow from '@tiptap/extension-table-row';
import TaskList from '@tiptap/extension-task-list';
import TaskItem from '@tiptap/extension-task-item';
import Link from '@tiptap/extension-link';
import Highlight from '@tiptap/extension-highlight';
import Underline from '@tiptap/extension-underline';
import Subscript from '@tiptap/extension-subscript';
import Superscript from '@tiptap/extension-superscript';
import Placeholder from '@tiptap/extension-placeholder';
import Typography from '@tiptap/extension-typography';
import { markdownToDocJSON } from '../markdown/markdownParser';
import { docToMarkdown } from '../markdown/markdownSerializer';
import { renderLatex, preloadMathJaxIfNeeded } from '../math/mathRenderer';
import {
  InlineMath,
  DisplayMath,
  MermaidBlock,
  LeporaImage,
  CalloutBlock,
  LeporaCodeBlock,
  LeporaTableCell,
  LeporaTableHeader,
  createFocusTrackerPlugin,
  createSearchPlugin,
  searchPluginKey,
  setInlineMathEditorOpener,
} from './extensions';
import DOMPurify from 'dompurify';

export interface OutlineItem {
  id: string;
  level: number;
  text: string;
  pos: number;
}

export interface DocumentStats {
  words: number;
  characters: number;
  lines: number;
  readingMinutes: number;
  mathCount: number;
  diagramCount: number;
}

export interface WysiwygCallbacks {
  onMarkdownChange: (markdown: string) => void;
  onStatsChange: (stats: DocumentStats) => void;
  onOutlineChange: (outline: OutlineItem[]) => void;
  onActiveHeadingChange: (headingId: string) => void;
  onTypingActivity: () => void;
}

export class LeporaWysiwygEditor {
  public readonly editor: Editor;
  private readonly host: HTMLElement;
  private readonly callbacks: WysiwygCallbacks;
  private suppressUpdates = false;
  private typewriterMode = false;
  private focusMode = false;
  private typewriterRaf: number | null = null;
  private metaTimer: number | undefined;
  private activeInlineMathPos: number | null = null;
  private activeInlineMathDelim = '$';
  private activeInlineMathDisplayStyle = false;

  // Popover DOM references
  private readonly mathPopover: HTMLElement;
  private readonly mathPreview: HTMLElement;
  private readonly mathInput: HTMLInputElement;
  private readonly mathOpenSpan: HTMLElement;
  private readonly mathCloseSpan: HTMLElement;
  private readonly mathBadge: HTMLElement;
  private readonly tableToolbar: HTMLElement;

  constructor(host: HTMLElement, callbacks: WysiwygCallbacks) {
    this.host = host;
    this.callbacks = callbacks;

    this.mathPopover = document.getElementById('inline-math-popover')!;
    this.mathPreview = document.getElementById('inline-math-preview')!;
    this.mathInput = document.getElementById('inline-math-input') as HTMLInputElement;
    this.mathOpenSpan = document.getElementById('inline-math-open')!;
    this.mathCloseSpan = document.getElementById('inline-math-close')!;
    this.mathBadge = document.getElementById('inline-math-badge')!;
    this.tableToolbar = document.getElementById('table-toolbar')!;

    this.editor = new Editor({
      element: host,
      extensions: [
        StarterKit.configure({
          codeBlock: false,
          heading: { levels: [1, 2, 3, 4, 5, 6] },
        }),
        LeporaCodeBlock,
        Table.configure({
          resizable: false,
          allowTableNodeSelection: true,
        }),
        TableRow,
        LeporaTableCell,
        LeporaTableHeader,
        TaskList,
        TaskItem.configure({ nested: true }),
        Link.configure({
          openOnClick: false,
          autolink: true,
          HTMLAttributes: { rel: 'noopener noreferrer' },
        }),
        Highlight,
        Underline,
        Subscript,
        Superscript,
        Typography.configure({
          openDoubleQuote: false,
          closeDoubleQuote: false,
          openSingleQuote: false,
          closeSingleQuote: false,
        }),
        Placeholder.configure({
          placeholder: '开始写作…  输入 # 标题、$公式$、$$ 块级公式、```mermaid 图表',
        }),
        InlineMath,
        DisplayMath,
        MermaidBlock,
        LeporaImage,
        CalloutBlock,
      ],
      editorProps: {
        attributes: {
          class: 'lepora-prose',
          spellcheck: 'false',
        },
        handleClick: (_view, _pos, event) => {
          const anchor = (event.target as HTMLElement | null)?.closest('a');
          if (anchor && (event.metaKey || event.ctrlKey)) {
            const href = anchor.getAttribute('href');
            if (href) {
              event.preventDefault();
              window.webkit?.messageHandlers?.lepora?.postMessage({
                type: 'openExternalLink',
                href,
              });
              return true;
            }
          }
          return false;
        },
      },
      onUpdate: () => {
        if (this.suppressUpdates) return;
        this.callbacks.onTypingActivity();
        this.scheduleMetaAndMarkdownSync();
        if (this.typewriterMode) {
          this.scheduleTypewriterCenter();
        }
      },
      onSelectionUpdate: () => {
        this.updateTableToolbarPosition();
        if (this.typewriterMode) {
          this.scheduleTypewriterCenter();
        }
        this.updateActiveHeadingFromCursor();
      },
    });

    // Register Focus Mode & Search plugins cleanly
    this.editor.registerPlugin(createFocusTrackerPlugin());
    this.editor.registerPlugin(createSearchPlugin());

    this.setupInlineMathPopover();
    this.setupTableToolbar();

    // Scroll listener to track active outline heading smoothly
    this.host.addEventListener(
      'scroll',
      () => {
        this.updateTableToolbarPosition();
        this.updateActiveHeadingFromScroll();
      },
      { passive: true }
    );
  }

  private setupInlineMathPopover(): void {
    setInlineMathEditorOpener(({ pos, tex, delimiter, displayStyle, anchorEl }) => {
      this.activeInlineMathPos = pos;
      this.activeInlineMathDelim = delimiter;
      this.activeInlineMathDisplayStyle = displayStyle;

      if (delimiter === '\\(') {
        this.mathOpenSpan.textContent = '\\(';
        this.mathCloseSpan.textContent = '\\)';
      } else if (delimiter === '\\[') {
        this.mathOpenSpan.textContent = '\\[';
        this.mathCloseSpan.textContent = '\\]';
      } else if (delimiter === '$$') {
        this.mathOpenSpan.textContent = '$$';
        this.mathCloseSpan.textContent = '$$';
      } else {
        this.mathOpenSpan.textContent = '$';
        this.mathCloseSpan.textContent = '$';
      }

      this.mathInput.value = tex;
      this.updateInlineMathPreview(tex);

      const rect = anchorEl.getBoundingClientRect();
      this.mathPopover.hidden = false;
      const popRect = this.mathPopover.getBoundingClientRect();
      const left = Math.max(16, Math.min(window.innerWidth - popRect.width - 16, rect.left + rect.width / 2 - popRect.width / 2));
      const top = rect.bottom + 10 + popRect.height > window.innerHeight ? Math.max(16, rect.top - popRect.height - 10) : rect.bottom + 10;
      this.mathPopover.style.left = `${left}px`;
      this.mathPopover.style.top = `${top}px`;

      requestAnimationFrame(() => {
        this.mathInput.focus();
        this.mathInput.select();
      });
    });

    this.mathInput.addEventListener('input', () => {
      const tex = this.mathInput.value;
      this.updateInlineMathPreview(tex);
      if (this.activeInlineMathPos !== null) {
        const node = this.editor.state.doc.nodeAt(this.activeInlineMathPos);
        if (node && node.type.name === 'inlineMath') {
          this.editor.view.dispatch(
            this.editor.state.tr.setNodeMarkup(this.activeInlineMathPos, undefined, {
              ...node.attrs,
              tex,
            })
          );
        }
      }
    });

    this.mathInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === 'Escape') {
        e.preventDefault();
        this.closeInlineMathPopover();
        this.editor.view.focus();
      }
    });

    document.addEventListener('mousedown', (e) => {
      if (
        !this.mathPopover.hidden &&
        !this.mathPopover.contains(e.target as globalThis.Node) &&
        !(e.target as HTMLElement | null)?.closest('.lepora-inline-math')
      ) {
        this.closeInlineMathPopover();
      }
    });
  }

  private updateInlineMathPreview(tex: string): void {
    const res = renderLatex(tex, this.activeInlineMathDisplayStyle);
    this.mathPreview.innerHTML = DOMPurify.sanitize(res.html, {
      USE_PROFILES: { html: true, svg: true, svgFilters: true, mathMl: true },
      ADD_TAGS: ['mjx-container', 'mjx-assistive-mml'],
    });
    this.mathBadge.textContent = res.engine === 'mathjax' ? 'MathJax' : res.engine === 'error' ? '错误' : 'KaTeX';
    this.mathBadge.dataset.engine = res.engine;
  }

  private closeInlineMathPopover(): void {
    this.mathPopover.hidden = true;
    this.activeInlineMathPos = null;
  }

  private setupTableToolbar(): void {
    this.tableToolbar.addEventListener('mousedown', (e) => {
      e.preventDefault();
    });

    this.tableToolbar.addEventListener('click', (e) => {
      const btn = (e.target as HTMLElement | null)?.closest('button[data-action]') as HTMLButtonElement | null;
      if (!btn) return;
      const action = btn.dataset.action;
      const chain = this.editor.chain().focus();
      switch (action) {
        case 'addRowBefore':
          chain.addRowBefore().run();
          break;
        case 'addRowAfter':
          chain.addRowAfter().run();
          break;
        case 'deleteRow':
          chain.deleteRow().run();
          break;
        case 'addColBefore':
          chain.addColumnBefore().run();
          break;
        case 'addColAfter':
          chain.addColumnAfter().run();
          break;
        case 'deleteCol':
          chain.deleteColumn().run();
          break;
        case 'alignLeft':
          chain.setCellAttribute('textAlign', 'left').run();
          break;
        case 'alignCenter':
          chain.setCellAttribute('textAlign', 'center').run();
          break;
        case 'alignRight':
          chain.setCellAttribute('textAlign', 'right').run();
          break;
        case 'deleteTable':
          chain.deleteTable().run();
          this.tableToolbar.hidden = true;
          break;
      }
      this.updateTableToolbarPosition();
    });
  }

  private updateTableToolbarPosition(): void {
    if (!this.editor.isActive('table')) {
      this.tableToolbar.hidden = true;
      return;
    }

    const { $from } = this.editor.state.selection;
    let tableDom: HTMLElement | null = null;
    for (let d = $from.depth; d > 0; d--) {
      if ($from.node(d).type.name === 'table') {
        const pos = $from.before(d);
        const dom = this.editor.view.nodeDOM(pos);
        if (dom instanceof HTMLElement) {
          tableDom = dom;
        }
        break;
      }
    }

    if (!tableDom) {
      this.tableToolbar.hidden = true;
      return;
    }

    const rect = tableDom.getBoundingClientRect();
    if (rect.bottom < 0 || rect.top > window.innerHeight) {
      this.tableToolbar.hidden = true;
      return;
    }

    this.tableToolbar.hidden = false;
    const barRect = this.tableToolbar.getBoundingClientRect();
    const left = Math.max(16, Math.min(window.innerWidth - barRect.width - 16, rect.left + rect.width / 2 - barRect.width / 2));
    const top = Math.max(54, rect.top - barRect.height - 8);
    this.tableToolbar.style.left = `${left}px`;
    this.tableToolbar.style.top = `${top}px`;
  }

  public setMarkdown(markdown: string): void {
    preloadMathJaxIfNeeded(markdown);
    this.suppressUpdates = true;
    const json = markdownToDocJSON(markdown);
    this.editor.commands.setContent(json, false);
    this.suppressUpdates = false;
    this.emitOutlineAndStats();
  }

  public getMarkdown(): string {
    return docToMarkdown(this.editor.state.doc);
  }

  public setFocusMode(enabled: boolean): void {
    this.focusMode = enabled;
    document.body.classList.toggle('focus-mode', enabled);
  }

  public setTypewriterMode(enabled: boolean): void {
    this.typewriterMode = enabled;
    document.body.classList.toggle('typewriter-mode', enabled);
    if (enabled) {
      this.scheduleTypewriterCenter();
    }
  }

  private scheduleTypewriterCenter(): void {
    if (this.typewriterRaf !== null) {
      cancelAnimationFrame(this.typewriterRaf);
    }
    this.typewriterRaf = requestAnimationFrame(() => {
      this.typewriterRaf = null;
      const { from } = this.editor.state.selection;
      try {
        const coords = this.editor.view.coordsAtPos(from);
        const hostRect = this.host.getBoundingClientRect();
        const targetY = hostRect.top + hostRect.height * 0.44;
        const delta = coords.top - targetY;
        if (Math.abs(delta) > 8) {
          this.host.scrollBy({ top: delta, behavior: 'smooth' });
        }
      } catch {
        // ignore invalid coords during rapid mutations
      }
    });
  }

  private scheduleMetaAndMarkdownSync(): void {
    window.clearTimeout(this.metaTimer);
    this.metaTimer = window.setTimeout(() => {
      const md = this.getMarkdown();
      this.callbacks.onMarkdownChange(md);
      this.emitOutlineAndStats();
    }, 90);
  }

  public emitOutlineAndStats(): void {
    const doc = this.editor.state.doc;
    const outline: OutlineItem[] = [];
    let mathCount = 0;
    let diagramCount = 0;
    let textPieces: string[] = [];
    let headingCounter = 0;

    doc.descendants((node, pos) => {
      if (node.type.name === 'heading') {
        const level = Number(node.attrs.level) || 1;
        const text = node.textContent.trim();
        if (text) {
          outline.push({
            id: `h-${++headingCounter}`,
            level,
            text,
            pos,
          });
        }
      } else if (node.type.name === 'inlineMath' || node.type.name === 'displayMath') {
        mathCount++;
      } else if (node.type.name === 'mermaidBlock') {
        diagramCount++;
      } else if (node.isText && node.text) {
        textPieces.push(node.text);
      } else if (node.isBlock) {
        textPieces.push('\n');
      }
    });

    const fullText = textPieces.join('');
    const cjkChars = (fullText.match(/[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]/g) ?? []).length;
    const latinWords = (
      fullText
        .replace(/[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]/g, ' ')
        .match(/[A-Za-z0-9_'-]+/g) ?? []
    ).length;
    const words = cjkChars + latinWords;
    const characters = fullText.replace(/\s+/g, '').length;
    const lines = Math.max(1, doc.childCount);
    const readingMinutes = Math.max(1, Math.ceil(words / 260));

    this.callbacks.onOutlineChange(outline);
    this.callbacks.onStatsChange({
      words,
      characters,
      lines,
      readingMinutes,
      mathCount,
      diagramCount,
    });
  }

  private updateActiveHeadingFromCursor(): void {
    const cursorPos = this.editor.state.selection.from;
    let activeId = '';
    let idx = 0;
    this.editor.state.doc.descendants((node, pos) => {
      if (node.type.name === 'heading' && node.textContent.trim()) {
        idx++;
        if (pos <= cursorPos) {
          activeId = `h-${idx}`;
        }
      }
    });
    if (activeId) {
      this.callbacks.onActiveHeadingChange(activeId);
    }
  }

  private updateActiveHeadingFromScroll(): void {
    const headings = this.host.querySelectorAll('h1, h2, h3, h4, h5, h6');
    let activeIdx = 0;
    headings.forEach((el, i) => {
      const rect = el.getBoundingClientRect();
      if (rect.top <= 120) {
        activeIdx = i + 1;
      }
    });
    if (activeIdx > 0) {
      this.callbacks.onActiveHeadingChange(`h-${activeIdx}`);
    }
  }

  public scrollToPos(pos: number): void {
    try {
      const clamped = Math.max(0, Math.min(this.editor.state.doc.content.size, pos + 1));
      this.editor.commands.setTextSelection(clamped);
      const domAt = this.editor.view.domAtPos(clamped);
      const el =
        domAt.node instanceof HTMLElement ? domAt.node : domAt.node.parentElement;
      el?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      this.editor.view.focus();
    } catch {
      // ignore out-of-range
    }
  }

  public insertImage(src: string, alt = ''): void {
    this.editor
      .chain()
      .focus()
      .insertContent({
        type: 'leporaImage',
        attrs: { src, alt, title: '', width: null },
      })
      .run();
  }

  public insertDisplayMath(tex = '', delimiter = '$$'): void {
    this.editor
      .chain()
      .focus()
      .insertContent({
        type: 'displayMath',
        attrs: { tex, delimiter },
      })
      .run();
  }

  public insertInlineMath(tex = 'E = mc^2', delimiter = '$'): void {
    this.editor
      .chain()
      .focus()
      .insertContent({
        type: 'inlineMath',
        attrs: { tex, delimiter, displayStyle: false },
      })
      .run();
  }

  public insertMermaid(code?: string): void {
    this.editor
      .chain()
      .focus()
      .insertContent({
        type: 'mermaidBlock',
        attrs: {
          code:
            code ??
            `flowchart LR\n  A[思路] --> B[Markdown]\n  B --> C[精美排版]`,
        },
      })
      .run();
  }

  public insertTable(rows = 3, cols = 3): void {
    this.editor.chain().focus().insertTable({ rows, cols, withHeaderRow: true }).run();
  }

  public insertCallout(calloutType = 'note'): void {
    this.editor
      .chain()
      .focus()
      .insertContent({
        type: 'callout',
        attrs: { calloutType },
        content: [{ type: 'paragraph', content: [{ type: 'text', text: '提示内容…' }] }],
      })
      .run();
  }

  public executeFormatCommand(cmd: string, arg?: string): void {
    const chain = this.editor.chain().focus();
    switch (cmd) {
      case 'h1':
        chain.toggleHeading({ level: 1 }).run();
        break;
      case 'h2':
        chain.toggleHeading({ level: 2 }).run();
        break;
      case 'h3':
        chain.toggleHeading({ level: 3 }).run();
        break;
      case 'h4':
        chain.toggleHeading({ level: 4 }).run();
        break;
      case 'paragraph':
        chain.setParagraph().run();
        break;
      case 'bold':
        chain.toggleBold().run();
        break;
      case 'italic':
        chain.toggleItalic().run();
        break;
      case 'strike':
        chain.toggleStrike().run();
        break;
      case 'underline':
        chain.toggleUnderline().run();
        break;
      case 'highlight':
        chain.toggleHighlight().run();
        break;
      case 'inlineCode':
        chain.toggleCode().run();
        break;
      case 'codeBlock':
        chain.toggleCodeBlock({ language: arg ?? '' }).run();
        break;
      case 'blockquote':
        chain.toggleBlockquote().run();
        break;
      case 'bulletList':
        chain.toggleBulletList().run();
        break;
      case 'orderedList':
        chain.toggleOrderedList().run();
        break;
      case 'taskList':
        chain.toggleTaskList().run();
        break;
      case 'hr':
        chain.setHorizontalRule().run();
        break;
      case 'inlineMath':
        this.insertInlineMath();
        break;
      case 'displayMath':
        this.insertDisplayMath();
        break;
      case 'mermaid':
        this.insertMermaid();
        break;
      case 'table':
        this.insertTable(3, 3);
        break;
      case 'callout':
        this.insertCallout(arg ?? 'note');
        break;
      case 'link': {
        const href = arg || 'https://';
        chain.extendMarkRange('link').setLink({ href }).run();
        break;
      }
      case 'undo':
        chain.undo().run();
        break;
      case 'redo':
        chain.redo().run();
        break;
    }
  }

  public search(query: string, caseSensitive = false, direction: 'current' | 'next' | 'prev' = 'current'): { count: number; current: number } {
    const prev = searchPluginKey.getState(this.editor.state);
    let nextIdx = 0;
    if (prev && prev.query === query && prev.matches.length > 0) {
      if (direction === 'next') nextIdx = prev.activeIndex + 1;
      else if (direction === 'prev') nextIdx = prev.activeIndex - 1;
      else nextIdx = prev.activeIndex >= 0 ? prev.activeIndex : 0;
    }

    this.editor.view.dispatch(
      this.editor.state.tr.setMeta(searchPluginKey, {
        query,
        caseSensitive,
        activeIndex: nextIdx,
      })
    );

    const updated = searchPluginKey.getState(this.editor.state);
    if (!updated || updated.matches.length === 0) {
      return { count: 0, current: 0 };
    }

    const match = updated.matches[updated.activeIndex];
    if (match) {
      const domAt = this.editor.view.domAtPos(match.from);
      const el = domAt.node instanceof HTMLElement ? domAt.node : domAt.node.parentElement;
      el?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }

    return { count: updated.matches.length, current: updated.activeIndex + 1 };
  }

  public replaceCurrent(replacement: string): { count: number; current: number } {
    const state = searchPluginKey.getState(this.editor.state);
    if (!state || state.activeIndex < 0 || !state.matches[state.activeIndex]) {
      return { count: 0, current: 0 };
    }
    const { from, to } = state.matches[state.activeIndex];
    this.editor.view.dispatch(this.editor.state.tr.insertText(replacement, from, to));
    return this.search(state.query, state.caseSensitive, 'current');
  }

  public replaceAll(replacement: string): { count: number; current: number } {
    const state = searchPluginKey.getState(this.editor.state);
    if (!state || state.matches.length === 0) {
      return { count: 0, current: 0 };
    }
    let tr = this.editor.state.tr;
    // Replace from back to front to keep positions valid
    for (let i = state.matches.length - 1; i >= 0; i--) {
      const m = state.matches[i];
      tr = tr.insertText(replacement, m.from, m.to);
    }
    this.editor.view.dispatch(tr);
    return this.search(state.query, state.caseSensitive, 'current');
  }

  public clearSearch(): void {
    this.editor.view.dispatch(
      this.editor.state.tr.setMeta(searchPluginKey, { query: '', activeIndex: -1 })
    );
  }

  public refreshAllMathAndDiagrams(): void {
    // Trigger clean re-render of math & mermaid blocks after engine/theme change
    const md = this.getMarkdown();
    const sel = this.editor.state.selection.from;
    this.setMarkdown(md);
    try {
      const safePos = Math.min(sel, this.editor.state.doc.content.size);
      this.editor.commands.setTextSelection(safePos);
    } catch {
      // ignore
    }
  }

  public getScrollRatio(): number {
    const max = Math.max(1, this.host.scrollHeight - this.host.clientHeight);
    return this.host.scrollTop / max;
  }

  public scrollToRatio(ratio: number): void {
    const max = Math.max(0, this.host.scrollHeight - this.host.clientHeight);
    this.host.scrollTop = max * ratio;
  }

  /**
   * Produces a clean, export-ready HTML snapshot of the rendered prose
   * (with KaTeX HTML, MathJax SVGs, Mermaid SVGs, and syntax-highlighted code blocks intact).
   */
  public getExportHTMLSnapshot(): string {
    const prose = this.host.querySelector('.lepora-prose');
    if (!prose) return '';
    const clone = prose.cloneNode(true) as HTMLElement;
    // Strip interactive-only UI chrome
    clone.querySelectorAll(
      '.block-editor-drawer, .mermaid-hover-edit, .image-hover-bar, .image-resize-handle, .code-block-toolbar'
    ).forEach((el) => el.remove());
    clone.querySelectorAll('[contenteditable]').forEach((el) => el.removeAttribute('contenteditable'));
    return clone.innerHTML;
  }
}
