import { timeout } from "./utils";

// Direct only: this fork does not route release metadata (which carries the
// update download URLs) through upstream's proxy. An unreachable GitHub must
// not block startup; callers treat a rejected api() as "update check failed".
const API_TIMEOUT_MS = 10000;

export async function createGithubEndpoint() {
  function api(path: `/${string}`): Promise<unknown> {
    return Promise.race([
      fetch(`https://api.github.com${path}`).then(x => {
        if (x.status == 200 || x.status == 301 || x.status == 302) {
          return x.json();
        }
        return Promise.reject(
          new Error(`Request failed: ${x.status} ${x.statusText} (${x.url})`)
        );
      }),
      timeout(API_TIMEOUT_MS),
    ]);
  }

  return {
    api,
  };
}

export type Github = ReturnType<typeof createGithubEndpoint> extends Promise<
  infer T
>
  ? T
  : never;

export interface GithubReleaseInfo {
  url: string;
  html_url: string;
  assets_url: string;
  id: number;
  tag_name: string;
  name: string;
  body: string;
  draft: boolean;
  prerelease: boolean;
  created_at: string;
  published_at: string;
  author: unknown;
  assets: GithubReleaseAssetsInfo[];
}

export interface GithubReleaseAssetsInfo {
  url: string;
  browser_download_url: string;
  id: number;
  name: string;
  content_type: string;
}

export type GithubReleases = GithubReleaseInfo[];
