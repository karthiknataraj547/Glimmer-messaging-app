# NEXA — Private Life Operating System

> **A privacy-first communication platform and personal assistant engineered with zero-knowledge architecture, Double Ratchet end-to-end encryption, multi-device key agreement, and calm Focus Orbit UX.**

---

## 📚 Project Architecture & Documentation

- 📄 **[Technical Specification & Blueprint](file:///d:/messaging%20app/docs/NEXA_TECHNICAL_SPECIFICATION.md)** — Complete mathematical, cryptographic, database, API, and UI design specification.
- 🗄️ **[Database Migration Schema](file:///d:/messaging%20app/backend/migrations/001_init_schema.sql)** — PostgreSQL 16 DDL with zero-knowledge envelope isolation.
- 🐳 **[Docker Compose Stack](file:///d:/messaging%20app/docker-compose.yml)** — PostgreSQL 16, Redis 7, NATS JetStream, and Coturn STUN/TURN server.

---

## 🔐 Cryptographic Core (PointyCastle / BouncyCastle Port)

- **AEAD Encryption**: AES-256-GCM with 128-bit MAC tag and Associated Authenticated Data (AAD) binding sender/recipient/timestamp.
- **Double Ratchet**: Forward secrecy and break-in recovery with RFC 5869 HKDF-SHA256 ratchets.
- **Out-of-Band MITM Defense**: 60-digit deterministic Safety Number verification with iterative SHA-512 stretching.
- **Passphrase Vault**: 100,000-iteration PBKDF2-HMAC-SHA256 master key derivation.
- **Memory Protection**: Active memory zeroization wiping cryptographic buffers upon disposal.
- **Offline Backup**: 24-word recovery phrase generator for client-side zero-knowledge restoration.

---

## 📱 Modules & Screens

- **Focus Orbit**: [focus_orbit_screen.dart](file:///d:/messaging%20app/app/lib/features/focus_orbit/presentation/focus_orbit_screen.dart) — Quiet Intelligence header, Priority Pulse conversation cards, and tactile bottom dock.
- **Chat & Messaging**: [chat_screen.dart](file:///d:/messaging%20app/app/lib/features/chat/presentation/chat_screen.dart) — Adaptive bubbles, E2E encryption badges, and offline intent cards.
- **Private On-Device AI**: [local_intent_engine.dart](file:///d:/messaging%20app/app/lib/features/assistant/domain/local_intent_engine.dart) — Offline parsing for reminders, meetings, and promise commitments.
- **WebRTC Encrypted Calling**: [active_call_screen.dart](file:///d:/messaging%20app/app/lib/features/calls/presentation/active_call_screen.dart) — DTLS-SRTP secure media voice and video calling.
- **Interest Communities**: [explore_communities_screen.dart](file:///d:/messaging%20app/app/lib/features/communities/presentation/explore_communities_screen.dart) & [community_channel_screen.dart](file:///d:/messaging%20app/app/lib/features/communities/presentation/community_channel_screen.dart) — Non-algorithmic spaces with public channels.
- **Device Pairing**: [device_link_qr_screen.dart](file:///d:/messaging%20app/app/lib/features/auth/presentation/device_link_qr_screen.dart) — Zero-knowledge multi-device authorization.
- **Recovery Key Vault**: [recovery_key_vault_screen.dart](file:///d:/messaging%20app/app/lib/features/auth/presentation/recovery_key_vault_screen.dart) — 24-word paper backup with confidential blur overlay.
- **Privacy Center**: [privacy_center_screen.dart](file:///d:/messaging%20app/app/lib/features/privacy_center/presentation/privacy_center_screen.dart) — One-touch security audits, phone hiding, and metadata controls.

---

## 🧪 Testing & Verification

### Run Flutter Client Tests
```bash
cd app
flutter test
flutter analyze
```

### Run Backend Integration Tests
```bash
cd backend
npm test
```

---

## 🏛️ Repository Layout

```
.
├── backend/
│   ├── migrations/
│   │   └── 001_init_schema.sql       # Core database tables & indexes
│   ├── server.js                     # Zero-Knowledge Relay & Key Server
│   └── test/api_test.js              # Integration test suite
├── docs/
│   └── NEXA_TECHNICAL_SPECIFICATION.md  # Architectural Blueprint
├── app/                              # Cross-Platform Flutter Client
│   ├── lib/
│   │   ├── core/crypto/              # PointyCastle crypto & Double Ratchet
│   │   ├── core/network/             # Realtime WebSocket & mailbox relay
│   │   ├── core/theme/               # Calm Orbit design tokens
│   │   └── features/                 # Modular feature screens
│   └── test/                         # Comprehensive unit & widget tests
├── docker-compose.yml                # Local infrastructure definition
└── .env.example                      # Configuration template
```
