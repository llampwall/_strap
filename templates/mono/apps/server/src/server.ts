import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import Fastify from "fastify";
import pino from "pino";

const createLogger = () => {
  const logsDir = resolve(process.cwd(), "..", "..", "logs");
  mkdirSync(logsDir, { recursive: true });
  const logPath = resolve(logsDir, "server.log");

  return pino({}, pino.destination({ dest: logPath, sync: false }));
};

export const buildServer = () => {
  const app = Fastify({
    logger: createLogger()
  });

  app.get("/", async () => ({ ok: true }));
  app.get("/health", async () => ({ ok: true }));

  return app;
};