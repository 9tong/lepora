import DOMPurify from 'dompurify';

type MermaidModule = typeof import('mermaid')['default'];

let mermaidInstance: MermaidModule | null = null;
let mermaidPromise: Promise<MermaidModule> | null = null;
let currentDark = false;
let renderSeq = 0;

const svgCache = new Map<string, string>();
const MAX_SVG_CACHE = 200;

function detectIsDark(): boolean {
  const theme = document.body.dataset.theme;
  if (theme === 'dark') return true;
  if (theme === 'light' || theme === 'paper') return false;
  return window.matchMedia('(prefers-color-scheme: dark)').matches;
}

function configureMermaid(m: MermaidModule, dark: boolean): void {
  currentDark = dark;
  m.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    suppressErrorRendering: true,
    theme: dark ? 'dark' : 'neutral',
    fontFamily:
      '-apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif',
    themeVariables: dark
      ? {
          background: 'transparent',
          primaryColor: '#253244',
          primaryTextColor: '#eef2f7',
          primaryBorderColor: '#4c6588',
          lineColor: '#7b92b2',
          secondaryColor: '#1f2937',
          tertiaryColor: '#192230',
          noteBkgColor: '#2a3342',
          noteTextColor: '#e5ebf4',
          edgeLabelBackground: '#1b2029',
        }
      : {
          background: 'transparent',
          primaryColor: '#eef4ff',
          primaryTextColor: '#1c2430',
          primaryBorderColor: '#98b4e3',
          lineColor: '#66758a',
          secondaryColor: '#f5f7fa',
          tertiaryColor: '#ffffff',
          noteBkgColor: '#fff9e6',
          noteTextColor: '#3a3525',
          edgeLabelBackground: '#ffffff',
        },
    flowchart: {
      curve: 'basis',
      htmlLabels: true,
      useMaxWidth: true,
    },
    sequence: {
      useMaxWidth: true,
    },
  });
}

async function loadMermaid(): Promise<MermaidModule> {
  if (mermaidInstance) {
    const dark = detectIsDark();
    if (dark !== currentDark) {
      configureMermaid(mermaidInstance, dark);
    }
    return mermaidInstance;
  }

  if (!mermaidPromise) {
    mermaidPromise = import('mermaid').then((mod) => {
      const m = mod.default;
      configureMermaid(m, detectIsDark());
      mermaidInstance = m;
      return m;
    });
  }
  return mermaidPromise;
}

export function resetMermaidTheme(): void {
  svgCache.clear();
  if (mermaidInstance) {
    configureMermaid(mermaidInstance, detectIsDark());
  }
}

export interface MermaidRenderResult {
  svg?: string;
  error?: string;
}

export async function renderMermaid(code: string): Promise<MermaidRenderResult> {
  const trimmed = code.trim();
  if (!trimmed) {
    return { svg: '' };
  }

  const dark = detectIsDark();
  const cacheKey = `${dark ? 'dark' : 'light'}:${trimmed}`;
  const cached = svgCache.get(cacheKey);
  if (cached) {
    return { svg: cached };
  }

  try {
    const m = await loadMermaid();
    const id = `lepora-mermaid-${++renderSeq}`;
    const { svg } = await m.render(id, trimmed);
    const sanitized = DOMPurify.sanitize(svg, {
      USE_PROFILES: { svg: true, svgFilters: true, html: true },
      ADD_TAGS: ['foreignObject'],
      ADD_ATTR: ['dominant-baseline', 'text-anchor', 'marker-end', 'marker-start'],
    });

    if (svgCache.size >= MAX_SVG_CACHE) {
      const first = svgCache.keys().next().value;
      if (first !== undefined) svgCache.delete(first);
    }
    svgCache.set(cacheKey, sanitized);
    return { svg: sanitized };
  } catch (err) {
    // Clean up any leftover error DOM node created by mermaid
    document.querySelectorAll('[id^="dlepora-mermaid-"]').forEach((el) => el.remove());
    const message = err instanceof Error ? err.message : String(err);
    return { error: message };
  }
}
