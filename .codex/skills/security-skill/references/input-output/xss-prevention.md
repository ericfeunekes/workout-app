# XSS Prevention

Cross-Site Scripting (XSS) allows attackers to inject malicious scripts that execute in users' browsers, stealing data or performing actions as the user.

## XSS Types

| Type | Description | Example |
|------|-------------|---------|
| **Reflected** | Input reflected in response | Search query in error message |
| **Stored** | Input stored and displayed later | Comment with script tag |
| **DOM-based** | Client-side code processes untrusted data | `innerHTML = location.hash` |

## Primary Defense: Output Encoding

Encode data based on the context where it appears:

| Context | Encoding | Example |
|---------|----------|---------|
| HTML body | HTML entity encode | `<` → `&lt;` |
| HTML attribute | Attribute encode | `"` → `&quot;` |
| JavaScript | JS encode | `'` → `\'` |
| URL parameter | URL encode | `&` → `%26` |
| CSS | CSS encode | `\` → `\\` |

## Server-Side (Python)

### HTML Encoding

```python
import html
from markupsafe import Markup, escape

# Built-in html.escape
safe_text = html.escape(user_input)
# <script> becomes &lt;script&gt;

# MarkupSafe (used by Jinja2)
safe_text = escape(user_input)

# Mark trusted content (use sparingly!)
trusted = Markup("<strong>Known safe</strong>")
```

### Template Engines Auto-Escape

Jinja2 (FastAPI, Flask):
```python
from jinja2 import Environment, select_autoescape

env = Environment(
    autoescape=select_autoescape(['html', 'xml'])  # Enable auto-escape
)

# In templates, variables are escaped automatically
# {{ user_name }}  →  escaped
# {{ user_name | safe }}  →  NOT escaped (avoid unless necessary)
```

### JSON in HTML

```python
import json

def safe_json_in_html(data: dict) -> str:
    """Safely embed JSON in HTML script tag."""
    # Escape </script> and <!-- to prevent breaking out
    json_str = json.dumps(data)
    json_str = json_str.replace("<", "\\u003c")
    json_str = json_str.replace(">", "\\u003e")
    json_str = json_str.replace("&", "\\u0026")
    return json_str

# Usage in template
# <script>const data = {{ safe_json_in_html(user_data) }};</script>
```

## Client-Side (JavaScript/React)

### React Auto-Escapes

```jsx
// SAFE - React escapes by default
function UserGreeting({ name }) {
  return <div>Hello, {name}</div>;
  // If name = "<script>alert(1)</script>"
  // Renders as text, not executed
}

// DANGEROUS - bypasses escaping
function UnsafeContent({ html }) {
  return <div dangerouslySetInnerHTML={{ __html: html }} />;
  // Never use with user input!
}
```

### Safe DOM Manipulation

```javascript
// SAFE - textContent doesn't parse HTML
element.textContent = userInput;

// DANGEROUS - innerHTML parses HTML
element.innerHTML = userInput;  // XSS if userInput contains <script>

// SAFE - createElement + textContent
const div = document.createElement('div');
div.textContent = userInput;
parent.appendChild(div);
```

### Safe Attribute Setting

```javascript
// SAFE - setAttribute for most attributes
element.setAttribute('data-value', userInput);

// DANGEROUS - event handlers
element.setAttribute('onclick', userInput);  // XSS!
element.onclick = () => eval(userInput);     // XSS!

// DANGEROUS - href with javascript:
element.setAttribute('href', userInput);
// If userInput = "javascript:alert(1)"  →  XSS

// SAFE - validate URL scheme
function safeHref(url) {
  try {
    const parsed = new URL(url, window.location.origin);
    if (!['http:', 'https:'].includes(parsed.protocol)) {
      return '#';  // Block javascript:, data:, etc.
    }
    return url;
  } catch {
    return '#';
  }
}
```

## Content Security Policy (CSP)

Defense in depth - CSP blocks inline scripts even if XSS exists:

```python
from fastapi import Response

@app.middleware("http")
async def add_security_headers(request, call_next):
    response = await call_next(request)

    # Strict CSP
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "script-src 'self'; "  # No inline scripts
        "style-src 'self' 'unsafe-inline'; "  # Allow inline styles
        "img-src 'self' https:; "
        "font-src 'self'; "
        "connect-src 'self' https://api.example.com; "
        "frame-ancestors 'none'; "
        "base-uri 'self'; "
        "form-action 'self'"
    )

    # Prevent MIME sniffing
    response.headers["X-Content-Type-Options"] = "nosniff"

    return response
```

### CSP with Nonces (for inline scripts)

```python
import secrets

@app.middleware("http")
async def csp_with_nonce(request, call_next):
    nonce = secrets.token_urlsafe(16)
    request.state.csp_nonce = nonce

    response = await call_next(request)

    response.headers["Content-Security-Policy"] = (
        f"default-src 'self'; "
        f"script-src 'self' 'nonce-{nonce}'; "
        f"style-src 'self' 'unsafe-inline'"
    )

    return response

# In template:
# <script nonce="{{ request.state.csp_nonce }}">
#   // This inline script is allowed
# </script>
```

## Sanitization (When HTML is Required)

Use only when you must allow some HTML:

### Python (bleach)

```python
import bleach

ALLOWED_TAGS = ['p', 'br', 'strong', 'em', 'ul', 'ol', 'li', 'a']
ALLOWED_ATTRS = {
    'a': ['href', 'title'],  # Only these attrs on <a>
}

def sanitize_html(dirty_html: str) -> str:
    return bleach.clean(
        dirty_html,
        tags=ALLOWED_TAGS,
        attributes=ALLOWED_ATTRS,
        strip=True
    )

# Link validation
def sanitize_with_link_validation(html: str) -> str:
    def filter_href(tag, name, value):
        if tag == 'a' and name == 'href':
            # Only allow http/https
            if not value.startswith(('http://', 'https://')):
                return False
        return True

    return bleach.clean(
        html,
        tags=ALLOWED_TAGS,
        attributes={'a': filter_href},
        strip=True
    )
```

### JavaScript (DOMPurify)

```javascript
import DOMPurify from 'dompurify';

// Basic sanitization
const clean = DOMPurify.sanitize(dirtyHtml);

// Strict config
const strictConfig = {
  ALLOWED_TAGS: ['p', 'br', 'strong', 'em'],
  ALLOWED_ATTR: [],  // No attributes
};
const clean = DOMPurify.sanitize(dirtyHtml, strictConfig);

// With link validation
DOMPurify.addHook('afterSanitizeAttributes', (node) => {
  if (node.tagName === 'A') {
    const href = node.getAttribute('href') || '';
    if (!href.startsWith('https://')) {
      node.removeAttribute('href');
    }
    node.setAttribute('rel', 'noopener noreferrer');
    node.setAttribute('target', '_blank');
  }
});
```

## Common Vulnerable Patterns

```javascript
// DOM XSS patterns to avoid:

// innerHTML with user data
element.innerHTML = `Welcome, ${username}`;

// document.write
document.write(userInput);

// eval and friends
eval(userInput);
new Function(userInput);
setTimeout(userInput, 0);
setInterval(userInput, 0);

// jQuery
$(userInput);  // If userInput starts with <, creates element
$('#id').html(userInput);
$('#id').append(userInput);

// Location-based
location = userInput;
location.href = userInput;
window.open(userInput);
```

```python
# Server-side patterns to avoid:

# String formatting in HTML
html = f"<div>{user_name}</div>"

# Template with autoescape disabled
{% autoescape false %}
  {{ user_content }}
{% endautoescape %}

# Marking user input as safe
Markup(user_input)
{{ user_input | safe }}
```

## HTTP Headers for XSS Prevention

```python
# Full security headers
response.headers["Content-Security-Policy"] = "..."  # See above
response.headers["X-Content-Type-Options"] = "nosniff"
response.headers["X-Frame-Options"] = "DENY"
response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

# Legacy XSS filter (deprecated but harmless)
response.headers["X-XSS-Protection"] = "1; mode=block"
```

## Testing for XSS

```python
XSS_PAYLOADS = [
    "<script>alert(1)</script>",
    "<img src=x onerror=alert(1)>",
    "<svg onload=alert(1)>",
    "javascript:alert(1)",
    "'-alert(1)-'",
    '"><script>alert(1)</script>',
    "{{constructor.constructor('alert(1)')()}}",  # Template injection
]

@pytest.mark.parametrize("payload", XSS_PAYLOADS)
def test_xss_encoded(client, payload):
    """Ensure XSS payloads are encoded in output."""
    response = client.get(f"/search?q={payload}")
    # Payload should be HTML-encoded, not raw
    assert payload not in response.text
    assert html.escape(payload) in response.text or payload not in response.text
```

## Audit Checklist

- [ ] Are templates using auto-escaping?
- [ ] Is `| safe` / `Markup()` / `dangerouslySetInnerHTML` avoided or carefully reviewed?
- [ ] Are URLs validated before use in href/src?
- [ ] Is CSP configured to block inline scripts?
- [ ] Is user HTML sanitized with allowlisted tags?
- [ ] Are security headers set (X-Content-Type-Options, etc.)?
- [ ] Is JSON properly encoded when embedded in HTML?
- [ ] Are DOM manipulation methods using textContent instead of innerHTML?

## References

- OWASP XSS Prevention Cheat Sheet
- MDN Content Security Policy
- DOMPurify documentation
