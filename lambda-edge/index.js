exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const uri = request.uri;

    console.log("Incoming request URI:", uri);

    // ── Passthrough routes — serve directly from S3 ──────────────────────────
    // These must not be treated as short URL hashes.
    // Rewrite clean paths to their HTML files
    const rewrites = {
      '/admin':    '/admin.html',
      '/callback': '/index.html',  // callback handled by JS in index.html
    };
    if (rewrites[uri]) {
        request.uri = rewrites[uri];
        console.log("Rewriting", uri, "→", request.uri);
        return request;
    }

    // Static assets and root — pass through as-is
    if (uri === '/' || uri.includes('.')) {
        console.log("Passthrough, forwarding request:", uri);
        return request;
    }

    // ── Short URL hash — redirect to API ─────────────────────────────────────
    // Matches any path segment e.g. /x7k2p /aB3dEf
    const hashRegex = /^\/([a-zA-Z0-9]+)$/;
    const match = uri.match(hashRegex);

    if (match) {
        // __API_BASE_URL__ is replaced at deploy time by the CI workflow
        const redirectUrl = '__API_BASE_URL__' + uri;
        console.log("Redirecting to API:", redirectUrl);
        return {
            status: '302',
            statusDescription: 'Found',
            headers: {
                location: [{ key: 'Location', value: redirectUrl }],
            },
        };
    }

    // ── Fallback — forward to S3 ──────────────────────────────────────────────
    console.log("No match, forwarding request:", uri);
    return request;
};
