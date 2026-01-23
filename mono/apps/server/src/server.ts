import { resolve } from "node:path";
import dotenv from "dotenv";
import Fastify from "fastify";

dotenv.config({ path: resolve(process.cwd(), "..", "..", ".env") });

export const buildServer = () => {
  const app = Fastify({
    logger: true
  });

  app.get("/", async () => ({ ok: true }));
  app.get("/health", async () => ({ ok: true }));

  return app;
};
