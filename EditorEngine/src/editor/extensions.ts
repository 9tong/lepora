import { Node, InputRule, mergeAttributes } from '@tiptap/core';
import { Plugin, PluginKey, TextSelection } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';
import CodeBlockLowlight from '@tiptap/extension-code-block-lowlight';
import TableCell from '@tiptap/extension-table-cell';
import TableHeader from '@tiptap/extension-table-header';
import { common, createLowlight } from 'lowlight';
import { renderLatex, onMathJaxReady } from '../math/mathRenderer';
import { renderMermaid } from '../mermaid/mermaidRenderer';
import DOMPurify from 'dompurify';

export const lowlight = createLowlight(common);

// Global image URL resolver callback (injected by main controller)
let imageUrlResolver: (rawSrc: string) => string = (s) => s;
let revealImageHandler: (rawSrc: string) => void = () => {};
let inlineMathEditorOpener:
  | ((opts: {
      pos: number;
      tex: string;
      delimiter: string;
      displayStyle: boolean;
      anchorEl: HTMLElement;
    }) => void)
  | null = null;

export function setImageUrlResolver(fn: (rawSrc: string) => string): void {
  imageUrlResolver = fn;
}

export function setRevealImageHandler(fn: (rawSrc: string) => void): void {
  revealImageHandler = fn;
}

export function setInlineMathEditorOpener(
  fn: (opts: {
    pos: number;
    tex: string;
    delimiter: string;
    displayStyle: boolean;
    anchorEl: HTMLElement;
  }) => void
): void {
  inlineMathEditorOpener = fn;
}

function autoResizeTextarea(ta: HTMLTextAreaElement): void {
  ta.style.height = 'auto';
  ta.style.height = `${Math.max(44, ta.scrollHeight)}px`;
}

function safeRenderMathInto(target: HTMLElement, html: string): void {
  const clean = DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true, svg: true, svgFilters: true, mathMl: true },
    ADD_TAGS: ['mjx-container', 'mjx-assistive-mml'],
    ADD_ATTR: ['jax', 'display', 'focusable', 'role', 'aria-hidden', 'style', 'viewBox', 'xmlns', 'data-mml-node'],
  });
  target.innerHTML = clean;
}

/**
 * Inline Math Node: $...$, \(...\), and inline $$...$$
 */
export const InlineMath = Node.create({
  name: 'inlineMath',
  group: 'inline',
  inline: true,
  atom: true,
  selectable: true,

  addAttributes() {
    return {
      tex: { default: '' },
      delimiter: { default: '$' },
      displayStyle: { default: false },
    };
  },

  parseHTML() {
    return [{ tag: 'span[data-type="inline-math"]' }];
  },

  renderHTML({ HTMLAttributes }) {
    return ['span', mergeAttributes(HTMLAttributes, { 'data-type': 'inline-math', class: 'lepora-inline-math' })];
  },

  addInputRules() {
    return [
      // $...$
      new InputRule({
        find: /(?:^|[^$\\])\$([^\s$][^$]*?[^\s$]|[^\s$])\$$/,
        handler: ({ state, range, match }) => {
          const tex = match[1];
          const full = match[0];
          const prefixLen = full.startsWith('$') ? 0 : 1;
          const start = range.from + prefixLen;
          const end = range.to;
          const node = this.type.create({ tex, delimiter: '$', displayStyle: false });
          state.tr.replaceWith(start, end, node);
        },
      }),
      // \(...\)
      new InputRule({
        find: /\\\((.+?)\\\)$/,
        handler: ({ state, range, match }) => {
          const tex = match[1].trim();
          if (!tex) return;
          const node = this.type.create({ tex, delimiter: '\\(', displayStyle: false });
          state.tr.replaceWith(range.from, range.to, node);
        },
      }),
    ];
  },

  addNodeView() {
    return ({ node, getPos }) => {
      let currentNode = node;
      const dom = document.createElement('span');
      dom.className = 'lepora-inline-math';
      dom.setAttribute('data-type', 'inline-math');
      dom.contentEditable = 'false';

      const render = () => {
        const tex = String(currentNode.attrs.tex ?? '');
        const displayStyle = Boolean(currentNode.attrs.displayStyle);
        const result = renderLatex(tex, displayStyle);
        safeRenderMathInto(dom, result.html);
        dom.dataset.engine = result.engine;
        dom.title = `点击编辑公式: ${tex}`;
      };

      render();
      const unsub = onMathJaxReady(render);

      const handleClick = (e: MouseEvent) => {
        e.preventDefault();
        e.stopPropagation();
        const pos = typeof getPos === 'function' ? getPos() : undefined;
        if (typeof pos === 'number' && inlineMathEditorOpener) {
          inlineMathEditorOpener({
            pos,
            tex: String(currentNode.attrs.tex ?? ''),
            delimiter: String(currentNode.attrs.delimiter ?? '$'),
            displayStyle: Boolean(currentNode.attrs.displayStyle),
            anchorEl: dom,
          });
        }
      };

      dom.addEventListener('click', handleClick);

      return {
        dom,
        update(updatedNode) {
          if (updatedNode.type.name !== 'inlineMath') return false;
          currentNode = updatedNode;
          render();
          return true;
        },
        destroy() {
          unsub();
          dom.removeEventListener('click', handleClick);
        },
      };
    };
  },
});

/**
 * Display Math Block Node: $$...$$, \[...\], \begin{equation/align/...}, ```math
 */
export const DisplayMath = Node.create({
  name: 'displayMath',
  group: 'block',
  atom: true,
  selectable: true,
  defining: true,

  addAttributes() {
    return {
      tex: { default: '' },
      delimiter: { default: '$$' },
    };
  },

  parseHTML() {
    return [{ tag: 'div[data-type="display-math"]' }];
  },

  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { 'data-type': 'display-math', class: 'lepora-display-math' })];
  },

  addInputRules() {
    return [
      new InputRule({
        find: /^\$\$\s?$/,
        handler: ({ state, range }) => {
          const node = this.type.create({ tex: '', delimiter: '$$' });
          state.tr.replaceWith(range.from - 1, range.to, node);
        },
      }),
      new InputRule({
        find: /^\\\[\s?$/,
        handler: ({ state, range }) => {
          const node = this.type.create({ tex: '', delimiter: '\\[' });
          state.tr.replaceWith(range.from - 1, range.to, node);
        },
      }),
      new InputRule({
        find: /^```math\s$/,
        handler: ({ state, range }) => {
          const node = this.type.create({ tex: '', delimiter: 'fence' });
          state.tr.replaceWith(range.from - 1, range.to, node);
        },
      }),
    ];
  },

  addNodeView() {
    return ({ node, editor, getPos }) => {
      let currentNode = node;
      let isEditing = String(node.attrs.tex ?? '').trim() === '';

      const wrapper = document.createElement('div');
      wrapper.className = 'lepora-display-math';
      wrapper.setAttribute('data-type', 'display-math');
      wrapper.contentEditable = 'false';

      // Editor drawer (Typora-style top source box + live preview below)
      const sourceBox = document.createElement('div');
      sourceBox.className = 'block-editor-drawer';

      const header = document.createElement('div');
      header.className = 'block-editor-header';

      const titleGroup = document.createElement('div');
      titleGroup.className = 'block-editor-title-group';

      const label = document.createElement('span');
      label.className = 'block-editor-label';
      label.textContent = 'LaTeX 公式';

      const delimSelect = document.createElement('select');
      delimSelect.className = 'block-editor-select';
      delimSelect.title = '定界符语法';
      const delims: Array<[string, string]> = [
        ['$$', '$$ … $$'],
        ['\\[', '\\[ … \\]'],
        ['env', '\\begin{…}'],
        ['fence', '```math'],
      ];
      for (const [val, text] of delims) {
        const opt = document.createElement('option');
        opt.value = val;
        opt.textContent = text;
        delimSelect.appendChild(opt);
      }

      const engineBadge = document.createElement('span');
      engineBadge.className = 'math-engine-badge';

      titleGroup.append(label, delimSelect, engineBadge);

      const actionGroup = document.createElement('div');
      actionGroup.className = 'block-editor-actions';

      const copyBtn = document.createElement('button');
      copyBtn.type = 'button';
      copyBtn.className = 'block-editor-btn';
      copyBtn.textContent = '复制 TeX';

      const doneBtn = document.createElement('button');
      doneBtn.type = 'button';
      doneBtn.className = 'block-editor-btn primary';
      doneBtn.textContent = '完成 ⌘↩';

      actionGroup.append(copyBtn, doneBtn);
      header.append(titleGroup, actionGroup);

      const textarea = document.createElement('textarea');
      textarea.className = 'block-editor-textarea';
      textarea.spellcheck = false;
      textarea.placeholder = '\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}';

      sourceBox.append(header, textarea);

      const preview = document.createElement('div');
      preview.className = 'display-math-preview';

      wrapper.append(sourceBox, preview);

      const commitAttrs = (tex: string, delimiter: string) => {
        const pos = typeof getPos === 'function' ? getPos() : undefined;
        if (typeof pos !== 'number') return;
        const tr = editor.view.state.tr.setNodeMarkup(pos, undefined, {
          ...currentNode.attrs,
          tex,
          delimiter,
        });
        editor.view.dispatch(tr);
      };

      const renderPreview = (tex: string) => {
        const res = renderLatex(tex, true);
        safeRenderMathInto(preview, res.html);
        engineBadge.textContent = res.engine === 'mathjax' ? 'MathJax' : res.engine === 'error' ? '语法错误' : 'KaTeX';
        engineBadge.dataset.engine = res.engine;
      };

      const syncEditingUI = () => {
        wrapper.classList.toggle('is-editing', isEditing);
        sourceBox.hidden = !isEditing;
        if (isEditing) {
          textarea.value = String(currentNode.attrs.tex ?? '');
          delimSelect.value = String(currentNode.attrs.delimiter ?? '$$');
          requestAnimationFrame(() => {
            autoResizeTextarea(textarea);
            textarea.focus();
          });
        }
      };

      const exitEditing = (moveAfter = false) => {
        if (!isEditing) return;
        isEditing = false;
        syncEditingUI();
        if (moveAfter) {
          const pos = typeof getPos === 'function' ? getPos() : undefined;
          if (typeof pos === 'number') {
            const after = pos + currentNode.nodeSize;
            const tr = editor.view.state.tr;
            if (after <= tr.doc.content.size) {
              tr.setSelection(TextSelection.near(tr.doc.resolve(after)));
              editor.view.dispatch(tr);
              editor.view.focus();
            }
          }
        }
      };

      renderPreview(String(currentNode.attrs.tex ?? ''));
      syncEditingUI();

      const unsubMathJax = onMathJaxReady(() => {
        renderPreview(isEditing ? textarea.value : String(currentNode.attrs.tex ?? ''));
      });

      const onPreviewClick = (e: MouseEvent) => {
        e.stopPropagation();
        if (!isEditing) {
          isEditing = true;
          syncEditingUI();
        }
      };

      const onInput = () => {
        autoResizeTextarea(textarea);
        renderPreview(textarea.value);
        commitAttrs(textarea.value, delimSelect.value);
      };

      const onDelimChange = () => {
        commitAttrs(textarea.value, delimSelect.value);
      };

      const onKeyDown = (e: KeyboardEvent) => {
        e.stopPropagation();
        if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
          e.preventDefault();
          exitEditing(true);
        } else if (e.key === 'Escape') {
          e.preventDefault();
          exitEditing(false);
          editor.view.focus();
        } else if (e.key === 'Tab') {
          e.preventDefault();
          const start = textarea.selectionStart;
          const end = textarea.selectionEnd;
          textarea.setRangeText('  ', start, end, 'end');
          onInput();
        }
      };

      const onCopyClick = (e: MouseEvent) => {
        e.stopPropagation();
        void navigator.clipboard?.writeText(textarea.value);
        copyBtn.textContent = '已复制';
        setTimeout(() => {
          copyBtn.textContent = '复制 TeX';
        }, 1200);
      };

      const onDoneClick = (e: MouseEvent) => {
        e.stopPropagation();
        exitEditing(true);
      };

      const onDocMouseDown = (e: MouseEvent) => {
        if (isEditing && !wrapper.contains(e.target as globalThis.Node)) {
          exitEditing(false);
        }
      };

      preview.addEventListener('click', onPreviewClick);
      textarea.addEventListener('input', onInput);
      textarea.addEventListener('keydown', onKeyDown);
      delimSelect.addEventListener('change', onDelimChange);
      copyBtn.addEventListener('click', onCopyClick);
      doneBtn.addEventListener('click', onDoneClick);
      document.addEventListener('mousedown', onDocMouseDown);

      return {
        dom: wrapper,
        stopEvent: (event) => {
          return isEditing && sourceBox.contains(event.target as globalThis.Node);
        },
        ignoreMutation: () => true,
        update(updatedNode) {
          if (updatedNode.type.name !== 'displayMath') return false;
          currentNode = updatedNode;
          const newTex = String(updatedNode.attrs.tex ?? '');
          const newDelim = String(updatedNode.attrs.delimiter ?? '$$');
          if (!isEditing) {
            renderPreview(newTex);
          } else {
            if (textarea.value !== newTex) {
              textarea.value = newTex;
              autoResizeTextarea(textarea);
            }
            delimSelect.value = newDelim;
            renderPreview(newTex);
          }
          return true;
        },
        destroy() {
          unsubMathJax();
          preview.removeEventListener('click', onPreviewClick);
          textarea.removeEventListener('input', onInput);
          textarea.removeEventListener('keydown', onKeyDown);
          delimSelect.removeEventListener('change', onDelimChange);
          copyBtn.removeEventListener('click', onCopyClick);
          doneBtn.removeEventListener('click', onDoneClick);
          document.removeEventListener('mousedown', onDocMouseDown);
        },
      };
    };
  },
});

const MERMAID_TEMPLATES: Record<string, string> = {
  flowchart: `flowchart LR\n  A[开始] --> B{条件判断}\n  B -->|是| C[执行任务]\n  B -->|否| D[结束]`,
  sequence: `sequenceDiagram\n  participant U as 用户\n  participant A as Lepora\n  U->>A: 输入 Markdown\n  A-->>U: 实时渲染视图`,
  mindmap: `mindmap\n  root((Lepora))\n    极简界面\n      Liquid Glass\n      专注模式\n    专业排版\n      KaTeX & MathJax\n      Mermaid 图表`,
  state: `stateDiagram-v2\n  [*] --> 草稿\n  草稿 --> 编辑中\n  编辑中 --> 已保存\n  已保存 --> [*]`,
};

/**
 * Mermaid Diagram Block Node: ```mermaid
 */
export const MermaidBlock = Node.create({
  name: 'mermaidBlock',
  group: 'block',
  atom: true,
  selectable: true,
  defining: true,

  addAttributes() {
    return {
      code: { default: MERMAID_TEMPLATES.flowchart },
    };
  },

  parseHTML() {
    return [{ tag: 'div[data-type="mermaid-block"]' }];
  },

  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { 'data-type': 'mermaid-block', class: 'lepora-mermaid-block' })];
  },

  addInputRules() {
    return [
      new InputRule({
        find: /^```mermaid\s$/,
        handler: ({ state, range }) => {
          const node = this.type.create({ code: MERMAID_TEMPLATES.flowchart });
          state.tr.replaceWith(range.from - 1, range.to, node);
        },
      }),
    ];
  },

  addNodeView() {
    return ({ node, editor, getPos }) => {
      let currentNode = node;
      let isEditing = String(node.attrs.code ?? '').trim() === '';
      let debounceTimer: number | undefined;
      let lastValidSvg = '';

      const wrapper = document.createElement('div');
      wrapper.className = 'lepora-mermaid-block';
      wrapper.setAttribute('data-type', 'mermaid-block');
      wrapper.contentEditable = 'false';

      const sourceBox = document.createElement('div');
      sourceBox.className = 'block-editor-drawer';

      const header = document.createElement('div');
      header.className = 'block-editor-header';

      const titleGroup = document.createElement('div');
      titleGroup.className = 'block-editor-title-group';

      const label = document.createElement('span');
      label.className = 'block-editor-label';
      label.textContent = 'Mermaid 图表';

      const templateSelect = document.createElement('select');
      templateSelect.className = 'block-editor-select';
      templateSelect.title = '插入示例模板';
      const tplPlaceholder = document.createElement('option');
      tplPlaceholder.value = '';
      tplPlaceholder.textContent = '模板…';
      templateSelect.appendChild(tplPlaceholder);
      for (const [key, labelText] of [
        ['flowchart', '流程图'],
        ['sequence', '时序图'],
        ['mindmap', '思维导图'],
        ['state', '状态图'],
      ]) {
        const opt = document.createElement('option');
        opt.value = key;
        opt.textContent = labelText;
        templateSelect.appendChild(opt);
      }

      const statusBadge = document.createElement('span');
      statusBadge.className = 'mermaid-status-badge';
      statusBadge.hidden = true;

      titleGroup.append(label, templateSelect, statusBadge);

      const actionGroup = document.createElement('div');
      actionGroup.className = 'block-editor-actions';

      const copySvgBtn = document.createElement('button');
      copySvgBtn.type = 'button';
      copySvgBtn.className = 'block-editor-btn';
      copySvgBtn.textContent = '复制 SVG';

      const doneBtn = document.createElement('button');
      doneBtn.type = 'button';
      doneBtn.className = 'block-editor-btn primary';
      doneBtn.textContent = '完成 ⌘↩';

      actionGroup.append(copySvgBtn, doneBtn);
      header.append(titleGroup, actionGroup);

      const textarea = document.createElement('textarea');
      textarea.className = 'block-editor-textarea';
      textarea.spellcheck = false;
      textarea.placeholder = 'flowchart LR\n  A[Start] --> B[End]';

      sourceBox.append(header, textarea);

      const preview = document.createElement('div');
      preview.className = 'mermaid-preview';

      const hoverEditBtn = document.createElement('button');
      hoverEditBtn.type = 'button';
      hoverEditBtn.className = 'mermaid-hover-edit';
      hoverEditBtn.textContent = '编辑 Mermaid';

      wrapper.append(sourceBox, preview, hoverEditBtn);

      const commitCode = (code: string) => {
        const pos = typeof getPos === 'function' ? getPos() : undefined;
        if (typeof pos !== 'number') return;
        const tr = editor.view.state.tr.setNodeMarkup(pos, undefined, {
          ...currentNode.attrs,
          code,
        });
        editor.view.dispatch(tr);
      };

      const renderDiagram = async (code: string) => {
        if (!code.trim()) {
          preview.innerHTML = '<div class="mermaid-empty">点击输入 Mermaid 图表语法…</div>';
          statusBadge.hidden = true;
          return;
        }
        const result = await renderMermaid(code);
        if (result.svg) {
          lastValidSvg = result.svg;
          preview.innerHTML = result.svg;
          statusBadge.hidden = true;
        } else if (result.error) {
          if (lastValidSvg) {
            // Keep last valid SVG visible while typing to prevent jarring flicker
            statusBadge.hidden = false;
            statusBadge.textContent = '语法未完成';
            statusBadge.title = result.error;
          } else {
            preview.innerHTML = `<div class="mermaid-error">Mermaid 语法解析错误：${result.error
              .replace(/</g, '&lt;')
              .slice(0, 180)}</div>`;
          }
        }
      };

      const syncEditingUI = () => {
        wrapper.classList.toggle('is-editing', isEditing);
        sourceBox.hidden = !isEditing;
        hoverEditBtn.hidden = isEditing;
        if (isEditing) {
          textarea.value = String(currentNode.attrs.code ?? '');
          requestAnimationFrame(() => {
            autoResizeTextarea(textarea);
            textarea.focus();
          });
        }
      };

      const exitEditing = (moveAfter = false) => {
        if (!isEditing) return;
        isEditing = false;
        syncEditingUI();
        if (moveAfter) {
          const pos = typeof getPos === 'function' ? getPos() : undefined;
          if (typeof pos === 'number') {
            const after = pos + currentNode.nodeSize;
            const tr = editor.view.state.tr;
            if (after <= tr.doc.content.size) {
              tr.setSelection(TextSelection.near(tr.doc.resolve(after)));
              editor.view.dispatch(tr);
              editor.view.focus();
            }
          }
        }
      };

      void renderDiagram(String(currentNode.attrs.code ?? ''));
      syncEditingUI();

      const onThemeRefresh = () => {
        void renderDiagram(isEditing ? textarea.value : String(currentNode.attrs.code ?? ''));
      };
      window.addEventListener('lepora-theme-changed', onThemeRefresh);

      const enterEdit = (e: MouseEvent) => {
        e.stopPropagation();
        if (!isEditing) {
          isEditing = true;
          syncEditingUI();
        }
      };

      const onInput = () => {
        autoResizeTextarea(textarea);
        commitCode(textarea.value);
        window.clearTimeout(debounceTimer);
        debounceTimer = window.setTimeout(() => {
          void renderDiagram(textarea.value);
        }, 120);
      };

      const onTemplateChange = () => {
        const key = templateSelect.value;
        if (key && MERMAID_TEMPLATES[key]) {
          textarea.value = MERMAID_TEMPLATES[key];
          templateSelect.value = '';
          onInput();
        }
      };

      const onKeyDown = (e: KeyboardEvent) => {
        e.stopPropagation();
        if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
          e.preventDefault();
          exitEditing(true);
        } else if (e.key === 'Escape') {
          e.preventDefault();
          exitEditing(false);
          editor.view.focus();
        } else if (e.key === 'Tab') {
          e.preventDefault();
          const start = textarea.selectionStart;
          const end = textarea.selectionEnd;
          textarea.setRangeText('  ', start, end, 'end');
          onInput();
        }
      };

      const onCopySvg = (e: MouseEvent) => {
        e.stopPropagation();
        if (lastValidSvg) {
          void navigator.clipboard?.writeText(lastValidSvg);
          copySvgBtn.textContent = '已复制';
          setTimeout(() => {
            copySvgBtn.textContent = '复制 SVG';
          }, 1200);
        }
      };

      const onDoneClick = (e: MouseEvent) => {
        e.stopPropagation();
        exitEditing(true);
      };

      const onDocMouseDown = (e: MouseEvent) => {
        if (isEditing && !wrapper.contains(e.target as globalThis.Node)) {
          exitEditing(false);
        }
      };

      preview.addEventListener('click', enterEdit);
      hoverEditBtn.addEventListener('click', enterEdit);
      textarea.addEventListener('input', onInput);
      textarea.addEventListener('keydown', onKeyDown);
      templateSelect.addEventListener('change', onTemplateChange);
      copySvgBtn.addEventListener('click', onCopySvg);
      doneBtn.addEventListener('click', onDoneClick);
      document.addEventListener('mousedown', onDocMouseDown);

      return {
        dom: wrapper,
        stopEvent: (event) => isEditing && sourceBox.contains(event.target as globalThis.Node),
        ignoreMutation: () => true,
        update(updatedNode) {
          if (updatedNode.type.name !== 'mermaidBlock') return false;
          currentNode = updatedNode;
          const newCode = String(updatedNode.attrs.code ?? '');
          if (!isEditing) {
            void renderDiagram(newCode);
          } else if (textarea.value !== newCode) {
            textarea.value = newCode;
            autoResizeTextarea(textarea);
            void renderDiagram(newCode);
          }
          return true;
        },
        destroy() {
          window.clearTimeout(debounceTimer);
          window.removeEventListener('lepora-theme-changed', onThemeRefresh);
          preview.removeEventListener('click', enterEdit);
          hoverEditBtn.removeEventListener('click', enterEdit);
          textarea.removeEventListener('input', onInput);
          textarea.removeEventListener('keydown', onKeyDown);
          templateSelect.removeEventListener('change', onTemplateChange);
          copySvgBtn.removeEventListener('click', onCopySvg);
          doneBtn.removeEventListener('click', onDoneClick);
          document.removeEventListener('mousedown', onDocMouseDown);
        },
      };
    };
  },
});

/**
 * Interactive Resizable Image Node (Typora-style local/remote asset support)
 */
export const LeporaImage = Node.create({
  name: 'leporaImage',
  group: 'inline',
  inline: true,
  atom: true,
  draggable: true,
  selectable: true,

  addAttributes() {
    return {
      src: { default: '' },
      alt: { default: '' },
      title: { default: '' },
      width: { default: null },
    };
  },

  parseHTML() {
    return [{ tag: 'img[src]' }];
  },

  renderHTML({ HTMLAttributes }) {
    return ['img', mergeAttributes(HTMLAttributes, { class: 'lepora-image' })];
  },

  addInputRules() {
    return [
      new InputRule({
        find: /!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)$/,
        handler: ({ state, range, match }) => {
          const [, alt, src, title] = match;
          const node = this.type.create({ src, alt: alt ?? '', title: title ?? '', width: null });
          state.tr.replaceWith(range.from, range.to, node);
        },
      }),
    ];
  },

  addNodeView() {
    return ({ node, editor, getPos }) => {
      let currentNode = node;

      const figure = document.createElement('span');
      figure.className = 'lepora-image-wrapper';
      figure.contentEditable = 'false';

      const img = document.createElement('img');
      img.className = 'lepora-image';
      img.loading = 'lazy';
      img.decoding = 'async';

      const overlay = document.createElement('span');
      overlay.className = 'image-hover-bar';

      const sizeLabel = document.createElement('span');
      sizeLabel.className = 'image-size-label';

      const resetBtn = document.createElement('button');
      resetBtn.type = 'button';
      resetBtn.textContent = '原尺寸';
      resetBtn.title = '恢复原始尺寸';

      const revealBtn = document.createElement('button');
      revealBtn.type = 'button';
      revealBtn.textContent = '访达显示';
      revealBtn.title = '在 Finder 中显示图片文件';

      overlay.append(sizeLabel, resetBtn, revealBtn);

      const resizeHandle = document.createElement('span');
      resizeHandle.className = 'image-resize-handle';
      resizeHandle.title = '拖拽缩放图片宽度';

      const caption = document.createElement('span');
      caption.className = 'image-caption';

      figure.append(img, overlay, resizeHandle, caption);

      const applyAttrs = () => {
        const rawSrc = String(currentNode.attrs.src ?? '');
        const resolved = imageUrlResolver(rawSrc);
        if (img.src !== resolved) {
          img.src = resolved;
        }
        img.alt = String(currentNode.attrs.alt ?? '');
        img.title = String(currentNode.attrs.title ?? '');
        const w = currentNode.attrs.width;
        if (w) {
          img.style.width = /^\d+$/.test(String(w)) ? `${w}px` : String(w);
          sizeLabel.textContent = img.style.width;
        } else {
          img.style.width = '';
          sizeLabel.textContent = '100%';
        }
        const altText = String(currentNode.attrs.alt ?? '').trim();
        caption.textContent = altText;
        caption.hidden = !altText;
        revealBtn.hidden = /^https?:\/\//i.test(rawSrc) || /^data:/i.test(rawSrc);
      };

      applyAttrs();

      const updateNodeAttr = (attrs: Record<string, unknown>) => {
        const pos = typeof getPos === 'function' ? getPos() : undefined;
        if (typeof pos !== 'number') return;
        const tr = editor.view.state.tr.setNodeMarkup(pos, undefined, {
          ...currentNode.attrs,
          ...attrs,
        });
        editor.view.dispatch(tr);
      };

      let startX = 0;
      let startWidth = 0;

      const onResizeMove = (e: MouseEvent) => {
        const nextWidth = Math.max(80, Math.min(1200, Math.round(startWidth + (e.clientX - startX))));
        img.style.width = `${nextWidth}px`;
        sizeLabel.textContent = `${nextWidth}px`;
      };

      const onResizeEnd = () => {
        figure.classList.remove('is-resizing');
        window.removeEventListener('mousemove', onResizeMove);
        window.removeEventListener('mouseup', onResizeEnd);
        const finalWidth = Math.round(img.getBoundingClientRect().width);
        if (finalWidth >= 80) {
          updateNodeAttr({ width: `${finalWidth}px` });
        }
      };

      const onResizeStart = (e: MouseEvent) => {
        e.preventDefault();
        e.stopPropagation();
        startX = e.clientX;
        startWidth = img.getBoundingClientRect().width;
        figure.classList.add('is-resizing');
        window.addEventListener('mousemove', onResizeMove);
        window.addEventListener('mouseup', onResizeEnd);
      };

      const onReset = (e: MouseEvent) => {
        e.preventDefault();
        e.stopPropagation();
        updateNodeAttr({ width: null });
      };

      const onReveal = (e: MouseEvent) => {
        e.preventDefault();
        e.stopPropagation();
        revealImageHandler(String(currentNode.attrs.src ?? ''));
      };

      resizeHandle.addEventListener('mousedown', onResizeStart);
      resetBtn.addEventListener('click', onReset);
      revealBtn.addEventListener('click', onReveal);

      return {
        dom: figure,
        stopEvent: (e) => overlay.contains(e.target as globalThis.Node) || e.target === resizeHandle,
        ignoreMutation: () => true,
        update(updatedNode) {
          if (updatedNode.type.name !== 'leporaImage') return false;
          currentNode = updatedNode;
          applyAttrs();
          return true;
        },
        destroy() {
          resizeHandle.removeEventListener('mousedown', onResizeStart);
          resetBtn.removeEventListener('click', onReset);
          revealBtn.removeEventListener('click', onReveal);
          window.removeEventListener('mousemove', onResizeMove);
          window.removeEventListener('mouseup', onResizeEnd);
        },
      };
    };
  },
});

/**
 * GitHub Alert Callout Block (> [!NOTE], [!TIP], [!IMPORTANT], [!WARNING], [!CAUTION])
 */
export const CalloutBlock = Node.create({
  name: 'callout',
  group: 'block',
  content: 'block+',
  defining: true,

  addAttributes() {
    return {
      calloutType: {
        default: 'note',
        parseHTML: (el) => el.getAttribute('data-callout') ?? 'note',
        renderHTML: (attrs) => ({ 'data-callout': attrs.calloutType }),
      },
    };
  },

  parseHTML() {
    return [{ tag: 'div[data-callout]' }];
  },

  renderHTML({ HTMLAttributes }) {
    const kind = String(HTMLAttributes['data-callout'] ?? 'note');
    return [
      'div',
      mergeAttributes(HTMLAttributes, { class: `lepora-callout callout-${kind}` }),
      0,
    ];
  },
});

/**
 * Enhanced Code Block with subtle Typora-style language pill + copy button
 */
const COMMON_LANGUAGES = [
  '',
  'swift',
  'typescript',
  'javascript',
  'python',
  'rust',
  'go',
  'cpp',
  'c',
  'java',
  'bash',
  'json',
  'yaml',
  'html',
  'css',
  'sql',
  'latex',
  'markdown',
  'diff',
];

export const LeporaCodeBlock = CodeBlockLowlight.extend({
  addNodeView() {
    return ({ node, editor, getPos }) => {
      let currentNode = node;

      const container = document.createElement('div');
      container.className = 'lepora-code-block';

      const toolbar = document.createElement('div');
      toolbar.className = 'code-block-toolbar';
      toolbar.contentEditable = 'false';

      const langSelect = document.createElement('select');
      langSelect.className = 'code-lang-select';
      langSelect.setAttribute('aria-label', 'Code language');
      for (const lang of COMMON_LANGUAGES) {
        const opt = document.createElement('option');
        opt.value = lang;
        opt.textContent = lang || '纯文本';
        langSelect.appendChild(opt);
      }

      const syncLangOption = (lang: string) => {
        if (lang && !COMMON_LANGUAGES.includes(lang)) {
          const extra = document.createElement('option');
          extra.value = lang;
          extra.textContent = lang;
          langSelect.appendChild(extra);
        }
        langSelect.value = lang;
      };
      syncLangOption(String(currentNode.attrs.language ?? ''));

      const copyBtn = document.createElement('button');
      copyBtn.type = 'button';
      copyBtn.className = 'code-copy-btn';
      copyBtn.textContent = '复制';

      toolbar.append(langSelect, copyBtn);

      const pre = document.createElement('pre');
      const code = document.createElement('code');
      pre.appendChild(code);

      container.append(toolbar, pre);

      const onLangChange = () => {
        const pos = typeof getPos === 'function' ? getPos() : undefined;
        if (typeof pos !== 'number') return;
        const lang = langSelect.value || null;
        if (lang === 'mermaid') {
          const text = currentNode.textContent;
          const mermaidNode = editor.schema.nodes.mermaidBlock?.create({ code: text });
          if (mermaidNode) {
            editor.view.dispatch(editor.view.state.tr.replaceWith(pos, pos + currentNode.nodeSize, mermaidNode));
            return;
          }
        }
        editor.view.dispatch(
          editor.view.state.tr.setNodeMarkup(pos, undefined, {
            ...currentNode.attrs,
            language: lang,
          })
        );
      };

      const onCopy = () => {
        void navigator.clipboard?.writeText(currentNode.textContent);
        copyBtn.textContent = '已复制';
        setTimeout(() => {
          copyBtn.textContent = '复制';
        }, 1200);
      };

      langSelect.addEventListener('change', onLangChange);
      copyBtn.addEventListener('click', onCopy);

      return {
        dom: container,
        contentDOM: code,
        update(updatedNode) {
          if (updatedNode.type.name !== 'codeBlock') return false;
          currentNode = updatedNode;
          syncLangOption(String(updatedNode.attrs.language ?? ''));
          return true;
        },
        destroy() {
          langSelect.removeEventListener('change', onLangChange);
          copyBtn.removeEventListener('click', onCopy);
        },
      };
    };
  },
}).configure({
  lowlight,
  defaultLanguage: null,
});

/**
 * Table Cell & Header with text-align preservation for GFM tables
 */
export const LeporaTableCell = TableCell.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      textAlign: {
        default: null,
        parseHTML: (el) => el.style.textAlign || null,
        renderHTML: (attrs) => (attrs.textAlign ? { style: `text-align: ${attrs.textAlign}` } : {}),
      },
    };
  },
});

export const LeporaTableHeader = TableHeader.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      textAlign: {
        default: null,
        parseHTML: (el) => el.style.textAlign || null,
        renderHTML: (attrs) => (attrs.textAlign ? { style: `text-align: ${attrs.textAlign}` } : {}),
      },
    };
  },
});

/**
 * Focus Mode Active Block Tracker Plugin
 */
export const focusTrackerKey = new PluginKey('leporaFocusTracker');

export function createFocusTrackerPlugin(): Plugin {
  return new Plugin({
    key: focusTrackerKey,
    props: {
      decorations(state) {
        const { $from } = state.selection;
        if ($from.depth < 1) return DecorationSet.empty;
        const start = $from.before(1);
        const node = state.doc.nodeAt(start);
        if (!node) return DecorationSet.empty;
        return DecorationSet.create(state.doc, [
          Decoration.node(start, start + node.nodeSize, {
            class: 'is-focused-block',
          }),
        ]);
      },
    },
  });
}

/**
 * Find & Replace Highlight Plugin
 */
export interface SearchPluginState {
  query: string;
  caseSensitive: boolean;
  matches: Array<{ from: number; to: number }>;
  activeIndex: number;
  decorations: DecorationSet;
}

export const searchPluginKey = new PluginKey<SearchPluginState>('leporaSearch');

function computeSearchState(
  doc: import('@tiptap/pm/model').Node,
  query: string,
  caseSensitive: boolean,
  activeIndex: number
): SearchPluginState {
  if (!query) {
    return {
      query: '',
      caseSensitive,
      matches: [],
      activeIndex: -1,
      decorations: DecorationSet.empty,
    };
  }

  const needle = caseSensitive ? query : query.toLowerCase();
  const matches: Array<{ from: number; to: number }> = [];

  doc.descendants((node, pos) => {
    if (!node.isText || !node.text) return;
    const haystack = caseSensitive ? node.text : node.text.toLowerCase();
    let idx = haystack.indexOf(needle);
    while (idx !== -1) {
      matches.push({ from: pos + idx, to: pos + idx + query.length });
      idx = haystack.indexOf(needle, idx + Math.max(1, needle.length));
    }
  });

  const clampedIndex = matches.length === 0 ? -1 : ((activeIndex % matches.length) + matches.length) % matches.length;
  const decos = matches.map((m, i) =>
    Decoration.inline(m.from, m.to, {
      class: i === clampedIndex ? 'lepora-search-match is-current' : 'lepora-search-match',
    })
  );

  return {
    query,
    caseSensitive,
    matches,
    activeIndex: clampedIndex,
    decorations: DecorationSet.create(doc, decos),
  };
}

export function createSearchPlugin(): Plugin<SearchPluginState> {
  return new Plugin<SearchPluginState>({
    key: searchPluginKey,
    state: {
      init: () => ({
        query: '',
        caseSensitive: false,
        matches: [],
        activeIndex: -1,
        decorations: DecorationSet.empty,
      }),
      apply(tr, prev, _oldState, newState) {
        const meta = tr.getMeta(searchPluginKey) as
          | { query?: string; caseSensitive?: boolean; activeIndex?: number }
          | undefined;
        if (meta) {
          const q = meta.query ?? prev.query;
          const cs = meta.caseSensitive ?? prev.caseSensitive;
          const idx = meta.activeIndex ?? prev.activeIndex;
          return computeSearchState(newState.doc, q, cs, idx);
        }
        if (tr.docChanged && prev.query) {
          return computeSearchState(newState.doc, prev.query, prev.caseSensitive, prev.activeIndex);
        }
        return prev;
      },
    },
    props: {
      decorations(state) {
        return searchPluginKey.getState(state)?.decorations ?? DecorationSet.empty;
      },
    },
  });
}
