import { default as sharedConfig } from "../../eslint.package.mjs";

/** Protocol owns strict Atomic Protocol V2 and nothing downstream. */
export default [
  ...sharedConfig,
  {
    files: ["src/**/*.{ts,tsx}"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: [
                "@motionvideo/motion-runtime",
                "@motionvideo/motion-runtime/*",
              ],
              message: "Protocol must not import Runtime IR.",
            },
            {
              group: [
                "@motionvideo/motion-compiler",
                "@motionvideo/motion-compiler/*",
              ],
              message: "Protocol must not import compiler or renderer packages.",
            },
          ],
        },
      ],
    },
  },
];
