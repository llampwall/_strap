import assert from "node:assert/strict";
import { buildServer } from "../src/server";

const run = async () => {
  const app = buildServer();
  const res = await app.inject({ method: "GET", url: "/health" });

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.json(), { ok: true });
};

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
