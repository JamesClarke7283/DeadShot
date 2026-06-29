// Typed barrel for Three.js.
//
// three@0.180.0 ships no TypeScript declarations, so we attach @types/three via
// the @ts-types directive here and re-export. Every module imports THREE from
// this barrel (`import * as THREE from "../three.ts"`) to get full typing while
// the runtime still uses the npm three. esbuild ignores the comment and bundles
// the real module.

// @ts-types="npm:@types/three@0.180.0"
export * from "three";
