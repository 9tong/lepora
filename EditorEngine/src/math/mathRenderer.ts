import katex from 'katex';
import 'katex/contrib/mhchem';

export type MathEngineMode = 'auto' | 'katex' | 'mathjax';

export interface MathRenderResult {
  html: string;
  engine: 'katex' | 'mathjax' | 'error';
  pending?: boolean;
  errorMessage?: string;
}

interface MathJaxRuntime {
  render: (tex: string, display: boolean) => string;
}

const MAX_CACHE_ENTRIES = 1000;
const renderCache = new Map<string, MathRenderResult>();

let engineMode: MathEngineMode = 'auto';
let mathJaxRuntime: MathJaxRuntime | null = null;
let mathJaxPromise: Promise<MathJaxRuntime> | null = null;
const mathJaxListeners = new Set<() => void>();

// Shared document-level TeX macros (supports \newcommand / \def across formulas)
const sharedMacros: Record<string, string> = {
  '\\RR': '\\mathbb{R}',
  '\\NN': '\\mathbb{N}',
  '\\ZZ': '\\mathbb{Z}',
  '\\QQ': '\\mathbb{Q}',
  '\\CC': '\\mathbb{C}',
  '\\EE': '\\mathbb{E}',
  '\\PP': '\\mathbb{P}',
};

// Environments or macros that KaTeX does not natively support (or supports partially)
// so Auto mode routes them straight to MathJax for full AMS fidelity.
const MATHJAX_PREFERRED_REGEX =
  /\\begin\{(eqnarray\*?|multline\*?|flalign\*?|alignat\*?|subequations|tikzcd|xalignat\*?|xxalignat)\}|\\(DeclareMathOperator|label|ref|eqref|operatornamewithlimits|xymatrix|sideset)\b/;

export function setMathEngineMode(mode: MathEngineMode): void {
  if (engineMode === mode) return;
  engineMode = mode;
  renderCache.clear();
}

export function getMathEngineMode(): MathEngineMode {
  return engineMode;
}

export function clearMathCache(): void {
  renderCache.clear();
}

export function onMathJaxReady(listener: () => void): () => void {
  mathJaxListeners.add(listener);
  return () => mathJaxListeners.delete(listener);
}

async function ensureMathJaxLoaded(): Promise<MathJaxRuntime> {
  if (mathJaxRuntime) return mathJaxRuntime;
  if (!mathJaxPromise) {
    mathJaxPromise = (async () => {
      const [
        { mathjax },
        { TeX },
        { SVG },
        { liteAdaptor },
        { RegisterHTMLHandler },
        { AllPackages },
      ] = await Promise.all([
        import('mathjax-full/js/mathjax.js'),
        import('mathjax-full/js/input/tex.js'),
        import('mathjax-full/js/output/svg.js'),
        import('mathjax-full/js/adaptors/liteAdaptor.js'),
        import('mathjax-full/js/handlers/html.js'),
        import('mathjax-full/js/input/tex/AllPackages.js'),
      ]);

      const adaptor = liteAdaptor();
      RegisterHTMLHandler(adaptor);

      const tex = new TeX({
        packages: AllPackages,
        tags: 'ams',
        inlineMath: [
          ['$', '$'],
          ['\\(', '\\)'],
        ],
        displayMath: [
          ['$$', '$$'],
          ['\\[', '\\]'],
        ],
        macros: {
          RR: '\\mathbb{R}',
          NN: '\\mathbb{N}',
          ZZ: '\\mathbb{Z}',
          QQ: '\\mathbb{Q}',
          CC: '\\mathbb{C}',
          EE: '\\mathbb{E}',
          PP: '\\mathbb{P}',
        },
      });

      const svg = new SVG({
        fontCache: 'none',
      });

      const htmlDoc = mathjax.document('', {
        InputJax: tex,
        OutputJax: svg,
      });

      const runtime: MathJaxRuntime = {
        render(source: string, display: boolean): string {
          const node = htmlDoc.convert(source, {
            display,
            em: 16,
            ex: 8,
            containerWidth: 80 * 16,
          });
          return adaptor.outerHTML(node);
        },
      };

      mathJaxRuntime = runtime;
      renderCache.clear();
      for (const fn of mathJaxListeners) {
        try {
          fn();
        } catch {
          // ignore listener errors
        }
      }
      return runtime;
    })();
  }
  return mathJaxPromise;
}

function setCached(key: string, result: MathRenderResult): MathRenderResult {
  if (renderCache.size >= MAX_CACHE_ENTRIES) {
    const firstKey = renderCache.keys().next().value;
    if (firstKey !== undefined) {
      renderCache.delete(firstKey);
    }
  }
  renderCache.set(key, result);
  return result;
}

function renderWithKaTeX(tex: string, displayMode: boolean): string {
  // Clone macros map slightly so global \gdef persists while avoiding mutation surprises
  return katex.renderToString(tex, {
    displayMode,
    throwOnError: true,
    strict: false,
    trust: true,
    macros: sharedMacros,
    maxExpand: 1000,
    fleqn: false,
    output: 'htmlAndMathml',
  });
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * Renders a LaTeX expression synchronously using KaTeX (primary) or offline MathJax 3 SVG
 * (automatic fallback for unsupported LaTeX environments/macros or explicit MathJax mode).
 */
export function renderLatex(tex: string, displayMode: boolean): MathRenderResult {
  const trimmed = tex.trim();
  if (!trimmed) {
    return {
      html: `<span class="math-placeholder">${displayMode ? '输入 LaTeX 公式…' : '公式'}</span>`,
      engine: 'katex',
    };
  }

  const cacheKey = `${engineMode}:${displayMode ? 'D' : 'I'}:${trimmed}`;
  const cached = renderCache.get(cacheKey);
  if (cached) return cached;

  const shouldPreferMathJax =
    engineMode === 'mathjax' ||
    (engineMode === 'auto' && MATHJAX_PREFERRED_REGEX.test(trimmed));

  // Try KaTeX first when appropriate
  if (!shouldPreferMathJax) {
    try {
      const html = renderWithKaTeX(trimmed, displayMode);
      return setCached(cacheKey, { html, engine: 'katex' });
    } catch (katexErr) {
      if (engineMode === 'katex') {
        const msg = katexErr instanceof Error ? katexErr.message : String(katexErr);
        return {
          html: `<span class="math-error" title="${escapeHtml(msg)}">${escapeHtml(trimmed)}</span>`,
          engine: 'error',
          errorMessage: msg,
        };
      }
      // Fall through to MathJax in 'auto' mode!
    }
  }

  // MathJax path (either explicitly chosen or automatic fallback)
  if (mathJaxRuntime) {
    try {
      const html = mathJaxRuntime.render(trimmed, displayMode);
      return setCached(cacheKey, { html, engine: 'mathjax' });
    } catch (mjErr) {
      const msg = mjErr instanceof Error ? mjErr.message : String(mjErr);
      return {
        html: `<span class="math-error" title="${escapeHtml(msg)}">${escapeHtml(trimmed)}</span>`,
        engine: 'error',
        errorMessage: msg,
      };
    }
  }

  // Trigger async lazy load of MathJax and show lightweight placeholder until ready
  void ensureMathJaxLoaded();
  return {
    html: `<span class="math-loading">正在渲染公式…</span>`,
    engine: 'mathjax',
    pending: true,
  };
}

/**
 * Preloads MathJax in the background if a document contains advanced LaTeX environments.
 */
export function preloadMathJaxIfNeeded(markdown: string): void {
  if (engineMode === 'mathjax' || MATHJAX_PREFERRED_REGEX.test(markdown)) {
    void ensureMathJaxLoaded();
  }
}
