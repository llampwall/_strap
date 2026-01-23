import Fastify from "fastify";

export const buildServer = () => {
  const app = Fastify({
    logger: true
  });

  app.get("/", async () => ({ ok: true }));
  app.get("/health", async () => ({ ok: true }));

  return app;
};
