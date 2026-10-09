export const config = {
  pattern: "^/([0-9a-f]{6}/?)?$",
};

export default (request, context) => {
  const accept = request.headers.get("accept") ?? "";
  const agent = request.headers.get("user-agent") ?? "";
  const { ip } = context;
  const url = new URL(request.url);

  console.log(JSON.stringify({ accept, agent, ip, path: url.pathname }));

  if (/\btext\/html\b/.test(accept) || /bot|compatible|google/i.test(agent)) {
    return;
  }

  url.pathname = url.pathname.replace(/\/?$/, "/brat.sh");
  return url;
};
