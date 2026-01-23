import { buildServer } from "./server.js";

const app = buildServer();

const port = Number(process.env.SERVER_PORT ?? 6969);
const host =
  process.env.SERVER_HOST && process.env.SERVER_HOST.trim() ? process.env.SERVER_HOST : "0.0.0.0";

app
  .listen({ port, host })
  .then(() => {
    app.log.info({ host, port }, "server listening");
  })
  .catch((err) => {
    app.log.error(err);
    process.exit(1);
  });
