import { resolve } from "node:path";
import dotenv from "dotenv";
import { buildServer } from "./server";

dotenv.config({ path: resolve(process.cwd(), ".env") });

const port = Number(process.env.SERVER_PORT ?? process.env.PORT ?? 6969);
const host =
  process.env.SERVER_HOST && process.env.SERVER_HOST.trim()
    ? process.env.SERVER_HOST
    : process.env.HOST && process.env.HOST.trim()
      ? process.env.HOST
      : "0.0.0.0";

const app = buildServer();

app.listen({ port, host }).catch((err) => {
  app.log.error(err);
  process.exit(1);
});
