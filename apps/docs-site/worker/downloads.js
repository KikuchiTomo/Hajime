// 配布物(/download/ の下)を R2 から配る．ほかのページは静的アセットのまま Worker を通らない(wrangler.jsonc の run_worker_first)．
//
//   /download/v0.1.13/Hajime-0.1.13.msi  そのバージョンの配布物．あとから中身を変えない(Microsoft Store はこの URL を登録する)
//   /download/macos・/download/windows   最新のバージョンの配布物へ転送する．R2 にまだ無ければ DOWNLOADS_FALLBACK(wrangler.jsonc)へ転送する
//
// R2 には tools/release/upload_downloads.sh が置く．最新のバージョンは latest.json に書く:
//   { "version": "0.1.13", "files": { "macos": "v0.1.13/Hajime-0.1.13.pkg", "windows": "v0.1.13/Hajime-0.1.13.msi" } }

const PREFIX = "/download/";
const LATEST = "latest.json";
// バージョンのフォルダの下のファイルだけを配る(latest.json などほかのキーは出さない)
const VERSIONED = /^v\d+\.\d+\.\d+\/[A-Za-z0-9][A-Za-z0-9._-]*$/;

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (!path.startsWith(PREFIX)) {
      return notFound();
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    const key = path.slice(PREFIX.length);
    if (VERSIONED.test(key)) {
      return serve(request, env.DOWNLOADS, key);
    }
    return redirectToLatest(env, key, request.url);
  },
};

async function redirectToLatest(env, platform, base) {
  const latest = await env.DOWNLOADS.get(LATEST);
  if (latest === null) {
    // まだ一度も R2 に置いていない
    return redirect(env.DOWNLOADS_FALLBACK);
  }
  const files = (await latest.json()).files ?? {};
  const key = Object.hasOwn(files, platform) ? files[platform] : null;
  if (typeof key !== "string" || !VERSIONED.test(key)) {
    return notFound();
  }
  return redirect(new URL(PREFIX + key, base).toString());
}

function redirect(location) {
  // 新しいバージョンを出したらすぐ切り替わるよう，転送は覚えさせない
  return new Response(null, { status: 302, headers: { Location: location, "Cache-Control": "no-store" } });
}

async function serve(request, bucket, key) {
  const head = request.method === "HEAD";
  const object = head
    ? await bucket.head(key)
    : await bucket.get(key, { range: request.headers, onlyIf: request.headers });
  if (object === null) {
    return notFound();
  }
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("ETag", object.httpEtag);
  headers.set("Accept-Ranges", "bytes");
  // バージョンの URL の中身は変えないので，ずっと覚えてよい
  headers.set("Cache-Control", "public, max-age=31536000, immutable");
  headers.set("Content-Disposition", `attachment; filename="${key.slice(key.lastIndexOf("/") + 1)}"`);
  // onlyIf の条件に合わなければ本文が無い(If-None-Match が合った，など)
  if (!head && !("body" in object)) {
    return new Response(null, { status: request.headers.has("If-None-Match") ? 304 : 412, headers });
  }
  if (head) {
    headers.set("Content-Length", String(object.size));
    return new Response(null, { headers });
  }
  const range = object.range;
  if (range && request.headers.has("Range")) {
    const offset = range.offset ?? object.size - range.suffix;
    const length = range.length ?? object.size - offset;
    headers.set("Content-Range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("Content-Length", String(length));
    return new Response(object.body, { status: 206, headers });
  }
  headers.set("Content-Length", String(object.size));
  return new Response(object.body, { headers });
}

function notFound() {
  return new Response("Not Found", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
