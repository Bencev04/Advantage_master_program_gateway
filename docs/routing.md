# Gateway Routing

The gateway is the browser-facing edge for active Advantage Master systems except Projects.

## Local Route Table

| Subdomain | Purpose | Local upstream |
| --- | --- | --- |
| `calendar.advantage.localhost` | Calendar Operations Hub frontend | `host.docker.internal:5174` |
| `hub.advantage.localhost` | Calendar alias/front door | `host.docker.internal:5174` |
| `calendar.advantage.localhost/api/*` | Calendar API | `host.docker.internal:8010` |
| `identity.advantage.localhost` | Identity login/API entrypoint | `host.docker.internal:18101` |
| `sales.advantage.localhost` | Sales React app | `host.docker.internal:5175` |
| `sales.advantage.localhost/api/sales/*` | Sales API facade | `host.docker.internal:18080` |
| `forwarding.advantage.localhost` | Forwarding app/API placeholder | `host.docker.internal:5180` |
| `fleet.advantage.localhost` | Fleet app/API placeholder | `host.docker.internal:5181` |

## Boundary

The gateway does not broker domain events. Cross-system state changes should be published through Kafka-compatible topics using the Events repo contracts and outbox/inbox patterns.

The gateway also does not replace app-level authorization. Identity issues sessions/tokens, and every backend still validates the verified user context and its own service code.
