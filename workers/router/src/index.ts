interface Env {
  ORIGIN_ONE_HOST: string;
  ORIGIN_TWO_HOST: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/page\/(\d+)$/);
    const page_str = match?.[1];

    if (!page_str) {
      return new Response("Not Found", { status: 404 });
    }

    const page_number = parseInt(page_str, 10);
    if (page_number === 0) {
      return new Response("Not Found", { status: 404 });
    }

    const origin_host = page_number % 2 !== 0 ? env.ORIGIN_ONE_HOST : env.ORIGIN_TWO_HOST;

    const origin_url = new URL(url.pathname, `https://${origin_host}`);
    const headers = new Headers(request.headers);
    headers.set("x-forwarded-host", url.hostname);

    const client_ip = request.headers.get("CF-Connecting-IP");
    if (client_ip) {
      headers.set("X-Real-IP", client_ip);
      headers.set("X-Forwarded-For", client_ip);
    }

    return fetch(origin_url.toString(), {
      method: request.method,
      headers,
    });
  },
} satisfies ExportedHandler<Env>;
