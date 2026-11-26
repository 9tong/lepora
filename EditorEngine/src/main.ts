import './styles/editor.css';
import { LeporaWysiwygEditor } from './editor/wysiwygEditor';
import type { SourceEditorController } from './editor/sourceEditor';
import { setImageUrlResolver, setRevealImageHandler } from './editor/extensions';
import { setMathEngineMode, type MathEngineMode } from './math/mathRenderer';
import { resetMermaidTheme } from './mermaid/mermaidRenderer';

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        lepora?: {
          postMessage: (payload: unknown) => void;
        };
      };
    };
    LeporaBridge?: LeporaBridgeAPI;
  }
}

interface EditorPreferences {
  theme: 'system' | 'light' | 'dark' | 'paper' | 'translucent';
  fontSize: number;
  lineHeight: number;
  maxWidth: number;
  mathEngine: MathEngineMode;
  focusMode: boolean;
  typewriterMode: boolean;
}

interface LeporaBridgeAPI {
  loadDocument: (markdown: string, baseDirPath: string) => void;
  setMode: (mode: 'wysiwyg' | 'source') => Promise<void>;
  getMarkdown: () => string;
  applyPreferences: (prefs: Partial<EditorPreferences>) => void;
  insertImage: (relativePath: string, alt?: string) => void;
  execCommand: (cmd: string, arg?: string) => void;
  scrollToPos: (pos: number) => void;
  find: (query: string, caseSensitive: boolean, direction?: 'current' | 'next' | 'prev') => { count: number; current: number };
  replaceCurrent: (query: string, replacement: string) => { count: number; current: number };
  replaceAll: (query: string, replacement: string) => { count: number; current: number };
  clearFind: () => void;
  getExportData: () => { html: string; css: string };
}

function postToSwift(payload: Record<string, unknown>): void {
  try {
    window.webkit?.messageHandlers?.lepora?.postMessage(payload);
  } catch {
    // Running outside WKWebView (e.g., Vite dev preview)
  }
}

let currentMode: 'wysiwyg' | 'source' = 'wysiwyg';
let currentBaseDir = '';
let latestMarkdown = '';
let sourceEditor: SourceEditorController | null = null;
let sourceSyncTimer: number | undefined;

const wysiwygHost = document.getElementById('wysiwyg-host')!;
const sourceHost = document.getElementById('source-host')!;

// Resolve local/relative image paths through Swift's custom lepora-local:// scheme
setImageUrlResolver((rawSrc: string) => {
  const trimmed = rawSrc.trim();
  if (!trimmed) return '';
  if (/^(https?:|data:|blob:|lepora-local:|lepora-app:)/i.test(trimmed)) {
    return trimmed;
  }
  const encodedSrc = encodeURIComponent(trimmed);
  const encodedBase = encodeURIComponent(currentBaseDir);
  return `lepora-local://asset?path=${encodedSrc}&base=${encodedBase}`;
});

setRevealImageHandler((rawSrc: string) => {
  postToSwift({
    type: 'revealImage',
    src: rawSrc,
  });
});

const wysiwyg = new LeporaWysiwygEditor(wysiwygHost, {
  onMarkdownChange: (markdown) => {
    latestMarkdown = markdown;
    postToSwift({ type: 'contentChanged', markdown });
  },
  onStatsChange: (stats) => {
    postToSwift({ type: 'statsChanged', stats });
  },
  onOutlineChange: (outline) => {
    postToSwift({ type: 'outlineChanged', outline });
  },
  onActiveHeadingChange: (headingId) => {
    postToSwift({ type: 'activeHeadingChanged', headingId });
  },
  onTypingActivity: () => {
    postToSwift({ type: 'typingActivity' });
  },
});

async function ensureSourceEditor(): Promise<SourceEditorController> {
  if (sourceEditor) return sourceEditor;
  const { createSourceEditor } = await import('./editor/sourceEditor');
  sourceEditor = createSourceEditor(sourceHost, latestMarkdown, (text) => {
    latestMarkdown = text;
    postToSwift({ type: 'typingActivity' });
    window.clearTimeout(sourceSyncTimer);
    sourceSyncTimer = window.setTimeout(() => {
      postToSwift({ type: 'contentChanged', markdown: text });
    }, 100);
  });
  return sourceEditor;
}

// React to macOS system appearance changes dynamically (required by dark-mode guidance!)
const darkMedia = window.matchMedia('(prefers-color-scheme: dark)');
darkMedia.addEventListener('change', () => {
  const activeTheme = document.documentElement.dataset.theme || document.body.dataset.theme;
  if (activeTheme === 'system' || activeTheme === 'translucent') {
    resetMermaidTheme();
    window.dispatchEvent(new Event('lepora-theme-changed'));
  }
});

// Intercept clipboard paste with image data inside WebView and route to Swift ImageAssetManager
document.addEventListener('paste', (event) => {
  const items = event.clipboardData?.items;
  if (!items) return;

  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (item.kind === 'file' && item.type.startsWith('image/')) {
      event.preventDefault();
      const file = item.getAsFile();
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        const result = typeof reader.result === 'string' ? reader.result : '';
        const comma = result.indexOf(',');
        const base64 = comma >= 0 ? result.slice(comma + 1) : '';
        if (base64) {
          postToSwift({
            type: 'pastedImageData',
            base64,
            mimeType: file.type,
            fileName: file.name || 'image.png',
          });
        }
      };
      reader.readAsDataURL(file);
      return;
    }
  }
});

function collectInlineStylesForExport(): string {
  const chunks: string[] = [];
  for (const sheet of Array.from(document.styleSheets)) {
    try {
      const rules = Array.from(sheet.cssRules).map((r) => r.cssText);
      chunks.push(rules.join('\n'));
    } catch {
      // skip cross-origin stylesheet if any
    }
  }
  return chunks.join('\n');
}

const bridge: LeporaBridgeAPI = {
  loadDocument(markdown: string, baseDirPath: string) {
    currentBaseDir = baseDirPath || '';
    latestMarkdown = markdown;
    try {
      wysiwyg.setMarkdown(markdown);
    } catch {
      // Fallback: never fail silently on exotic Markdown syntax
      wysiwyg.editor.commands.setContent(markdown, false);
    }
    wysiwygHost.scrollTop = 0;
    if (sourceEditor) {
      sourceEditor.setValue(markdown);
      sourceEditor.scrollToRatio(0);
    }
  },

  async setMode(mode: 'wysiwyg' | 'source') {
    if (currentMode === mode) return;
    if (mode === 'source') {
      const ratio = wysiwyg.getScrollRatio();
      latestMarkdown = wysiwyg.getMarkdown();
      const src = await ensureSourceEditor();
      src.setValue(latestMarkdown);
      wysiwygHost.hidden = true;
      sourceHost.hidden = false;
      currentMode = 'source';
      requestAnimationFrame(() => {
        src.scrollToRatio(ratio);
        src.focus();
      });
    } else {
      const ratio = sourceEditor?.getScrollRatio() ?? 0;
      if (sourceEditor) {
        latestMarkdown = sourceEditor.getValue();
      }
      wysiwyg.setMarkdown(latestMarkdown);
      sourceHost.hidden = true;
      wysiwygHost.hidden = false;
      currentMode = 'wysiwyg';
      requestAnimationFrame(() => {
        wysiwyg.scrollToRatio(ratio);
        wysiwyg.editor.view.focus();
      });
    }
    postToSwift({ type: 'modeChanged', mode: currentMode });
  },

  getMarkdown() {
    if (currentMode === 'source' && sourceEditor) {
      latestMarkdown = sourceEditor.getValue();
    } else {
      latestMarkdown = wysiwyg.getMarkdown();
    }
    return latestMarkdown;
  },

  applyPreferences(prefs: Partial<EditorPreferences>) {
    const root = document.documentElement;
    let shouldRefreshTheme = false;
    let shouldRefreshMath = false;

    if (prefs.theme && (root.dataset.theme !== prefs.theme || document.body.dataset.theme !== prefs.theme)) {
      root.dataset.theme = prefs.theme;
      document.body.dataset.theme = prefs.theme;
      shouldRefreshTheme = true;
    }
    if (typeof prefs.fontSize === 'number') {
      root.style.setProperty('--editor-font-size', `${prefs.fontSize}px`);
    }
    if (typeof prefs.lineHeight === 'number') {
      root.style.setProperty('--editor-line-height', String(prefs.lineHeight));
    }
    if (typeof prefs.maxWidth === 'number') {
      root.style.setProperty('--editor-max-width', `${prefs.maxWidth}px`);
    }
    if (prefs.mathEngine) {
      setMathEngineMode(prefs.mathEngine);
      shouldRefreshMath = true;
    }
    if (typeof prefs.focusMode === 'boolean') {
      wysiwyg.setFocusMode(prefs.focusMode);
    }
    if (typeof prefs.typewriterMode === 'boolean') {
      wysiwyg.setTypewriterMode(prefs.typewriterMode);
    }

    if (shouldRefreshTheme) {
      resetMermaidTheme();
      window.dispatchEvent(new Event('lepora-theme-changed'));
    }
    if (shouldRefreshMath && currentMode === 'wysiwyg') {
      wysiwyg.refreshAllMathAndDiagrams();
    }
  },

  insertImage(relativePath: string, alt = '') {
    if (currentMode === 'source' && sourceEditor) {
      sourceEditor.insertText(`![${alt}](${relativePath})`);
    } else {
      wysiwyg.insertImage(relativePath, alt);
    }
  },

  execCommand(cmd: string, arg?: string) {
    if (currentMode === 'source') return;
    wysiwyg.executeFormatCommand(cmd, arg);
  },

  scrollToPos(pos: number) {
    if (currentMode === 'wysiwyg') {
      wysiwyg.scrollToPos(pos);
    }
  },

  find(query: string, caseSensitive: boolean, direction: 'current' | 'next' | 'prev' = 'current') {
    if (currentMode === 'source' && sourceEditor) {
      return sourceEditor.findNext(query, direction === 'prev');
    }
    return wysiwyg.search(query, caseSensitive, direction);
  },

  replaceCurrent(query: string, replacement: string) {
    if (currentMode === 'source' && sourceEditor) {
      sourceEditor.replaceCurrent(query, replacement);
      return sourceEditor.findNext(query, false);
    }
    return wysiwyg.replaceCurrent(replacement);
  },

  replaceAll(query: string, replacement: string) {
    if (currentMode === 'source' && sourceEditor) {
      sourceEditor.replaceAll(query, replacement);
      return { count: 0, current: 0 };
    }
    return wysiwyg.replaceAll(replacement);
  },

  clearFind() {
    wysiwyg.clearSearch();
  },

  getExportData() {
    if (currentMode === 'source' && sourceEditor) {
      // Ensure WYSIWYG DOM is up-to-date for export
      wysiwyg.setMarkdown(sourceEditor.getValue());
    }
    return {
      html: wysiwyg.getExportHTMLSnapshot(),
      css: collectInlineStylesForExport(),
    };
  },
};

window.LeporaBridge = bridge;

// Signal Swift host that the offline editor bundle is fully mounted and ready
postToSwift({ type: 'ready' });
