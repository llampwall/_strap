import dotenv from "dotenv";
import { defineConfig } from "vite";

dotenv.config({ path: "../../.env" });

const uiHost = process.env.UI_HOST && process.env.UI_HOST.trim() ? process.env.UI_HOST : "0.0.0.0";
const uiPort = Number(process.env.UI_PORT ?? 7777);

export default defineConfig({
  server: {
    host: uiHost,
    port: uiPort
  }
});
