import { describe, expect, it } from "vitest";
import { buildServer } from "../src/server";

describe("smoke", () => {
  it("responds on /health", async () => {
    const app = buildServer();
    const res = await app.inject({ method: "GET", url: "/health" });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
  });
});
