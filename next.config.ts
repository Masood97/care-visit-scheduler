import type { NextConfig } from "next";

// Every page renders the signed-in user's own data (cookies + RLS), so there is nothing
// to cache or prerender: the create-next-app defaults cacheComponents/partialPrefetching
// are left off.
const nextConfig: NextConfig = {
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
