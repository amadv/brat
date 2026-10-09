export const config = {
  pattern: "^/([0-9a-f]{6}/?)?$",
  cache: "manual",
};

export default async (request, context) => {
  const accept = request.headers.get("accept") ?? "";
  if (!/\btext\/html\b/.test(accept)) {
    return;
  }

  const url = new URL(request.url);
  if (url.hostname != "brat.sh" && !url.hostname.endsWith(".netlify.app")) {
    return;
  }

  const response = await context.next();
  if (!response.ok) {
    return response;
  }

  const html = await response.text();
  const page = new Response(
    html.replace(
      "</head>",
      `  <script src="https://cdn.usefathom.com/script.js" data-site="JUKLUVDG" defer></script>\n  </head>`,
    ),
    response,
  );
  page.headers.set("Netlify-CDN-Cache-Control", "public, s-maxage=31536000");
  return page;
};
