import type { Node as PMNode, Mark } from '@tiptap/pm/model';

function escapeMarkdownText(text: string): string {
  // Keep text clean and readable; only escape characters that could ambiguously break syntax
  return text.replace(/\\/g, '\\\\');
}

function serializeInline(node: PMNode): string {
  let out = '';

  node.forEach((child) => {
    if (child.isText) {
      let text = child.text ?? '';
      const marks = child.marks;

      const hasCode = marks.some((m) => m.type.name === 'code');
      if (hasCode) {
        const ticks = text.includes('`') ? '``' : '`';
        const pad = text.startsWith('`') || text.endsWith('`') ? ' ' : '';
        text = `${ticks}${pad}${text}${pad}${ticks}`;
        // Still allow link wrapping around inline code
        const linkMark = marks.find((m) => m.type.name === 'link');
        if (linkMark) {
          text = wrapLink(text, linkMark);
        }
        out += text;
        return;
      }

      // Preserve normal LaTeX/text cleanly without over-escaping
      let wrapped = text;
      const orderedMarks = [...marks].sort((a, b) => markPriority(a) - markPriority(b));
      for (const mark of orderedMarks) {
        wrapped = wrapMark(wrapped, mark);
      }
      out += wrapped;
      return;
    }

    switch (child.type.name) {
      case 'hardBreak':
        out += '  \n';
        break;

      case 'inlineMath': {
        const tex = String(child.attrs.tex ?? '');
        const delimiter = String(child.attrs.delimiter ?? '$');
        if (delimiter === '\\(') {
          out += `\\(${tex}\\)`;
        } else if (delimiter === '\\[') {
          out += `\\[${tex}\\]`;
        } else if (delimiter === '$$') {
          out += `$$${tex}$$`;
        } else {
          out += `$${tex}$`;
        }
        break;
      }

      case 'leporaImage': {
        const src = String(child.attrs.src ?? '');
        const alt = String(child.attrs.alt ?? '');
        const title = String(child.attrs.title ?? '');
        const width = child.attrs.width ? String(child.attrs.width) : null;
        if (width) {
          const titleAttr = title ? ` title="${escapeAttr(title)}"` : '';
          out += `<img src="${escapeAttr(src)}" alt="${escapeAttr(alt)}"${titleAttr} width="${escapeAttr(width)}" />`;
        } else {
          const titlePart = title ? ` "${title.replace(/"/g, '\\"')}"` : '';
          out += `![${alt}](${src}${titlePart})`;
        }
        break;
      }

      default:
        out += child.textContent;
        break;
    }
  });

  return out;
}

function escapeAttr(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function markPriority(mark: Mark): number {
  switch (mark.type.name) {
    case 'subscript':
    case 'superscript':
      return 1;
    case 'underline':
    case 'highlight':
      return 2;
    case 'strike':
      return 3;
    case 'italic':
      return 4;
    case 'bold':
      return 5;
    case 'link':
      return 10;
    default:
      return 6;
  }
}

function wrapLink(content: string, mark: Mark): string {
  const href = String(mark.attrs.href ?? '');
  const title = mark.attrs.title ? ` "${String(mark.attrs.title).replace(/"/g, '\\"')}"` : '';
  return `[${content}](${href}${title})`;
}

function wrapMark(content: string, mark: Mark): string {
  if (!content) return content;
  switch (mark.type.name) {
    case 'bold':
      return `**${content}**`;
    case 'italic':
      return `*${content}*`;
    case 'strike':
      return `~~${content}~~`;
    case 'highlight':
      return `==${content}==`;
    case 'underline':
      return `<u>${content}</u>`;
    case 'subscript':
      return `<sub>${content}</sub>`;
    case 'superscript':
      return `<sup>${content}</sup>`;
    case 'link':
      return wrapLink(content, mark);
    default:
      return content;
  }
}

function indentLines(text: string, prefix: string, firstLinePrefix = prefix): string {
  const lines = text.split('\n');
  return lines
    .map((line, idx) => {
      if (idx === 0) return `${firstLinePrefix}${line}`;
      return line.length > 0 ? `${prefix}${line}` : prefix.trimEnd();
    })
    .join('\n');
}

function serializeTable(tableNode: PMNode): string {
  const rows: Array<Array<{ text: string; align: string | null }>> = [];

  tableNode.forEach((row) => {
    const cells: Array<{ text: string; align: string | null }> = [];
    row.forEach((cell) => {
      const parts: string[] = [];
      cell.forEach((child) => {
        parts.push(serializeInline(child).replace(/\n/g, '<br>'));
      });
      const cellText = parts.join('<br>').replace(/\|/g, '\\|').trim();
      cells.push({
        text: cellText,
        align: (cell.attrs.textAlign as string | null) ?? null,
      });
    });
    rows.push(cells);
  });

  if (rows.length === 0) return '';
  const colCount = Math.max(...rows.map((r) => r.length));

  // Compute column widths for crisp, readable GFM pipe tables
  const widths = new Array<number>(colCount).fill(3);
  for (const row of rows) {
    for (let c = 0; c < colCount; c++) {
      const len = (row[c]?.text ?? '').length;
      if (len > widths[c]) widths[c] = len;
    }
  }

  const formatRow = (row: Array<{ text: string; align: string | null }>) => {
    const padded: string[] = [];
    for (let c = 0; c < colCount; c++) {
      const val = row[c]?.text ?? '';
      padded.push(val.padEnd(widths[c], ' '));
    }
    return `| ${padded.join(' | ')} |`;
  };

  const sepCells: string[] = [];
  for (let c = 0; c < colCount; c++) {
    const align = rows[0]?.[c]?.align ?? rows[1]?.[c]?.align ?? null;
    const dashes = '-'.repeat(Math.max(3, widths[c]));
    if (align === 'center') {
      sepCells.push(`:${dashes.slice(1, -1) || '-'}:`);
    } else if (align === 'right') {
      sepCells.push(`${dashes.slice(0, -1) || '--'}:`);
    } else if (align === 'left') {
      sepCells.push(`:${dashes.slice(1) || '--'}`);
    } else {
      sepCells.push(dashes);
    }
  }

  const lines = [formatRow(rows[0]), `| ${sepCells.join(' | ')} |`];
  for (let r = 1; r < rows.length; r++) {
    lines.push(formatRow(rows[r]));
  }
  return lines.join('\n');
}

function serializeBlock(node: PMNode): string {
  switch (node.type.name) {
    case 'heading': {
      const level = Number(node.attrs.level) || 1;
      return `${'#'.repeat(level)} ${serializeInline(node)}`;
    }

    case 'paragraph':
      return serializeInline(node);

    case 'horizontalRule':
      return '---';

    case 'codeBlock': {
      const lang = String(node.attrs.language ?? '');
      const code = node.textContent;
      const fence = code.includes('```') ? '~~~~' : '```';
      return `${fence}${lang}\n${code}\n${fence}`;
    }

    case 'mermaidBlock': {
      const code = String(node.attrs.code ?? '');
      return `\`\`\`mermaid\n${code}\n\`\`\``;
    }

    case 'displayMath': {
      const tex = String(node.attrs.tex ?? '').trim();
      const delimiter = String(node.attrs.delimiter ?? '$$');
      if (delimiter === 'env') {
        return tex;
      }
      if (delimiter === '\\[') {
        return `\\[\n${tex}\n\\]`;
      }
      if (delimiter === 'fence') {
        return `\`\`\`math\n${tex}\n\`\`\``;
      }
      return `$$\n${tex}\n$$`;
    }

    case 'blockquote': {
      const inner = serializeChildren(node, '\n\n');
      return inner
        .split('\n')
        .map((line) => (line.length > 0 ? `> ${line}` : '>'))
        .join('\n');
    }

    case 'callout': {
      const kind = String(node.attrs.calloutType ?? 'note').toUpperCase();
      const inner = serializeChildren(node, '\n\n');
      const bodyLines = inner
        .split('\n')
        .map((line) => (line.length > 0 ? `> ${line}` : '>'));
      return [`> [!${kind}]`, ...bodyLines].join('\n');
    }

    case 'bulletList': {
      const items: string[] = [];
      node.forEach((li) => {
        const inner = serializeListItemChildren(li);
        items.push(indentLines(inner, '  ', '- '));
      });
      return items.join('\n');
    }

    case 'orderedList': {
      const start = Number(node.attrs.start) || 1;
      const items: string[] = [];
      let idx = start;
      node.forEach((li) => {
        const prefix = `${idx}. `;
        const contIndent = ' '.repeat(prefix.length);
        const inner = serializeListItemChildren(li);
        items.push(indentLines(inner, contIndent, prefix));
        idx++;
      });
      return items.join('\n');
    }

    case 'taskList': {
      const items: string[] = [];
      node.forEach((li) => {
        const mark = li.attrs.checked ? '[x]' : '[ ]';
        const inner = serializeListItemChildren(li);
        items.push(indentLines(inner, '  ', `- ${mark} `));
      });
      return items.join('\n');
    }

    case 'table':
      return serializeTable(node);

    default:
      return escapeMarkdownText(node.textContent);
  }
}

function serializeListItemChildren(li: PMNode): string {
  const parts: string[] = [];
  li.forEach((child, _offset, index) => {
    const serialized = serializeBlock(child);
    if (index === 0) {
      parts.push(serialized);
    } else if (
      child.type.name === 'bulletList' ||
      child.type.name === 'orderedList' ||
      child.type.name === 'taskList'
    ) {
      parts.push(`\n${serialized}`);
    } else {
      parts.push(`\n\n${serialized}`);
    }
  });
  return parts.join('');
}

function serializeChildren(parent: PMNode, separator: string): string {
  const blocks: string[] = [];
  parent.forEach((child) => {
    blocks.push(serializeBlock(child));
  });
  return blocks.join(separator);
}

export function docToMarkdown(doc: PMNode): string {
  if (doc.childCount === 1 && doc.firstChild?.type.name === 'paragraph' && doc.firstChild.content.size === 0) {
    return '';
  }
  return serializeChildren(doc, '\n\n') + '\n';
}
