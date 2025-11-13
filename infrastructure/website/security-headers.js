function handler(event) {
    var response = event.response;

    // Add security headers
    var headers = response.headers = response.headers || {};

    headers['strict-transport-security'] = {
        value: 'max-age=31536000; includeSubDomains; preload'
    };

    headers['x-content-type-options'] = {
        value: 'nosniff'
    };

    headers['x-frame-options'] = {
        value: 'DENY'
    };

    headers['x-xss-protection'] = {
        value: '1; mode=block'
    };

    headers['referrer-policy'] = {
        value: 'strict-origin-when-cross-origin'
    };

    headers['permissions-policy'] = {
        value: 'camera=(), microphone=(), geolocation=(), interest-cohort=()'
    };

    return response;
}