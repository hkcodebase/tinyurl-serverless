package hk.prj;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import software.amazon.awssdk.utils.StringUtils;

import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class TinyurlHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    private static final String PAGE_404 = "404.html";

    private static final String ALLOWED_POST_ORIGIN = "https://links.hemantkumar.dev";

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> event, Context context) {
        String httpMethod = event.get("httpMethod") instanceof String ? (String) event.get("httpMethod") : "GET";
        String path = event.get("path") instanceof String ? (String) event.get("path") : "/";
        String url = event.get("body") instanceof String ? (String) event.get("body") : "";
        Map<String, String> headers = (Map<String, String>) event.get("headers");
        Map<String, Object> requestContext = (Map<String, Object>) event.get("requestContext");

        String host = headers.get("Host");
        String stage = (String) requestContext.get("stage");

        if (httpMethod == null || path == null) {
            return generateApiResponse(400, getErrorBody("Error: Missing 'httpMethod' or 'path'."));
        }

        try {
            switch (httpMethod) {
                case "POST": {
                    String origin = getHeaderIgnoreCase(headers, "Origin");
                    String referer = getHeaderIgnoreCase(headers, "Referer");

                    if (!isAllowedPostCaller(origin, referer)) {
                        // Explicitly restrict POST usage to your site.
                        return generateApiResponse(
                                403,
                                getErrorBody("Forbidden: POST allowed only from links.hemantkumar.dev"),
                                ALLOWED_POST_ORIGIN
                        );
                    }

                    return handleGenerateShortUrl(url, host + "/" + stage, ALLOWED_POST_ORIGIN);
                }
                case "GET":
                    return handleRedirectToOriginalUrl(path, host + "/" + stage);
                default:
                    return generateApiResponse(405, getErrorBody("Error: Unsupported HTTP method."));
            }
        } catch (Exception e) {
            context.getLogger().log("Error: " + e.getMessage());
            return generateApiResponse(500, getErrorBody("Error: Unable to process the request."));
        }
    }

    private String getErrorBody(String errorMessage) {
        return String.format("{\"error\": \"%s\"}", errorMessage);
    }

    // Accept if Origin matches exactly. If Origin is absent (some non-browser clients),
    // optionally allow only if Referer starts with the allowed origin.
    private boolean isAllowedPostCaller(String origin, String referer) {
        if (ALLOWED_POST_ORIGIN.equals(origin)) return true;
        return StringUtils.isBlank(origin)
                && !StringUtils.isBlank(referer)
                && referer.startsWith(ALLOWED_POST_ORIGIN + "/");
    }

    private String getHeaderIgnoreCase(Map<String, String> headers, String name) {
        if (headers == null || name == null) return null;

        String direct = headers.get(name);
        if (direct != null) return direct;

        // Handle common case where API Gateway normalizes header keys differently
        for (Map.Entry<String, String> e : headers.entrySet()) {
            if (e.getKey() != null && e.getKey().equalsIgnoreCase(name)) {
                return e.getValue();
            }
        }
        return null;
    }

    private Map<String, Object> handleGenerateShortUrl(String url, String host, String allowOrigin) {
        if (url == null || url.isEmpty()) {
            return generateApiResponse(400, getErrorBody("Error: 'url' is missing."), allowOrigin);
        }
        if (isValidUrlFormat(url)) {
            String hash = DynamoDBService.createUrl(url); // Use a hashing function for URL
            String responseBody = String.format("{\"tinyurl\": \"%s\"}", hash);
            return generateApiResponse(200, responseBody, allowOrigin);
        }
        return generateApiResponse(400, getErrorBody("Error: invalid URL - " + url), allowOrigin);
    }

    private Map<String, Object> handleRedirectToOriginalUrl(String path, String host) {
        System.out.println("Redirecting to original URL: " + path);
        String hash = path.substring(path.lastIndexOf('/') + 1); // Extract hash from path
        String redirectUrl = DynamoDBService.getRedirectUrl(hash);

        if (StringUtils.isBlank(redirectUrl)) {
            redirectUrl = String.format("%s/%s?originalUrl=%s%s", host, PAGE_404, host, path);
        }
        Map<String, Object> response = new HashMap<>();
        response.put("statusCode", 302);
        Map<String, String> headers = new HashMap<>();
        headers.put("Location", redirectUrl);
        response.put("headers", headers);
        return response;
    }

    private Map<String, Object> generateApiResponse(int statusCode, String body) {
        return generateApiResponse(statusCode, body, "*");
    }

    private Map<String, Object> generateApiResponse(int statusCode, String body, String allowOrigin) {
        Map<String, Object> response = new HashMap<>();
        response.put("statusCode", statusCode);
        Map<String, String> headers = new HashMap<>();
        headers.put("Content-Type", "application/json");

        // CORS: reflect only the allowed origin for POST responses
        headers.put("Access-Control-Allow-Origin", allowOrigin);
        headers.put("Access-Control-Allow-Methods", "OPTIONS,POST,GET");
        response.put("headers", headers);
        response.put("body", body);
        return response;
    }

    public static boolean isValidUrlFormat(String urlString) {
        String regex = "^(https?|http?)://[-a-zA-Z0-9+&@#/%?=~_|!:,.;]*[-a-zA-Z0-9+&@#/%=~_|]";
        Pattern pattern = Pattern.compile(regex);
        Matcher matcher = pattern.matcher(urlString);
        return matcher.matches();
    }
}
