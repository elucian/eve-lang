What if I create evewp (eve web portal) to insepct eve activity. Graphic monitoring server/ helth server. That show server activity. Number of users connected and what domains it serve. Can host multiple apps on subdomains. Each app has it's own folder. Is not a dev layer is a deploy layer, is a web server.

Building evewp (Eve Web Portal) as a dedicated production web server, reverse proxy, and monitoring gateway makes architectural sense. Shifting it entirely out of the development loop (comp/evetx/eveux) and into the deployment and hosting layer creates a clean boundary.

Architectural Role of evewp
evewp acts as the edge router, multi-tenant container host, and telemetry dashboard for production environments.

┌─────────────────────────────────────────────────────────────┐
│ Public Web Traffic (HTTP/HTTPS) & Admin Dashboard           │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
               ▼                              ▼
┌─────────────────────────────────────────┐  ┌────────────────┐
│ evewp (Production Web Server & Proxy)   │  │ evewp Dashboard│
│ ├── Subdomain Router (app1.domain.com)  │  │ Health Metrics │
│ ├── Static Asset & Dynamic App Host     │  │ Active Conns   │
│ └── TLS Termination & Request Logging   │  │ Domain Status  │
└──────────────┬──────────────────────────┘  └────────────────┘
               │ Local IPC / Unix Domain Sockets
               ▼
┌─────────────────────────────────────────────────────────────┐
│ eve (Core Execution & Runtime Daemon)                       │
└─────────────────────────────────────────────────────────────┘
Core Responsibilities of evewp
Subdomain-Based Multi-Tenancy

Each deployed application lives in an isolated folder (/srv/eve/apps/<app_name>/).

evewp inspects incoming Host headers (app1.eve.io, app2.eve.io), maps them to the corresponding directory or process, and routes traffic accordingly.

Edge Proxy & Static Serving

Serves static assets directly from the app folder with high performance.

For dynamic routes, proxies requests via local Unix sockets or loopback HTTP to the background eve runtime daemon.

Graphic Monitoring & Health Server

Exposes a built-in admin interface showing active client connections, request rates, memory footprints, and domain routing tables.

Pulls telemetry metrics directly from the underlying eve server daemon via a low-overhead local IPC channel.

Implementation Considerations
Language Stack: Since your compiler core is built in Zig, writing evewp in Zig using a high-performance HTTP library (such as zap or Zig's native network modules) provides maximum throughput and minimal resource overhead.

Process Isolation: Ensure evewp handles reverse-proxying and routing, while the actual execution of app logic and data pipelines remains isolated inside the eve core daemon. This prevents a misbehaving web app from crashing the monitoring dashboard or edge proxy.
