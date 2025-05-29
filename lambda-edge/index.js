exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const uri = request.uri;

    console.log("Incoming request URI:", uri);

    const hashRegex = /^\/([a-f0-9]+)$/i;
    const match = uri.match(hashRegex);

    if (match) {
        const redirectUrl = 'REPLACE_ME' + uri;
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
