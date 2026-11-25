import MarkdownIt from 'markdown-it';
import type Token from 'markdown-it/lib/token.mjs';
import type StateBlock from 'markdown-it/lib/rules_block/state_block.mjs';
import type StateInline from 'markdown-it/lib/rules_inline/state_inline.mjs';
import type { JSONContent } from '@tiptap/core';

const LATEX_ENV_NAMES = new Set([
  'equation',
  'equation*',
  'align',
  'align*',
  'alignat',
  'alignat*',
  'xalignat',
  'xalignat*',
  'xxalignat',
  'gather',
  'gather*',
  'multline',
  'multline*',
  'flalign',
  'flalign*',
  'eqnarray',
  'eqnarray*',
  'split',
  'cases',
  'dcases',
  'rcases',
  'matrix',
  'pmatrix',
  'bmatrix',
  'Bmatrix',
  'vmatrix',
  'Vmatrix',
  'smallmatrix',
  'array',
  'subequations',
  'CD',
]);

function isValidInlineDollarOpen(src: string, pos: number): boolean {
  const nextChar = src.charCodeAt(pos + 1);
  // Cannot be empty, whitespace, or another '$'
  if (Number.isNaN(nextChar) || nextChar === 0x20 || nextChar === 0x09 || nextChar === 0x0a || nextChar === 0x24) {
    return false;
  }
  return true;
}

function isValidInlineDollarClose(src: string, pos: number): boolean {
  const prevChar = src.charCodeAt(pos - 1);
  if (prevChar === 0x20 || prevChar === 0x09 || prevChar === 0x0a) {
    return false;
  }
  const nextChar = src.charCodeAt(pos + 1);
  // Avoid matching currency like "$5 and $10" (closing '$' directly followed by digit)
  if (nextChar >= 0x30 && nextChar <= 0x39) {
    return false;
  }
  return true;
}

/**
 * Block rule: $$ ... $$ (single-line or multi-line)
 */
function mathBlockDollarRule(
  state: StateBlock,
  startLine: number,
  endLine: number,
  silent: boolean
): boolean {
  let pos = state.bMarks[startLine] + state.tShift[startLine];
  let max = state.eMarks[startLine];

  if (pos + 2 > max) return false;
  if (state.src.slice(pos, pos + 2) !== '$$') return false;

  pos += 2;
  let firstLine = state.src.slice(pos, max);

  if (silent) return true;

  // Single-line $$ ... $$
  if (firstLine.trim().endsWith('$$') && firstLine.trim().length >= 2) {
    const trimmed = firstLine.trim();
    const tex = trimmed.slice(0, -2).trim();
    const token = state.push('math_block', 'math', 0);
    token.block = true;
    token.content = tex;
    token.meta = { delimiter: '$$' };
    token.map = [startLine, startLine + 1];
    state.line = startLine + 1;
    return true;
  }

  let nextLine = startLine;
  let foundClosing = false;
  let lastLine = '';

  while (++nextLine < endLine) {
    pos = state.bMarks[nextLine] + state.tShift[nextLine];
    max = state.eMarks[nextLine];

    if (pos < max && state.tShift[nextLine] < state.blkIndent) {
      break;
    }

    const lineText = state.src.slice(pos, max);
    if (lineText.trim().endsWith('$$')) {
      const idx = lineText.lastIndexOf('$$');
      lastLine = lineText.slice(0, idx);
      foundClosing = true;
      break;
    }
  }

  if (!foundClosing) return false;

  const middleLines = state.getLines(startLine + 1, nextLine, state.tShift[startLine], true);
  const content = [firstLine, middleLines, lastLine]
    .join('\n')
    .replace(/^\n+|\n+$/g, '');

  const token = state.push('math_block', 'math', 0);
  token.block = true;
  token.content = content;
  token.meta = { delimiter: '$$' };
  token.map = [startLine, nextLine + 1];
  state.line = nextLine + 1;
  return true;
}

/**
 * Block rule: \[ ... \] (single-line or multi-line)
 */
function mathBlockBracketRule(
  state: StateBlock,
  startLine: number,
  endLine: number,
  silent: boolean
): boolean {
  let pos = state.bMarks[startLine] + state.tShift[startLine];
  let max = state.eMarks[startLine];

  if (pos + 2 > max) return false;
  if (state.src.slice(pos, pos + 2) !== '\\[') return false;

  pos += 2;
  const firstLine = state.src.slice(pos, max);

  if (silent) return true;

  if (firstLine.trim().endsWith('\\]')) {
    const trimmed = firstLine.trim();
    const tex = trimmed.slice(0, -2).trim();
    const token = state.push('math_block', 'math', 0);
    token.block = true;
    token.content = tex;
    token.meta = { delimiter: '\\[' };
    token.map = [startLine, startLine + 1];
    state.line = startLine + 1;
    return true;
  }

  let nextLine = startLine;
  let foundClosing = false;
  let lastLine = '';

  while (++nextLine < endLine) {
    pos = state.bMarks[nextLine] + state.tShift[nextLine];
    max = state.eMarks[nextLine];
    const lineText = state.src.slice(pos, max);
    if (lineText.trim().endsWith('\\]')) {
      const idx = lineText.lastIndexOf('\\]');
      lastLine = lineText.slice(0, idx);
      foundClosing = true;
      break;
    }
  }

  if (!foundClosing) return false;

  const middleLines = state.getLines(startLine + 1, nextLine, state.tShift[startLine], true);
  const content = [firstLine, middleLines, lastLine]
    .join('\n')
    .replace(/^\n+|\n+$/g, '');

  const token = state.push('math_block', 'math', 0);
  token.block = true;
  token.content = content;
  token.meta = { delimiter: '\\[' };
  token.map = [startLine, nextLine + 1];
  state.line = nextLine + 1;
  return true;
}

/**
 * Block rule: Standalone LaTeX environments like \begin{equation}...\end{equation},
 * \begin{align}...\end{align}, \begin{cases}...\end{cases}, etc.
 */
function mathBlockEnvRule(
  state: StateBlock,
  startLine: number,
  endLine: number,
  silent: boolean
): boolean {
  const pos = state.bMarks[startLine] + state.tShift[startLine];
  const max = state.eMarks[startLine];
  const firstLine = state.src.slice(pos, max);

  const match = firstLine.match(/^\\begin\{([a-zA-Z]+\*?)\}/);
  if (!match) return false;
  const envName = match[1];
  if (!LATEX_ENV_NAMES.has(envName)) return false;

  if (silent) return true;

  const endMarker = `\\end{${envName}}`;
  if (firstLine.includes(endMarker)) {
    const token = state.push('math_block', 'math', 0);
    token.block = true;
    token.content = firstLine.trim();
    token.meta = { delimiter: 'env' };
    token.map = [startLine, startLine + 1];
    state.line = startLine + 1;
    return true;
  }

  let nextLine = startLine;
  let foundClosing = false;
  while (++nextLine < endLine) {
    const lPos = state.bMarks[nextLine] + state.tShift[nextLine];
    const lMax = state.eMarks[nextLine];
    const lineText = state.src.slice(lPos, lMax);
    if (lineText.includes(endMarker)) {
      foundClosing = true;
      break;
    }
  }

  if (!foundClosing) return false;

  const content = state.getLines(startLine, nextLine + 1, state.tShift[startLine], false).trim();
  const token = state.push('math_block', 'math', 0);
  token.block = true;
  token.content = content;
  token.meta = { delimiter: 'env' };
  token.map = [startLine, nextLine + 1];
  state.line = nextLine + 1;
  return true;
}

/**
 * Inline rule: $...$, \(...\), and inline $$...$$
 */
function mathInlineRule(state: StateInline, silent: boolean): boolean {
  const src = state.src;
  const start = state.pos;
  const max = state.posMax;

  // Case 1: \( ... \)
  if (src.charCodeAt(start) === 0x5c /* \ */ && src.charCodeAt(start + 1) === 0x28 /* ( */) {
    let pos = start + 2;
    while (pos < max - 1) {
      if (src.charCodeAt(pos) === 0x5c && src.charCodeAt(pos + 1) === 0x29 /* ) */) {
        // Check not escaped backslash
        let backslashes = 0;
        let k = pos - 1;
        while (k >= start + 2 && src.charCodeAt(k) === 0x5c) {
          backslashes++;
          k--;
        }
        if (backslashes % 2 === 0) {
          const tex = src.slice(start + 2, pos).trim();
          if (!tex) return false;
          if (!silent) {
            const token = state.push('math_inline', 'math', 0);
            token.content = tex;
            token.meta = { delimiter: '\\(' };
          }
          state.pos = pos + 2;
          return true;
        }
      }
      pos++;
    }
    return false;
  }

  // Case 2: \[ ... \] appearing inline
  if (src.charCodeAt(start) === 0x5c && src.charCodeAt(start + 1) === 0x5b /* [ */) {
    let pos = start + 2;
    while (pos < max - 1) {
      if (src.charCodeAt(pos) === 0x5c && src.charCodeAt(pos + 1) === 0x5d /* ] */) {
        const tex = src.slice(start + 2, pos).trim();
        if (!tex) return false;
        if (!silent) {
          const token = state.push('math_inline', 'math', 0);
          token.content = tex;
          token.meta = { delimiter: '\\[', displayStyle: true };
        }
        state.pos = pos + 2;
        return true;
      }
      pos++;
    }
    return false;
  }

  if (src.charCodeAt(start) !== 0x24 /* $ */) return false;

  // Case 3: Inline $$ ... $$
  if (src.charCodeAt(start + 1) === 0x24) {
    const closeIdx = src.indexOf('$$', start + 2);
    if (closeIdx === -1 || closeIdx >= max) return false;
    const tex = src.slice(start + 2, closeIdx).trim();
    if (!tex) return false;
    if (!silent) {
      const token = state.push('math_inline', 'math', 0);
      token.content = tex;
      token.meta = { delimiter: '$$', displayStyle: true };
    }
    state.pos = closeIdx + 2;
    return true;
  }

  // Case 4: Standard $ ... $
  if (!isValidInlineDollarOpen(src, start)) return false;

  let pos = start + 1;
  while (pos < max) {
    const ch = src.charCodeAt(pos);
    if (ch === 0x5c /* \ */) {
      pos += 2; // Skip escaped character (e.g., \$)
      continue;
    }
    if (ch === 0x24 /* $ */) {
      if (isValidInlineDollarClose(src, pos)) {
        const tex = src.slice(start + 1, pos);
        if (!tex.trim()) return false;
        if (!silent) {
          const token = state.push('math_inline', 'math', 0);
          token.content = tex;
          token.meta = { delimiter: '$' };
        }
        state.pos = pos + 1;
        return true;
      }
    }
    pos++;
  }

  return false;
}

/**
 * Inline rule: ==highlight==
 */
function highlightInlineRule(state: StateInline, silent: boolean): boolean {
  const src = state.src;
  const start = state.pos;
  const max = state.posMax;

  if (src.charCodeAt(start) !== 0x3d || src.charCodeAt(start + 1) !== 0x3d) {
    return false;
  }
  const end = src.indexOf('==', start + 2);
  if (end === -1 || end >= max || end === start + 2) return false;

  if (!silent) {
    const open = state.push('mark_open', 'mark', 1);
    open.markup = '==';
    const text = state.push('text', '', 0);
    text.content = src.slice(start + 2, end);
    const close = state.push('mark_close', 'mark', -1);
    close.markup = '==';
  }
  state.pos = end + 2;
  return true;
}

function createMarkdownParser(): MarkdownIt {
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    breaks: false,
    typographer: false,
  });

  md.block.ruler.before('fence', 'math_block_dollar', mathBlockDollarRule, {
    alt: ['paragraph', 'reference', 'blockquote', 'list'],
  });
  md.block.ruler.before('fence', 'math_block_bracket', mathBlockBracketRule, {
    alt: ['paragraph', 'reference', 'blockquote', 'list'],
  });
  md.block.ruler.before('fence', 'math_block_env', mathBlockEnvRule, {
    alt: ['paragraph', 'reference', 'blockquote', 'list'],
  });

  md.inline.ruler.before('escape', 'math_inline', mathInlineRule);
  md.inline.ruler.before('emphasis', 'mark_highlight', highlightInlineRule);

  return md;
}

const mdParser = createMarkdownParser();

interface MarkSpec {
  type: string;
  attrs?: Record<string, unknown>;
}

function cloneMarks(marks: MarkSpec[]): MarkSpec[] | undefined {
  return marks.length > 0 ? marks.map((m) => ({ ...m })) : undefined;
}

function parseInlineTokens(tokens: Token[]): JSONContent[] {
  const result: JSONContent[] = [];
  const marks: MarkSpec[] = [];

  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];

    switch (token.type) {
      case 'text': {
        if (token.content) {
          result.push({
            type: 'text',
            text: token.content,
            ...(marks.length ? { marks: cloneMarks(marks) } : {}),
          });
        }
        break;
      }

      case 'code_inline': {
        if (token.content) {
          result.push({
            type: 'text',
            text: token.content,
            marks: [...marks, { type: 'code' }],
          });
        }
        break;
      }

      case 'math_inline': {
        result.push({
          type: 'inlineMath',
          attrs: {
            tex: token.content,
            delimiter: token.meta?.delimiter ?? '$',
            displayStyle: Boolean(token.meta?.displayStyle),
          },
        });
        break;
      }

      case 'softbreak': {
        result.push({
          type: 'text',
          text: '\n',
          ...(marks.length ? { marks: cloneMarks(marks) } : {}),
        });
        break;
      }

      case 'hardbreak': {
        result.push({ type: 'hardBreak' });
        break;
      }

      case 'strong_open':
        marks.push({ type: 'bold' });
        break;
      case 'strong_close':
        popMark(marks, 'bold');
        break;

      case 'em_open':
        marks.push({ type: 'italic' });
        break;
      case 'em_close':
        popMark(marks, 'italic');
        break;

      case 's_open':
        marks.push({ type: 'strike' });
        break;
      case 's_close':
        popMark(marks, 'strike');
        break;

      case 'mark_open':
        marks.push({ type: 'highlight' });
        break;
      case 'mark_close':
        popMark(marks, 'highlight');
        break;

      case 'link_open': {
        const href = token.attrGet('href') ?? '';
        const title = token.attrGet('title');
        marks.push({
          type: 'link',
          attrs: { href, ...(title ? { title } : {}) },
        });
        break;
      }
      case 'link_close':
        popMark(marks, 'link');
        break;

      case 'image': {
        const src = token.attrGet('src') ?? '';
        const title = token.attrGet('title') ?? '';
        const alt = token.content || token.children?.map((c) => c.content).join('') || '';
        result.push({
          type: 'leporaImage',
          attrs: { src, alt, title, width: null },
        });
        break;
      }

      case 'html_inline': {
        const raw = token.content.trim();
        const lower = raw.toLowerCase();
        if (lower === '<u>') {
          marks.push({ type: 'underline' });
        } else if (lower === '</u>') {
          popMark(marks, 'underline');
        } else if (lower === '<mark>') {
          marks.push({ type: 'highlight' });
        } else if (lower === '</mark>') {
          popMark(marks, 'highlight');
        } else if (lower === '<sub>') {
          marks.push({ type: 'subscript' });
        } else if (lower === '</sub>') {
          popMark(marks, 'subscript');
        } else if (lower === '<sup>') {
          marks.push({ type: 'superscript' });
        } else if (lower === '</sup>') {
          popMark(marks, 'superscript');
        } else if (/^<br\s*\/?>$/i.test(raw)) {
          result.push({ type: 'hardBreak' });
        } else if (/^<img\b/i.test(raw)) {
          const img = parseHtmlImgTag(raw);
          if (img) result.push(img);
        } else {
          // Keep unrecognized inline HTML as literal text so user content is never lost
          result.push({
            type: 'text',
            text: token.content,
            ...(marks.length ? { marks: cloneMarks(marks) } : {}),
          });
        }
        break;
      }

      default:
        break;
    }
  }

  return result;
}

function popMark(marks: MarkSpec[], type: string): void {
  for (let i = marks.length - 1; i >= 0; i--) {
    if (marks[i].type === type) {
      marks.splice(i, 1);
      return;
    }
  }
}

function parseHtmlImgTag(html: string): JSONContent | null {
  const srcMatch = html.match(/src=["']([^"']+)["']/i);
  if (!srcMatch) return null;
  const altMatch = html.match(/alt=["']([^"']*)["']/i);
  const titleMatch = html.match(/title=["']([^"']*)["']/i);
  const widthMatch = html.match(/width=["']?(\d+(?:px|%)?)["']?/i);
  const styleWidthMatch = html.match(/width:\s*(\d+(?:px|%))/i);
  const width = widthMatch?.[1] ?? styleWidthMatch?.[1] ?? null;

  return {
    type: 'leporaImage',
    attrs: {
      src: srcMatch[1],
      alt: altMatch?.[1] ?? '',
      title: titleMatch?.[1] ?? '',
      width,
    },
  };
}

function parseBlockTokens(tokens: Token[], startIdx: number, endIdx: number): JSONContent[] {
  const nodes: JSONContent[] = [];
  let i = startIdx;

  while (i < endIdx) {
    const token = tokens[i];

    switch (token.type) {
      case 'heading_open': {
        const level = Number(token.tag.slice(1)) || 1;
        const inlineToken = tokens[i + 1];
        const content = inlineToken?.children ? parseInlineTokens(inlineToken.children) : [];
        nodes.push({
          type: 'heading',
          attrs: { level: Math.min(6, Math.max(1, level)) },
          ...(content.length ? { content } : {}),
        });
        i += 3; // heading_open, inline, heading_close
        break;
      }

      case 'paragraph_open': {
        const inlineToken = tokens[i + 1];
        const content = inlineToken?.children ? parseInlineTokens(inlineToken.children) : [];
        nodes.push({
          type: 'paragraph',
          ...(content.length ? { content } : {}),
        });
        i += 3;
        break;
      }

      case 'math_block': {
        nodes.push({
          type: 'displayMath',
          attrs: {
            tex: token.content,
            delimiter: token.meta?.delimiter ?? '$$',
          },
        });
        i += 1;
        break;
      }

      case 'fence':
      case 'code_block': {
        const info = (token.info ?? '').trim();
        const lang = info.split(/\s+/)[0]?.toLowerCase() ?? '';
        const code = token.content.replace(/\n$/, '');

        if (lang === 'mermaid') {
          nodes.push({
            type: 'mermaidBlock',
            attrs: { code },
          });
        } else if (lang === 'math') {
          nodes.push({
            type: 'displayMath',
            attrs: { tex: code, delimiter: 'fence' },
          });
        } else {
          nodes.push({
            type: 'codeBlock',
            attrs: { language: lang || null },
            ...(code ? { content: [{ type: 'text', text: code }] } : {}),
          });
        }
        i += 1;
        break;
      }

      case 'hr': {
        nodes.push({ type: 'horizontalRule' });
        i += 1;
        break;
      }

      case 'blockquote_open': {
        const closeIdx = findMatchingClose(tokens, i, 'blockquote_open', 'blockquote_close');
        const children = parseBlockTokens(tokens, i + 1, closeIdx);
        const callout = tryConvertToCallout(children);
        if (callout) {
          nodes.push(callout);
        } else {
          nodes.push({
            type: 'blockquote',
            content: children.length ? children : [{ type: 'paragraph' }],
          });
        }
        i = closeIdx + 1;
        break;
      }

      case 'bullet_list_open': {
        const closeIdx = findMatchingClose(tokens, i, 'bullet_list_open', 'bullet_list_close');
        const listNode = parseList(tokens, i + 1, closeIdx, false);
        nodes.push(listNode);
        i = closeIdx + 1;
        break;
      }

      case 'ordered_list_open': {
        const closeIdx = findMatchingClose(tokens, i, 'ordered_list_open', 'ordered_list_close');
        const startAttr = Number(token.attrGet('start')) || 1;
        const listNode = parseList(tokens, i + 1, closeIdx, true, startAttr);
        nodes.push(listNode);
        i = closeIdx + 1;
        break;
      }

      case 'table_open': {
        const closeIdx = findMatchingClose(tokens, i, 'table_open', 'table_close');
        const tableNode = parseTable(tokens, i + 1, closeIdx);
        if (tableNode) nodes.push(tableNode);
        i = closeIdx + 1;
        break;
      }

      case 'html_block': {
        const raw = token.content.trim();
        if (/^<img\b/i.test(raw)) {
          const img = parseHtmlImgTag(raw);
          if (img) {
            nodes.push({ type: 'paragraph', content: [img] });
            i += 1;
            break;
          }
        }
        // Preserve raw HTML block as a clean paragraph or code block instead of silently dropping
        if (raw) {
          nodes.push({
            type: 'paragraph',
            content: [{ type: 'text', text: raw }],
          });
        }
        i += 1;
        break;
      }

      default:
        i += 1;
        break;
    }
  }

  return nodes;
}

function findMatchingClose(
  tokens: Token[],
  openIdx: number,
  openType: string,
  closeType: string
): number {
  let depth = 0;
  for (let i = openIdx; i < tokens.length; i++) {
    if (tokens[i].type === openType) depth++;
    else if (tokens[i].type === closeType) {
      depth--;
      if (depth === 0) return i;
    }
  }
  return tokens.length - 1;
}

function tryConvertToCallout(children: JSONContent[]): JSONContent | null {
  if (children.length === 0) return null;
  const first = children[0];
  if (first.type !== 'paragraph' || !first.content?.length) return null;
  const firstText = first.content[0];
  if (firstText.type !== 'text' || !firstText.text) return null;

  const match = firstText.text.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](?:\s*\n?|\s+)?/i);
  if (!match) return null;

  const calloutType = match[1].toLowerCase();
  const remainder = firstText.text.slice(match[0].length);
  const updatedFirstContent = [...first.content];
  if (remainder) {
    updatedFirstContent[0] = { ...firstText, text: remainder };
  } else {
    updatedFirstContent.shift();
  }

  const newChildren = [...children];
  if (updatedFirstContent.length > 0) {
    newChildren[0] = { ...first, content: updatedFirstContent };
  } else {
    newChildren.shift();
  }

  return {
    type: 'callout',
    attrs: { calloutType },
    content: newChildren.length ? newChildren : [{ type: 'paragraph' }],
  };
}

function parseList(
  tokens: Token[],
  startIdx: number,
  endIdx: number,
  ordered: boolean,
  startNum = 1
): JSONContent {
  const items: Array<{ content: JSONContent[]; taskChecked: boolean | null }> = [];
  let i = startIdx;

  while (i < endIdx) {
    if (tokens[i].type === 'list_item_open') {
      const closeIdx = findMatchingClose(tokens, i, 'list_item_open', 'list_item_close');
      const itemBlocks = parseBlockTokens(tokens, i + 1, closeIdx);
      let taskChecked: boolean | null = null;

      if (!ordered && itemBlocks.length > 0 && itemBlocks[0].type === 'paragraph') {
        const pContent = itemBlocks[0].content;
        if (pContent && pContent.length > 0 && pContent[0].type === 'text' && pContent[0].text) {
          const m = pContent[0].text.match(/^\[([ xX])\]\s+/);
          if (m) {
            taskChecked = m[1].toLowerCase() === 'x';
            const rest = pContent[0].text.slice(m[0].length);
            if (rest) {
              pContent[0] = { ...pContent[0], text: rest };
            } else {
              pContent.shift();
            }
          }
        }
      }

      items.push({
        content: itemBlocks.length ? itemBlocks : [{ type: 'paragraph' }],
        taskChecked,
      });
      i = closeIdx + 1;
    } else {
      i += 1;
    }
  }

  const isTaskList = !ordered && items.length > 0 && items.every((item) => item.taskChecked !== null);
  if (isTaskList) {
    return {
      type: 'taskList',
      content: items.map((item) => ({
        type: 'taskItem',
        attrs: { checked: Boolean(item.taskChecked) },
        content: item.content,
      })),
    };
  }

  return {
    type: ordered ? 'orderedList' : 'bulletList',
    ...(ordered && startNum !== 1 ? { attrs: { start: startNum } } : {}),
    content: items.map((item) => ({
      type: 'listItem',
      content: item.content,
    })),
  };
}

function parseTable(tokens: Token[], startIdx: number, endIdx: number): JSONContent | null {
  const rows: JSONContent[] = [];
  let i = startIdx;

  while (i < endIdx) {
    if (tokens[i].type === 'tr_open') {
      const closeTr = findMatchingClose(tokens, i, 'tr_open', 'tr_close');
      const cells: JSONContent[] = [];
      let j = i + 1;

      while (j < closeTr) {
        const cellTok = tokens[j];
        if (cellTok.type === 'th_open' || cellTok.type === 'td_open') {
          const isHeader = cellTok.type === 'th_open';
          const closeCell = findMatchingClose(
            tokens,
            j,
            isHeader ? 'th_open' : 'td_open',
            isHeader ? 'th_close' : 'td_close'
          );
          const styleAttr = cellTok.attrGet('style') ?? '';
          const alignMatch = styleAttr.match(/text-align:\s*(left|center|right)/i);
          const textAlign = alignMatch ? alignMatch[1].toLowerCase() : null;

          const inlineTok = tokens[j + 1];
          const inlineContent = inlineTok?.children ? parseInlineTokens(inlineTok.children) : [];

          cells.push({
            type: isHeader ? 'tableHeader' : 'tableCell',
            attrs: { textAlign },
            content: [
              {
                type: 'paragraph',
                ...(inlineContent.length ? { content: inlineContent } : {}),
              },
            ],
          });
          j = closeCell + 1;
        } else {
          j += 1;
        }
      }

      if (cells.length > 0) {
        rows.push({ type: 'tableRow', content: cells });
      }
      i = closeTr + 1;
    } else {
      i += 1;
    }
  }

  if (rows.length === 0) return null;
  return { type: 'table', content: rows };
}

export function markdownToDocJSON(markdown: string): JSONContent {
  const normalized = markdown.replace(/\r\n?/g, '\n');
  const tokens = mdParser.parse(normalized, {});
  const blocks = parseBlockTokens(tokens, 0, tokens.length);

  return {
    type: 'doc',
    content: blocks.length > 0 ? blocks : [{ type: 'paragraph' }],
  };
}
