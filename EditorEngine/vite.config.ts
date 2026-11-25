import { defineConfig } from 'vite';
import path from 'node:path';

export default defineConfig({
  base: './',
  build: {
    target: 'esnext',
    outDir: path.resolve(__dirname, '../Lepora/Resources/EditorBundle'),
    emptyOutDir: true,
    sourcemap: false,
    cssCodeSplit: false,
    assetsInlineLimit: 0,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules/mathjax-full')) return 'mathjax';
          if (id.includes('node_modules/mermaid') || id.includes('node_modules/cytoscape') || id.includes('node_modules/d3')) {
            return 'mermaid';
          }
          if (id.includes('node_modules/@codemirror') || id.includes('node_modules/codemirror') || id.includes('node_modules/@lezer')) {
            return 'codemirror';
          }
          if (id.includes('node_modules/katex')) return 'katex';
          if (id.includes('node_modules/@tiptap') || id.includes('node_modules/prosemirror')) {
            return 'tiptap';
          }
          return undefined;
        },
      },
    },
  },
});
