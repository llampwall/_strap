export const log = (...args: unknown[]) => {
  console.log("[app]", ...args);
};

export const info = (...args: unknown[]) => {
  console.info("[app]", ...args);
};

export const warn = (...args: unknown[]) => {
  console.warn("[app]", ...args);
};

export const error = (...args: unknown[]) => {
  console.error("[app]", ...args);
};