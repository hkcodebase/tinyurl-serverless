exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const uri = request.uri;

    console.log("Incoming request URI:", uri);

    const hashRegex = /^\/([a-f0-9]+)$/i;
    const match = uri.match(hashRegex);

    if (match) {
        // __API_BASE_URL__ is replaced at deploy time by the CI workflow
        const redirectUrl = '__API_BASE_URL__' + uri;
        console.log("Redirecting to:", redirectUrl);
        return {
            status: '302',
            statusDescription: 'Found',
            headers: {
                location: [{ key: 'Location', value: redirectUrl }],
            },
        };
    }
    else {
        console.log("No match, forwarding request.");
        return request;
    }
};
