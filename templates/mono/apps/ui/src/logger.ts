export const log = (...args: unknown[]) => {
  console.log("[ui]", ...args);
};

export const info = (...args: unknown[]) => {
  console.info("[ui]", ...args);
};

export const warn = (...args: unknown[]) => {
  console.warn("[ui]", ...args);
};

export const error = (...args: unknown[]) => {
  console.error("[ui]", ...args);
};