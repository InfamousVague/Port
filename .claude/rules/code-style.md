# Code Style

- Follow the project's existing patterns and conventions
- Keep functions focused and small
- Prefer explicit over implicit
- Write self-documenting code — add comments only where logic isn't self-evident
- UI state lives in `PortStore` (`@MainActor`, `@Observable`); views stay declarative.
- System calls (`kill`, `lsof`, `getifaddrs`, `Network.framework`) are confined to the non-UI files.
- Anything that signals or kills a process must be explicit, user-initiated, and confirmable — never automatic.
