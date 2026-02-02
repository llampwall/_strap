import { describe, expect, it, vi } from "vitest";
import { runConsolidateTransaction } from "../../../src/commands/consolidate/transaction";

describe("runConsolidateTransaction", () => {
  it("rolls back completed moves in reverse order and skips registry write when move fails", async () => {
    const events: string[] = [];
    const handlers = {
      writeRollbackLogStart: vi.fn(async () => {
        events.push("rollback-log:start");
      }),
      executeMove: vi.fn(async (name: string) => {
        events.push(`move:${name}`);
        if (name === "streamside") {
          throw new Error("copy verification failed for streamside");
        }
      }),
      rollbackMove: vi.fn(async (name: string) => {
        events.push(`rollback:${name}`);
      }),
      writeRollbackLogResult: vi.fn(async (payload: { completed: string[]; failed?: string }) => {
        events.push(`rollback-log:result:${payload.completed.join(",")}:${payload.failed ?? ""}`);
      }),
      writeRegistryBatch: vi.fn(async () => {
        events.push("registry:write");
      }),
      updateChinvexBatch: vi.fn(async () => {
        events.push("chinvex:write");
      }),
    };

    await expect(
      runConsolidateTransaction(
        {
          plans: [
            { name: "chinvex", fromPath: "C:\\Code\\chinvex", toPath: "P:\\software\\chinvex" },
            { name: "streamside", fromPath: "C:\\Code\\streamside", toPath: "P:\\software\\streamside" },
          ],
        },
        handlers,
      ),
    ).rejects.toThrow("copy verification failed for streamside");

    expect(handlers.writeRegistryBatch).not.toHaveBeenCalled();
    expect(handlers.updateChinvexBatch).not.toHaveBeenCalled();
    expect(events).toEqual([
      "rollback-log:start",
      "move:chinvex",
      "move:streamside",
      "rollback:chinvex",
      "rollback-log:result:chinvex:copy verification failed for streamside",
    ]);
  });

  it("rolls back registry if chinvex batch update fails after moves", async () => {
    const handlers = {
      writeRollbackLogStart: vi.fn(async () => undefined),
      executeMove: vi.fn(async () => undefined),
      rollbackMove: vi.fn(async () => undefined),
      writeRollbackLogResult: vi.fn(async () => undefined),
      writeRegistryBatch: vi.fn(async () => undefined),
      restoreRegistryFromBackup: vi.fn(async () => undefined),
      updateChinvexBatch: vi.fn(async () => {
        throw new Error("chinvex context update failed");
      }),
    };

    await expect(
      runConsolidateTransaction(
        {
          plans: [{ name: "chinvex", fromPath: "C:\\Code\\chinvex", toPath: "P:\\software\\chinvex" }],
        },
        handlers,
      ),
    ).rejects.toThrow("chinvex context update failed");

    expect(handlers.writeRegistryBatch).toHaveBeenCalledTimes(1);
    expect(handlers.restoreRegistryFromBackup).toHaveBeenCalledTimes(1);
  });
});
