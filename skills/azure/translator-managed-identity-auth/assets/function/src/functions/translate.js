const { app } = require('@azure/functions');
const { DefaultAzureCredential } = require('@azure/identity');

// SFI-durable translation proxy. A client-side app (e.g. an Omnichannel real-time
// translation web resource) calls this function instead of calling Azure Translator
// directly, so no Translator key lives in the browser. The function authenticates to
// Translator with its managed identity (Microsoft Entra ID) and transparently forwards
// the v3 translate call, returning Translator's raw response verbatim.
//
// App settings (no secrets):
//   TRANSLATOR_ENDPOINT   = https://<subdomain>.cognitiveservices.azure.com/translator/text/v3.0
//   TRANSLATOR_RESOURCE_ID= /subscriptions/.../accounts/<name>/   (only used on the global endpoint)
//   TRANSLATOR_REGION     = optional; omit for a global resource / custom-domain endpoint

const TRANSLATOR_ENDPOINT = (process.env.TRANSLATOR_ENDPOINT || 'https://api.cognitive.microsofttranslator.com').replace(/\/+$/, '');
const TRANSLATOR_RESOURCE_ID = process.env.TRANSLATOR_RESOURCE_ID;
const TRANSLATOR_REGION = process.env.TRANSLATOR_REGION;
const SCOPE = 'https://cognitiveservices.azure.com/.default';

const credential = new DefaultAzureCredential();

// In-process token cache (Entra tokens are valid ~10 min; reuse them).
let cachedToken = null;
let cachedExpiry = 0;
async function getToken() {
    const now = Date.now();
    if (cachedToken && now < cachedExpiry - 60_000) return cachedToken;
    const t = await credential.getToken(SCOPE);
    cachedToken = t.token;
    cachedExpiry = t.expiresOnTimestamp;
    return cachedToken;
}

app.http('translate', {
    methods: ['POST'],
    authLevel: 'function',
    handler: async (request, context) => {
        // Forward the query string the client built (api-version, to, from),
        // but strip our own params (code = function key, debug) so they don't leak upstream.
        const fwd = new URLSearchParams(request.query);
        const debug = fwd.get('debug') === '1';
        fwd.delete('code');
        fwd.delete('debug');
        const qs = fwd.toString();
        const url = `${TRANSLATOR_ENDPOINT}/translate${qs ? '?' + qs : ''}`;
        const body = await request.text();

        let token;
        try {
            token = await getToken();
        } catch (err) {
            context.error('Failed to acquire managed-identity token', err);
            return { status: 502, jsonBody: { error: 'Token acquisition failed', detail: String(err && err.message || err) } };
        }

        const headers = {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json; charset=UTF-8'
        };
        // ResourceId is only needed on the GLOBAL endpoint; harmless (ignored) on custom-domain.
        if (TRANSLATOR_RESOURCE_ID) headers['Ocp-Apim-ResourceId'] = TRANSLATOR_RESOURCE_ID;
        if (TRANSLATOR_REGION) headers['Ocp-Apim-Subscription-Region'] = TRANSLATOR_REGION;

        let upstream;
        try {
            upstream = await fetch(url, { method: 'POST', headers, body });
        } catch (err) {
            context.error('Upstream Translator call failed', err);
            return { status: 502, jsonBody: { error: 'Translator request failed', detail: String(err && err.message || err) } };
        }

        const text = await upstream.text();

        if (debug) {
            let claims = {};
            try {
                const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64').toString('utf8'));
                claims = { aud: payload.aud, appid: payload.appid, oid: payload.oid, iss: payload.iss };
            } catch (e) { claims = { decodeError: String(e) }; }
            return {
                status: 200,
                jsonBody: {
                    debug: true,
                    upstreamStatus: upstream.status,
                    upstreamUrl: url,
                    resourceId: TRANSLATOR_RESOURCE_ID || null,
                    region: TRANSLATOR_REGION || null,
                    tokenClaims: claims,
                    upstreamBody: text
                }
            };
        }

        return {
            status: upstream.status,
            headers: { 'Content-Type': 'application/json' },
            body: text
        };
    }
});
