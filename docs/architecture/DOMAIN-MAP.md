# Draneka Platform Domain Map

Current architectural direction:

```text
Draneka Platform

Core
Journal
Breeder
Intelligence
  └─ Intelligence Inbox
```

Intelligence is a peer domain, not a Journal child domain.

Journal Intelligence / Journal Assistant may remain a Journal-facing product surface, but internally it is an integration with Draneka Intelligence.

Future producers may include Journal, Breeder, Vision, Finder, Support/Customer Ops, or other separately admitted domains. Naming them here does not authorize integration.

Core may provide shared platform primitives, but it does not absorb Intelligence execution ownership merely because common services are used.
