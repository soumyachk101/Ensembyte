export default {
  fetch(request) {
    const url = new URL(request.url);
    url.hostname = "ensembyte.sh";
    return Response.redirect(url.toString(), 301);
  },
};
