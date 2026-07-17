import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

function inlineApplication(): Plugin {
  let outputDirectory = "";
  return {
    name: "inline-application",
    enforce: "post",
    configResolved(config) {
      outputDirectory = resolve(config.root, config.build.outDir);
    },
    generateBundle(_options, bundle) {
      const htmlAsset = Object.values(bundle).find(
        (item) => item.type === "asset" && item.fileName === "index.html",
      );
      if (!htmlAsset || htmlAsset.type !== "asset") return;
      let html = String(htmlAsset.source);

      for (const [fileName, item] of Object.entries(bundle)) {
        if (item.type === "chunk" && item.isEntry) {
          const escapedCode = item.code.replaceAll("</script", "</scr\\x69pt");
          html = html.replace(
            new RegExp(`<script[^>]+src=["'][^"']*${fileName.replaceAll("/", "\\/")}["'][^>]*><\\/script>`),
            "",
          );
          html = html.replace(
            "</body>",
            () => `<script id="vibevoice-oss-bundle" type="text/plain">${escapedCode}</script><!--ENTRY_END--></body>`,
          );
          delete bundle[fileName];
        } else if (item.type === "asset" && fileName.endsWith(".css")) {
          html = html.replace(
            new RegExp(`<link[^>]+href=["'][^"']*${fileName.replaceAll("/", "\\/")}["'][^>]*>`),
            () => `<style>${String(item.source)}</style>`,
          );
          delete bundle[fileName];
        }
      }
      htmlAsset.source = html;
    },
    closeBundle() {
      const indexPath = resolve(outputDirectory, "index.html");
      const html = readFileSync(indexPath, "utf8")
        .replace("</script><!--ENTRY_END-->", "__ENTRY_CLOSE__")
        .replaceAll("</script>", "</scr\\x69pt>")
        .replace("__ENTRY_CLOSE__", "</script>");
      writeFileSync(indexPath, html);
    },
  };
}

export default defineConfig({
  base: "./",
  plugins: [react(), inlineApplication()],
});
