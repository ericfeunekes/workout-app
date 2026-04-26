# React Frontend Instrumentation

Complete setup for React with Azure Application Insights, including distributed tracing, user analytics, and click tracking.

## Installation

```bash
npm install @microsoft/applicationinsights-web
npm install @microsoft/applicationinsights-react-js
npm install @microsoft/applicationinsights-clickanalytics-js  # Optional
```

## Basic Setup

```typescript
// src/telemetry/appInsights.ts
import { ApplicationInsights, DistributedTracingModes } from '@microsoft/applicationinsights-web';
import { ReactPlugin } from '@microsoft/applicationinsights-react-js';
import { createBrowserHistory } from 'history';

const browserHistory = createBrowserHistory();
const reactPlugin = new ReactPlugin();

const appInsights = new ApplicationInsights({
  config: {
    connectionString: process.env.REACT_APP_APPINSIGHTS_CONNECTION_STRING!,

    // Extensions
    extensions: [reactPlugin],
    extensionConfig: {
      [reactPlugin.identifier]: { history: browserHistory }
    },

    // Distributed tracing
    distributedTracingMode: DistributedTracingModes.W3C,
    enableCorsCorrelation: true,  // CRITICAL for cross-origin API calls

    // Page tracking
    enableAutoRouteTracking: true,
    autoTrackPageVisitTime: true,

    // Performance
    enableAjaxPerfTracking: true,
    maxAjaxCallsPerView: 500,

    // Domains to correlate
    correlationHeaderDomains: ['api.yourapp.com', 'agent.yourapp.com'],
    correlationHeaderExcludedDomains: ['*.google-analytics.com'],
  }
});

appInsights.loadAppInsights();

export { appInsights, reactPlugin };
```

## Provider Setup

```tsx
// src/index.tsx
import { AppInsightsContext } from '@microsoft/applicationinsights-react-js';
import { reactPlugin } from './telemetry/appInsights';

ReactDOM.render(
  <AppInsightsContext.Provider value={reactPlugin}>
    <App />
  </AppInsightsContext.Provider>,
  document.getElementById('root')
);
```

## User Authentication Tracking

Track authenticated users for session correlation:

```typescript
// After successful login
import { appInsights } from './telemetry/appInsights';

function onLoginSuccess(user: User) {
  appInsights.setAuthenticatedUserContext(
    user.id,           // User ID (hashed if sensitive)
    user.tenantId,     // Account/tenant ID
    true               // Store in cookie for session continuity
  );
}

// On logout
function onLogout() {
  appInsights.clearAuthenticatedUserContext();
}
```

## Custom Event Tracking

Track business-significant actions:

```typescript
import { useAppInsightsContext, useTrackEvent } from '@microsoft/applicationinsights-react-js';

function DocumentUpload() {
  const appInsights = useAppInsightsContext();
  const trackUpload = useTrackEvent(appInsights, 'DocumentUpload', {});

  const handleUpload = async (file: File) => {
    // Track upload initiated
    trackUpload({
      fileName: file.name,
      fileSize: file.size,
      fileType: file.type,
      step: 'initiated'
    });

    try {
      const result = await uploadFile(file);

      // Track success
      trackUpload({
        fileName: file.name,
        documentId: result.id,
        step: 'completed'
      });
    } catch (error) {
      // Track failure
      trackUpload({
        fileName: file.name,
        error: error.message,
        step: 'failed'
      });
      throw error;
    }
  };

  return <UploadComponent onUpload={handleUpload} />;
}
```

## Component Engagement Tracking

Measure how long users spend in components:

```typescript
import { withAITracking } from '@microsoft/applicationinsights-react-js';
import { reactPlugin } from './telemetry/appInsights';

// Wrap component to track engagement time
class ChatInterface extends React.Component {
  // Component implementation
}

// Tracks time from ComponentDidMount to ComponentWillUnmount
export default withAITracking(reactPlugin, ChatInterface, 'ChatInterface');
```

For functional components:

```typescript
import { useTrackMetric } from '@microsoft/applicationinsights-react-js';

function ChatInterface() {
  const appInsights = useAppInsightsContext();
  const trackMetric = useTrackMetric(appInsights, 'ChatInterface');

  useEffect(() => {
    // Track when component mounts
    const startTime = Date.now();

    return () => {
      // Track engagement duration on unmount
      trackMetric({ average: Date.now() - startTime });
    };
  }, []);

  return <div>...</div>;
}
```

## Click Analytics Plugin

Automatically track user interactions:

```typescript
import { ClickAnalyticsPlugin } from '@microsoft/applicationinsights-clickanalytics-js';

const clickPluginInstance = new ClickAnalyticsPlugin();
const clickPluginConfig = {
  autoCapture: true,
  dataTags: {
    useDefaultContentNameOrId: true,
    // Custom prefix for data attributes
    customDataPrefix: 'data-ai-',
  },
  // Callback for custom processing
  callback: {
    contentName: (element: Element) => {
      // Custom logic to extract content name
      return element.getAttribute('data-ai-name') ||
             element.getAttribute('aria-label') ||
             element.textContent?.slice(0, 50);
    }
  }
};

const appInsights = new ApplicationInsights({
  config: {
    connectionString: '...',
    extensions: [reactPlugin, clickPluginInstance],
    extensionConfig: {
      [reactPlugin.identifier]: { history: browserHistory },
      [clickPluginInstance.identifier]: clickPluginConfig,
    }
  }
});
```

Add data attributes to elements:

```tsx
<button
  data-ai-id="send-message"
  data-ai-action="click"
  data-ai-context="chat-interface"
  onClick={handleSend}
>
  Send Message
</button>
```

## Funnel Tracking

Track user progression through multi-step flows:

```typescript
// Define funnel steps as constants
const UPLOAD_FUNNEL = {
  SELECT_FILE: 'Upload.SelectFile',
  UPLOAD_START: 'Upload.Started',
  PROCESSING: 'Upload.Processing',
  COMPLETE: 'Upload.Complete',
  ERROR: 'Upload.Error',
};

function DocumentUploadFlow() {
  const appInsights = useAppInsightsContext();

  const trackStep = (step: string, properties?: Record<string, unknown>) => {
    appInsights.trackEvent({ name: step }, properties);
  };

  const handleFileSelect = (file: File) => {
    trackStep(UPLOAD_FUNNEL.SELECT_FILE, { fileType: file.type });
  };

  const handleUpload = async (file: File) => {
    trackStep(UPLOAD_FUNNEL.UPLOAD_START, { fileSize: file.size });

    try {
      trackStep(UPLOAD_FUNNEL.PROCESSING);
      const result = await uploadFile(file);
      trackStep(UPLOAD_FUNNEL.COMPLETE, { documentId: result.id });
    } catch (error) {
      trackStep(UPLOAD_FUNNEL.ERROR, { error: error.message });
    }
  };
}
```

Then in Azure Portal: Usage → Funnels → Add steps using these event names.

## Error Tracking

```typescript
import { SeverityLevel } from '@microsoft/applicationinsights-web';

// Global error boundary
class ErrorBoundary extends React.Component {
  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    appInsights.trackException({
      exception: error,
      severityLevel: SeverityLevel.Error,
      properties: {
        componentStack: errorInfo.componentStack,
        location: window.location.href,
      }
    });
  }
}

// Manual exception tracking
try {
  riskyOperation();
} catch (error) {
  appInsights.trackException({
    exception: error as Error,
    properties: { context: 'riskyOperation' }
  });
}
```

## Custom Metrics

```typescript
// Track numeric values
appInsights.trackMetric({
  name: 'DocumentProcessingTime',
  average: processingTimeMs,
  sampleCount: 1,
  min: processingTimeMs,
  max: processingTimeMs,
});

// Track with dimensions
appInsights.trackMetric({
  name: 'ChatResponseTime',
  average: responseTimeMs,
}, {
  model: 'gpt-4',
  messageType: 'user_query'
});
```

## Performance Optimization

```typescript
const appInsights = new ApplicationInsights({
  config: {
    connectionString: '...',

    // Batching
    maxBatchInterval: 15000,  // Send every 15 seconds
    maxBatchSizeInBytes: 102400,  // Or when batch reaches 100KB

    // Sampling (for high-traffic apps)
    samplingPercentage: 50,  // Sample 50% of telemetry

    // Disable features you don't need
    disableExceptionTracking: false,
    disableFetchTracking: false,
    disableAjaxTracking: false,
    disableCorrelationHeaders: false,  // Keep this enabled!
  }
});
```

## Source Maps for Production Debugging

Enable source map upload so exception stack traces are readable:

```typescript
// vite.config.ts
export default defineConfig({
  build: {
    sourcemap: true,  // Generate source maps
  }
});
```

Upload source maps to Azure:

```bash
# Install Azure CLI extension
az extension add --name application-insights

# Upload source maps after build
az monitor app-insights component sourcemap upload \
  --app <app-insights-name> \
  --resource-group <rg> \
  --source-map dist/assets/*.map \
  --source dist/assets/*.js
```

Or use the webpack/vite plugin:

```typescript
// vite.config.ts
import { applicationinsightsSourcemapPlugin } from '@anthropic/vite-plugin-appinsights-sourcemap';

export default defineConfig({
  plugins: [
    applicationinsightsSourcemapPlugin({
      connectionString: process.env.APPINSIGHTS_CONNECTION_STRING,
    })
  ]
});
```

**Important:** Keep source maps private. Upload them to App Insights but don't serve them publicly.

## Web Vitals Integration

Capture Core Web Vitals and send to Application Insights:

```bash
npm install web-vitals
```

```typescript
// src/telemetry/webVitals.ts
import { onCLS, onINP, onLCP, onFCP, onTTFB } from 'web-vitals';
import { appInsights } from './appInsights';

interface WebVitalMetric {
  name: string;
  value: number;
  rating: 'good' | 'needs-improvement' | 'poor';
  id: string;
}

function sendToAppInsights(metric: WebVitalMetric) {
  appInsights.trackMetric({
    name: `WebVitals.${metric.name}`,
    average: metric.value,
    sampleCount: 1,
  }, {
    rating: metric.rating,
    metricId: metric.id,
  });

  // Also track as event for easier querying
  appInsights.trackEvent({
    name: 'WebVitals',
  }, {
    metricName: metric.name,
    value: metric.value,
    rating: metric.rating,
  });
}

// Initialize - call once at app startup
export function initWebVitals() {
  onCLS(sendToAppInsights);   // Cumulative Layout Shift
  onINP(sendToAppInsights);   // Interaction to Next Paint
  onLCP(sendToAppInsights);   // Largest Contentful Paint
  onFCP(sendToAppInsights);   // First Contentful Paint
  onTTFB(sendToAppInsights);  // Time to First Byte
}
```

```typescript
// src/index.tsx
import { initWebVitals } from './telemetry/webVitals';

// Initialize after app loads
initWebVitals();
```

Query in Azure Monitor:

```kusto
customMetrics
| where name startswith "WebVitals."
| summarize
    avg(value) as avg_value,
    percentile(value, 75) as p75,
    percentile(value, 95) as p95
    by name, bin(timestamp, 1h)
| render timechart
```

## Testing Telemetry

```typescript
// In tests, mock the appInsights instance
jest.mock('./telemetry/appInsights', () => ({
  appInsights: {
    trackEvent: jest.fn(),
    trackException: jest.fn(),
    trackMetric: jest.fn(),
  },
  reactPlugin: {},
}));

// Verify tracking calls
expect(appInsights.trackEvent).toHaveBeenCalledWith(
  { name: 'DocumentUpload' },
  expect.objectContaining({ step: 'completed' })
);
```

## Minimal Viable Setup

Start with the essentials and expand only when you have questions you can't answer:

**Phase 1: Core observability**
- Request traces (automatic with SDK)
- Exceptions (automatic + error boundary)
- Page views (automatic with `enableAutoRouteTracking`)

**Phase 2: User behavior**
- Authenticated user context
- 3-5 key business events (signup, upload, chat, etc.)

**Phase 3: Performance**
- Web Vitals
- Custom metrics for critical paths

**Avoid over-instrumentation:** Don't track every click or add dozens of custom events upfront. Each piece of telemetry should answer a specific question.
