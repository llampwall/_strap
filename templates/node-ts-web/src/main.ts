import { info } from "./logger";

const root = document.querySelector("#app");

if (root) {
  root.innerHTML = `<main style="font-family: system-ui, sans-serif; padding: 2rem;">
    <h1>{{REPO_NAME}}</h1>
    <p>Vite + TypeScript starter.</p>
  </main>`;
}

info("ui booted");