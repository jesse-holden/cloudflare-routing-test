const SERVER_NAME = "origin-two";

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/page\/(\d+)$/);

    if (!match) {
      return new Response("Not Found", { status: 404 });
    }

    const page_number = parseInt(match[1], 10);
    if (page_number === 0) {
      return new Response("Not Found", { status: 404 });
    }

    const request_id = crypto.randomUUID();
    return new Response(`Hello from ${SERVER_NAME}, request-id: ${request_id}`);
  },
} satisfies ExportedHandler;
