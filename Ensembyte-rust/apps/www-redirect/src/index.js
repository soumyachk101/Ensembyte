export default {
  fetch(request) {
    const url = new URL(request.url);
    url.hostname = "orbit.sh";
    return Response.redirect(url.toString(), 301);
  },
};
