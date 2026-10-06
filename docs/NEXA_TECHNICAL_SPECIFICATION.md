# NEXA — Production-Grade Technical Specification & Architecture Blueprint
**Version:** 1.0.0-PROD-SPEC  
**Status:** Approved Architecture Draft  
**Target Platform:** Mobile (iOS/Android via Flutter), Desktop (macOS/Windows/Linux), Cloud Backend (Go / Node.js + PostgreSQL + Redis + WebRTC)

---

## Table of Contents
1. [Executive Architectural Summary](#1-executive-architectural-summary)
2. [End-to-End Cryptographic & Key Architecture](#2-end-to-end-cryptographic--key-architecture)
3. [Database Architecture & Complete Schema (PostgreSQL 16)](#3-database-architecture--complete-schema-postgresql-16)
4. [API & Real-Time WebSocket Protocol Specifications](#4-api--real-time-websocket-protocol-specifications)
5. [Backend Services & Microservices Topology](#5-backend-services--microservices-topology)
6. [WebRTC Audio & Video Calling Subsystem](#6-webrtc-audio--video-calling-subsystem)
7. [Flutter Client Architecture & Directory Layout](#7-flutter-client-architecture--directory-layout)
8. [Private AI & Zero-Knowledge Assistant Architecture](#8-private-ai--zero-knowledge-assistant-architecture)
9. [Security, Zero-Trust & STRIDE Threat Model](#9-security-zero-trust--stride-threat-model)
10. [Design System & Focus Orbit UI/UX Architecture](#10-design-system--focus-orbit-uiux-architecture)
11. [Containerized Infrastructure (Docker Compose Deployment)](#11-containerized-infrastructure-docker-compose-deployment)
12. [Phased Engineering Implementation Roadmap](#12-phased-engineering-implementation-roadmap)

---

## 1. Executive Architectural Summary

NEXA is engineered around a strict **zero-knowledge, metadata-minimized core**. The server acts strictly as an authenticated blind broker:
- **No plaintext access:** Message payloads, file attachments, and direct call streams are never accessible to the backend.
- **De-coupled identity:** Accounts use cryptographic user identifiers (`NX-XXXX-XXXX`) rather than mandatory mobile phone exposure.
- **Multi-device cryptographic isolation:** Each registered client device possesses an isolated cryptographic identity keypair. Multi-device sync uses pairwise Double Ratchet sessions and client-side device fan-out.
- **Calm, intentional UI:** The *Focus Orbit* interface prioritizes calm attention, actionable conversation cards, and contextual AI assistants with explicit user opt-in boundaries.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        NEXA TRUST BOUNDARY                             │
│                                                                        │
│   [ Client Device A ] <======== E2E Double Ratchet =======> [ Client Device B ]
│           │                                                      │     │
│   Hardware Keystore                                    Hardware Keystore
│           │                                                      │     │
│           ▼ (Ciphertext + Ephemeral Routing Meta)               ▼     │
│  ┌─────────────────────────────────────────────────────────────┐       │
│  │                    NEXA Edge / Gateway                      │       │
│  │  - Rate Limiting   - Blind Auth Token Validation            │       │
│  │  - Ephemeral Redis Relay                                    │       │
│  │  - Zero Plaintext Access                                    │       │
│  └─────────────────────────────────────────────────────────────┘       │
│           │                                                      │     │
│           ▼                                                      ▼     │
│  [ Encrypted Mailbox / Relay ]                            [ WebRTC TURN/SFU ]
│    (Short TTL Ciphertext Store)                            (DTLS-SRTP Media)
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. End-to-End Cryptographic & Key Architecture

NEXA implements the standard **Extended Triple Diffie-Hellman (X3DH)** key agreement protocol and the **Double Ratchet Protocol** (KDF-chain ratchet + DH ratchet).

### 2.1 Cryptographic Primitives
- **Curve:** Curve25519 (X25519 for DH key exchange, Ed25519 for identity signatures).
- **Symmetric Cipher:** `AES-256-GCM` or `ChaCha20-Poly1305` with 96-bit random nonce.
- **Hash Function:** `SHA-256` / `HMAC-SHA256` / `HKDF`.
- **Local Storage:** Client-side database encrypted with `SQLCipher` using AES-256-CBC, key sealed within Android Keystore / iOS Secure Enclave.

### 2.2 Key Hierarchy per Device
Every device $D_i$ owned by user $U_k$ generates and maintains:
1. **Identity Keypair ($IK_{D_i}$):** Long-term Ed25519 signing + X25519 DH keypair.
2. **Signed Prekey ($SPK_{D_i}$):** Medium-term X25519 keypair, cryptographically signed with $IK_{D_i}$, rotated every 7 days.
3. **One-Time Prekeys ($OPK_{D_i}^1, \dots, OPK_{D_i}^N$):** Pool of 100 ephemeral X25519 keypairs uploaded to server. When the pool drops below 25, client regenerates a new batch.
4. **Safety Number (Fingerprint):** Derived from sorted concatenation of both parties' identity public keys using SHA-512, formatted into 12 5-digit decimal blocks for manual or QR-code out-of-band verification.

### 2.3 X3DH Session Initiation Protocol Flow
When User A ($A_1$) initiates a session with User B ($B_1$):
```
User A (Device A1)                  Server                     User B (Device B1)
       │                               │                                │
       ├───── Fetch Prekey Bundle ────>│                                │
       │      for B1                   │                                │
       │<──── Returns (IK_B, SPK_B, ───┤                                │
       │      Sig_SPK_B, OPK_B_j)      │ (Consumes OPK_B_j)             │
       │                                                                │
  1. Verify Sig_SPK_B against IK_B                                      │
  2. Generate Ephemeral Keypair EK_A                                    │
  3. Compute DH1 = DH(IK_A, SPK_B)                                      │
     Compute DH2 = DH(EK_A, IK_B)                                       │
     Compute DH3 = DH(EK_A, SPK_B)                                      │
     Compute DH4 = DH(EK_A, OPK_B_j)                                    │
  4. SK = HKDF(DH1 || DH2 || DH3 || DH4, info="NEXA_X3DH_v1")          │
  5. Initialize Double Ratchet with SK                                 │
  6. Encrypt first message with AD = (IK_A || IK_B)                     │
       │                               │                                │
       ├───── Send Init Message ──────>│                                │
       │      (IK_A, EK_A, OPK_ID,     ├───── Deliver Init Message ────>│
       │       Ciphertext)             │                                │
                                                                  Compute DH1..4
                                                                  Initialize Ratchet
                                                                  Decrypt Ciphertext
```

### 2.4 Multi-Device Synchronization (Fan-Out)
When User A owns devices $\{A_1, A_2\}$ and sends a message to User B with devices $\{B_1, B_2\}$:
1. User A encrypts message payload $M$ into 3 independent ciphertexts:
   - $C_{B_1} = \text{Encrypt}(Session_{A_1 \to B_1}, M)$
   - $C_{B_2} = \text{Encrypt}(Session_{A_1 \to B_2}, M)$
   - $C_{A_2} = \text{Encrypt}(Session_{A_1 \to A_2}, M)$ (Self-sync copy)
2. The server receives 1 transmission container with 3 destination device envelopes and delivers them blindly.
3. User master key never leaves the client device.

### 2.5 Group Messaging Architecture (Sender Keys)
For groups up to 1,000 members:
- Uses the **Signal Sender Key Protocol**: Each member generates a symmetric Sender Key (Chain Key + Signature Key) and encrypts it pairwise to each group member via 1:1 Double Ratchet channels.
- Subsequent group messages use ratcheted symmetric encryption from the author's Sender Key chain, avoiding $O(N)$ re-encryption overhead on every single message.
- Group state changes (member added/removed) trigger immediate Sender Key rotation.

---

## 3. Database Architecture & Complete Schema (PostgreSQL 16)

The relational schema strictly enforces metadata segregation. Message tables store zero plaintext and short-lived queue entries.

```sql
-- PostgreSQL 16 Production DDL for NEXA Core
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. USERS & IDENTITY
-- ============================================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nexa_id VARCHAR(16) NOT NULL UNIQUE, -- E.g. NX-7K4M-29QP
    username VARCHAR(32) UNIQUE,
    phone_hash VARCHAR(64) UNIQUE,        -- Salted HMAC-SHA256 of E.164 phone
    phone_encrypted BYTEA,                -- Client-decryptable or null
    display_name VARCHAR(64) NOT NULL,
    avatar_url TEXT,
    bio TEXT,
    phone_discovery_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    username_discovery_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    account_status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (account_status IN ('active', 'suspended', 'deactivated')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_nexa_id ON users(nexa_id);
CREATE INDEX idx_users_username ON users(username) WHERE username IS NOT NULL;
CREATE INDEX idx_users_phone_hash ON users(phone_hash) WHERE phone_hash IS NOT NULL;

-- User Privacy Settings
CREATE TABLE user_privacy_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    last_seen_visibility VARCHAR(16) NOT NULL DEFAULT 'nobody' CHECK (last_seen_visibility IN ('everyone', 'contacts', 'nobody')),
    online_status_visibility VARCHAR(16) NOT NULL DEFAULT 'contacts' CHECK (online_status_visibility IN ('everyone', 'contacts', 'nobody')),
    read_receipts_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    who_can_find_me VARCHAR(16) NOT NULL DEFAULT 'id_only' CHECK (who_can_find_me IN ('nobody', 'contacts', 'id_only', 'everyone')),
    allow_ai_cloud_processing BOOLEAN NOT NULL DEFAULT FALSE,
    block_unknown_callers BOOLEAN NOT NULL DEFAULT TRUE,
    filter_unknown_messages BOOLEAN NOT NULL DEFAULT TRUE,
    disappearing_messages_default_ttl_sec INT DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 2. DEVICES & CRYPTOGRAPHIC KEYS (X3DH / DOUBLE RATCHET)
-- ============================================================================
CREATE TABLE user_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,            -- Client-generated persistent UUID
    device_name VARCHAR(64) NOT NULL,          -- E.g. "Pixel 8 Pro", "MacBook Pro M3"
    platform VARCHAR(16) NOT NULL CHECK (platform IN ('android', 'ios', 'windows', 'macos', 'linux', 'web')),
    identity_key BYTEA NOT NULL,               -- Ed25519 Public Key (32 bytes)
    registration_id INT NOT NULL,              -- Signal registration identity ID
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    push_token TEXT,                           -- FCM / APNs Token
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, device_id)
);

CREATE INDEX idx_devices_user ON user_devices(user_id, is_active);

-- Signed Prekeys per Device
CREATE TABLE device_signed_prekeys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES user_devices(id) ON DELETE CASCADE,
    key_id INT NOT NULL,
    public_key BYTEA NOT NULL,                 -- X25519 Public Key (32 bytes)
    signature BYTEA NOT NULL,                  -- Signature by device Identity Key (64 bytes)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(device_id, key_id)
);

-- One-Time Prekeys Pool
CREATE TABLE device_one_time_prekeys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES user_devices(id) ON DELETE CASCADE,
    key_id INT NOT NULL,
    public_key BYTEA NOT NULL,                 -- X25519 Public Key (32 bytes)
    is_consumed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(device_id, key_id)
);

CREATE INDEX idx_opk_unconsumed ON device_one_time_prekeys(device_id) WHERE is_consumed = FALSE;

-- ============================================================================
-- 3. MESSAGING & MAILBOX (ZERO-KNOWLEDGE CIPHERTEXT RELAY)
-- ============================================================================
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(16) NOT NULL CHECK (type IN ('direct', 'group', 'community_channel')),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE conversation_participants (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(16) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (conversation_id, user_id)
);

-- Ephemeral Message Mailbox Queue (Ciphertext only, deleted after ACKs)
CREATE TABLE message_mailbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sender_device_id UUID NOT NULL REFERENCES user_devices(id) ON DELETE CASCADE,
    recipient_device_id UUID NOT NULL REFERENCES user_devices(id) ON DELETE CASCADE,
    
    message_type INT NOT NULL DEFAULT 1,      -- 1: Signal Message, 2: Prekey Init, 3: Key Sync
    ciphertext BYTEA NOT NULL,                -- Pure encrypted payload (Double Ratchet envelope)
    iv BYTEA,                                 -- Initialization vector / nonce
    ephemeral_public_key BYTEA,               -- Optional ephemeral DH key for X3DH
    one_time_key_id INT,                      -- Referenced OPK ID if init
    
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mailbox_recipient ON message_mailbox(recipient_device_id, created_at ASC);

-- ============================================================================
-- 4. GROUPS & COMMUNITIES
-- ============================================================================
CREATE TABLE communities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(80) NOT NULL,
    slug VARCHAR(80) NOT NULL UNIQUE,
    description TEXT,
    avatar_url TEXT,
    is_private BOOLEAN NOT NULL DEFAULT FALSE,
    category VARCHAR(32) NOT NULL,           -- E.g. "Electronics", "AI", "Agriculture"
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    member_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE community_channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    community_id UUID NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    name VARCHAR(64) NOT NULL,
    is_announcement BOOLEAN NOT NULL DEFAULT FALSE,
    channel_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE community_members (
    community_id UUID NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(16) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (community_id, user_id)
);

-- ============================================================================
-- 5. CALLING SESSIONS (WEBRTC SIGNALING LOGS)
-- ============================================================================
CREATE TABLE call_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    call_type VARCHAR(16) NOT NULL CHECK (call_type IN ('audio', 'video')),
    status VARCHAR(16) NOT NULL DEFAULT 'ringing' CHECK (status IN ('ringing', 'active', 'ended', 'rejected', 'missed')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_sec INT DEFAULT 0
);

-- ============================================================================
-- 6. PERSONAL ASSISTANT & REMINDERS (CLIENT-SEALED BLOB OR LOCAL)
-- ============================================================================
CREATE TABLE personal_reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_payload BYTEA NOT NULL,         -- Reminders encrypted with user sync key
    remind_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'snoozed', 'cancelled')),
    recurrence_rule VARCHAR(64),              -- E.g. "FREQ=DAILY;INTERVAL=1"
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_reminders_trigger ON personal_reminders(user_id, remind_at, status);

-- ============================================================================
-- 7. AUDIT & REPUTATION (ZERO-KNOWLEDGE ABUSE CONTROLS)
-- ============================================================================
CREATE TABLE account_security_audits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type VARCHAR(32) NOT NULL,          -- 'new_device_linked', 'key_rotated', 'ip_anomaly'
    ip_subnet VARCHAR(45) NOT NULL,           -- Masked IP (e.g. /24 or /48)
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## 4. API & Real-Time WebSocket Protocol Specifications

### 4.1 REST Endpoints

| Method | Endpoint | Description | Auth Required |
|---|---|---|---|
| `POST` | `/v1/auth/register-challenge` | Initiate passkey / anonymous registration | No |
| `POST` | `/v1/auth/verify-registration` | Verify signature and issue auth tokens | No |
| `POST` | `/v1/auth/refresh` | Rotate access & refresh JWT tokens | Yes |
| `GET` | `/v1/users/lookup` | Query user by `nexa_id`, `username`, or phone hash | Yes |
| `POST` | `/v1/devices/register` | Register new device with identity public key | Yes |
| `POST` | `/v1/keys/prekeys` | Upload batch of Signed Prekey & One-time Prekeys | Yes |
| `GET` | `/v1/keys/bundle/:user_id/:device_id`| Fetch X3DH prekey bundle for session creation | Yes |
| `POST` | `/v1/mailbox/send` | Transmit encrypted envelopes for recipient devices | Yes |
| `POST` | `/v1/mailbox/ack` | Acknowledge receipt and purge ciphertext from server | Yes |
| `POST` | `/v1/communities` | Create public/private community | Yes |
| `GET` | `/v1/communities/explore` | Fetch recommended communities by category tags | Yes |

### 4.2 WebSocket Real-Time Frame Protocol
- **Transport:** WebSocket over TLS 1.3 (`wss://api.nexa.im/v1/realtime`)
- **Format:** Protocol Buffers or structured JSON frames.

#### Incoming Frame (Client to Server)
```json
{
  "trace_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "action": "ENVELOPE_SEND",
  "payload": {
    "conversation_id": "77f3941a-a169-4509-9ec6-89689e4726bf",
    "envelopes": [
      {
        "recipient_device_id": "4e184e6e-e630-466c-bb9e-4c12bbbe2766",
        "message_type": 1,
        "ciphertext_base64": "vA3B8kLx9...==",
        "nonce_base64": "98vBxZaL...==",
        "ephemeral_dh_public_base64": null
      }
    ]
  }
}
```

#### Outgoing Push Frame (Server to Client)
```json
{
  "event": "NEW_MESSAGE_ENVELOPE",
  "envelope_id": "f8a02d33-47be-43a3-b918-6bb7f8087d15",
  "conversation_id": "77f3941a-a169-4509-9ec6-89689e4726bf",
  "sender_user_id": "a12bc9d0-0f2c-4ec1-9128-40a12c40c812",
  "sender_device_id": "19b5ff02-cf30-4e50-9c21-1254bf5613da",
  "message_type": 1,
  "ciphertext_base64": "vA3B8kLx9...==",
  "nonce_base64": "98vBxZaL...==",
  "timestamp": 1728249600000
}
```

---

## 5. Backend Services & Microservices Topology

The backend uses a clean, high-concurrency Go service topology communicating via **NATS JetStream** for low-latency pub/sub and Redis cluster for ephemeral state.

```
                         [ Cloudflare / Envoy API Gateway ]
                         (TLS 1.3 Termination, WAF, Rate Limits)
                                          │
            ┌─────────────────────────────┼─────────────────────────────┐
            ▼                             ▼                             ▼
    [ Auth & Identity ]          [ Realtime Gateway ]          [ WebRTC Signaling ]
    - User IDs & Profiles        - WebSocket Conns             - Session Negotiation
    - Prekey Bundle Registry     - NATS JetStream Pub/Sub      - ICE Exchange
            │                             │                             │
            ├─────────────────────────────┴─────────────────────────────┤
            ▼                                                           ▼
     [ PostgreSQL 16 ]                                           [ Redis 7 ]
   - User Accounts                                             - Online Status Presence
   - Identity Keys                                             - Rate Limiter Buckets
   - Communities & Channels                                    - Ephemeral Routing Table
   - Mailbox Envelopes (Short TTL)
```

---

## 6. WebRTC Audio & Video Calling Subsystem

### 6.1 Calling Architecture & Signaling Flow
Calls utilize **peer-to-peer WebRTC with mandatory DTLS-SRTP** encryption for 1:1 sessions, falling back to TURN relay when NAT traversal fails.

```
Caller (Client A)            Signaling Server (Go WS)            Callee (Client B)
       │                                │                                │
       ├───── Call Invite (SDP Offer) ─>│                                │
       │      (Encrypted via Ratchet)   ├───── Forward Invite ──────────>│
       │                                │                                │
       │                                │<──── Call Accept (SDP Answer) ─┤
       │<──── Forward SDP Answer ───────┤                                │
       │                                │                                │
       ├───── ICE Candidate A ─────────>├───── Forward Candidate A ────>│
       │<──── Forward Candidate B ──────┤<──── ICE Candidate B ──────────┤
       │                                │                                │
       ▼                                                                 ▼
       ================ P2P Direct Connection (DTLS-SRTP) ===============
       [ Audio / Video Stream 100% Encrypted End-to-End ]
```

---

## 7. Flutter Client Architecture & Directory Layout

The client is structured following **Clean Architecture with Feature-First Modularization** using **Riverpod 2.0** for state management and **drift / SQLCipher** for local encrypted storage.

```
nexa_app/
├── android/app/src/main/kotlin/im/nexa/app/MainActivity.kt
├── ios/Runner/AppDelegate.swift
├── lib/
│   ├── main.dart                          # App bootstrap & service container init
│   ├── core/
│   │   ├── crypto/                        # Signal Protocol / Libsodium implementation
│   │   │   ├── double_ratchet.dart
│   │   │   ├── x3dh_manager.dart
│   │   │   ├── key_store.dart             # Hardware Keystore / Secure Enclave binding
│   │   │   └── safety_number.dart
│   │   ├── network/
│   │   │   ├── api_client.dart            # Dio HTTP client with certificate pinning
│   │   │   ├── websocket_client.dart      # Auto-reconnecting WS manager
│   │   │   └── token_interceptor.dart
│   │   ├── database/
│   │   │   ├── local_database.dart        # SQLCipher Drift schema
│   │   │   └── secure_storage.dart        # FlutterSecureStorage wrapper
│   │   ├── theme/
│   │   │   ├── color_palette.dart         # Calm Orbit design tokens
│   │   │   ├── typography.dart            # Inter / Outfit fonts
│   │   │   └── nexa_theme.dart
│   │   └── utils/
│   │       └── logger.dart
│   ├── features/
│   │   ├── auth/                          # Identity & Device Pairing
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   └── presentation/screens/
│   │   │       ├── register_screen.dart
│   │   │       ├── device_link_qr_screen.dart
│   │   │       └── recovery_key_screen.dart
│   │   ├── focus_orbit/                   # Central Home Hub & Priority Cards
│   │   │   ├── presentation/
│   │   │   │   ├── focus_orbit_screen.dart
│   │   │   │   └── widgets/
│   │   │       ├── orbit_navigation_wheel.dart
│   │   │       ├── priority_chat_card.dart
│   │   │       └── quiet_status_widget.dart
│   │   ├── chat/                          # 1:1 and Group Messaging
│   │   │   ├── domain/models/
│   │   │   ├── presentation/screens/
│   │   │   │   ├── conversation_list_screen.dart
│   │   │   │   └── chat_room_screen.dart
│   │   │   └── presentation/widgets/
│   │   │       ├── adaptive_chat_bubble.dart
│   │   │       ├── inline_reminder_card.dart
│   │   │       └── ephemeral_countdown.dart
│   │   ├── calls/                         # WebRTC VoIP & Video
│   │   │   ├── domain/
│   │   │   ├── presentation/screens/
│   │   │   │   ├── active_call_screen.dart
│   │   │   │   └── call_history_screen.dart
│   │   ├── communities/                   # Interest Exploration
│   │   │   ├── presentation/screens/
│   │   │   │   ├── explore_feed_screen.dart
│   │   │   │   └── channel_screen.dart
│   │   ├── assistant/                     # Private AI Assistant
│   │   │   ├── domain/
│   │   │   │   ├── local_assistant_engine.dart
│   │   │   │   └── permission_guard.dart
│   │   │   └── presentation/screens/
│   │   │       ├── assistant_bottom_sheet.dart
│   │   │       └── reminder_list_screen.dart
│   │   └── privacy_center/                # Full Transparency & Security Checkup
│   │       └── presentation/screens/
│   │           ├── privacy_dashboard_screen.dart
│   │           └── active_devices_screen.dart
└── pubspec.yaml
```

---

## 8. Private AI & Zero-Knowledge Assistant Architecture

### 8.1 Tri-Tier AI Execution Model
1. **Tier 1: On-Device Local AI (Default & Zero Latency)**
   - Runs quantized small models (e.g. MediaPipe / Gemma 2B or ONNX-optimized intent recognizers) directly on mobile NPU/GPU.
   - Functions: Message summarization, offline date/time entity extraction, scheduled reminder generation, contact search.
   - Privacy guarantee: No network transmission; data never leaves the device.
2. **Tier 2: Explicit Ephemeral Cloud Enclave (User Opt-in Only)**
   - Triggered only when the user explicitly requests heavy reasoning or complex summaries.
   - Modal prompt requires consent: `[Allow Once]`, `[Allow For This Chat]`, `[Never]`.
   - Transmitted to an isolated, non-logging confidential computing enclave; prompt and output are discarded immediately after processing.
3. **Tier 3: Strict Zero-AI Isolation**
   - In chats marked as "Strict Secret" or where either participant disables AI assistance, local model scanning hooks are strictly disabled.

---

## 9. Security, Zero-Trust & STRIDE Threat Model

| Threat Category (STRIDE) | Attack Vector | NEXA Mitigation Defense |
|---|---|---|
| **Spoofing** | Attacker impersonates a user's device or creates fake identity | Hardware-backed Ed25519 Identity keys; safety number verification with QR scanning; signed prekeys. |
| **Tampering** | Man-in-the-Middle alters ciphertext or routing envelope | AES-256-GCM / ChaCha20-Poly1305 with Associated Data (AD) including sender and recipient IDs. |
| **Repudiation** | User denies sending a malicious envelope | Ephemeral Double Ratchet message keys possess non-repudiation during session, but provide deniable authentication properties post-ratchet. |
| **Information Disclosure** | Server compromise or database dump | Zero-knowledge design: database stores only encrypted envelopes with 30-day TTL. Private keys never leave user devices. |
| **Denial of Service** | Flooding prekey bundles or spamming mailboxes | Token bucket rate limiting at Envoy gateway; prekey generation quotas; proof-of-work challenge on unauthenticated device registration. |
| **Elevation of Privilege** | Community member bypasses moderation controls | PostgreSQL Row-Level Security (RLS) and cryptographically signed administrative action logs. |

---

## 10. Design System & Focus Orbit UI/UX Architecture

### 10.1 Calm Palette Design Tokens
```css
:root {
  --nexa-bg-canvas: #0A0D12;       /* Deep space abyss */
  --nexa-bg-surface: #121721;      /* Elevated card slate */
  --nexa-bg-elevated: #1B2232;     /* Floating interactive element */
  --nexa-border-subtle: #242D40;   /* Hairline boundaries */
  
  --nexa-accent-cyan: #00E5FF;     /* Focus glow & primary CTA */
  --nexa-accent-emerald: #00E676;  /* Verified E2E encryption status */
  --nexa-accent-amber: #FFB300;    /* Pending reminders */
  
  --nexa-text-primary: #F0F4F8;   /* High contrast legible white */
  --nexa-text-secondary: #94A3B8; /* Muted slate for secondary meta */
  --nexa-text-muted: #64748B;     /* Timestamps and quiet labels */
  
  --nexa-radius-sm: 8px;
  --nexa-radius-md: 16px;
  --nexa-radius-lg: 24px;
}
```

---

## 11. Containerized Infrastructure (Docker Compose Deployment)

```yaml
version: '3.8'

services:
  nexa-postgres:
    image: postgres:16-alpine
    container_name: nexa-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: nexa_db
      POSTGRES_USER: nexa_admin
      POSTGRES_PASSWORD: ${DB_PASSWORD:-SecretNexaProductionPass123!}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U nexa_admin -d nexa_db"]
      interval: 5s
      timeout: 5s
      retries: 5

  nexa-redis:
    image: redis:7-alpine
    container_name: nexa-redis
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes", "--requirepass", "${REDIS_PASSWORD:-NexaRedisToken456!}"]
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"

  nexa-nats:
    image: nats:2.10-alpine
    container_name: nexa-nats
    restart: unless-stopped
    command: ["-js", "-m", "8222"]
    ports:
      - "4222:4222"
      - "8222:8222"

  nexa-backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: nexa-backend
    restart: unless-stopped
    depends_on:
      nexa-postgres:
        condition: service_healthy
      nexa-redis:
        condition: service_started
      nexa-nats:
        condition: service_started
    environment:
      PORT: 8080
      DATABASE_URL: postgres://nexa_admin:${DB_PASSWORD:-SecretNexaProductionPass123!}@nexa-postgres:5432/nexa_db?sslmode=disable
      REDIS_URL: redis://:${REDIS_PASSWORD:-NexaRedisToken456!}@nexa-redis:6379/0
      NATS_URL: nats://nexa-nats:4222
      JWT_SIGNING_KEY: ${JWT_SECRET:-NexaSecureSecretSigningKey789!}
    ports:
      - "8080:8080"

  nexa-coturn:
    image: coturn/coturn:latest
    container_name: nexa-coturn
    restart: unless-stopped
    network_mode: host
    command:
      - "-n"
      - "--log-file=stdout"
      - "--min-port=49152"
      - "--max-port=65535"
      - "--realm=turn.nexa.im"
      - "--use-auth-secret"
      - "--static-auth-secret=${TURN_SECRET:-CoturnSecretKeyNexa2026}"

volumes:
  postgres_data:
  redis_data:
```

---

## 12. Phased Engineering Implementation Roadmap

```
Phase 1: Zero-Knowledge Foundation
├── Identity creation (NX-ID + Ed25519 keys)
├── PostgreSQL schema & migration pipelines
├── Go REST API + JWT & device registration
└── Flutter basic UI shell with Secure Enclave storage

Phase 2: E2E Encrypted Messaging
├── X3DH prekey generation & server pool syncing
├── Double Ratchet session initiation & message encryption
├── Real-time WebSocket transmission & push notifications
└── Local encrypted message database (SQLCipher)

Phase 3: Multi-Device Sync & Recovery
├── QR-code device pairing handshake
├── Cross-device key synchronization
└── 24-word recovery key generation & offline vault backup

Phase 4: WebRTC Voice & Video
├── 1:1 DTLS-SRTP encrypted calling
├── Call signaling over WebSocket
└── STUN/TURN fallback configuration

Phase 5: Focus Orbit & Communities
├── Focus Orbit home screen & Priority Pulse card
├── Public/private interest communities & channels
└── Quiet Intelligence notification throttling

Phase 6: Private AI Assistant
├── On-device quantized model integration (MediaPipe)
├── Actionable message card detection (reminders/events)
└── Explicit privacy enclave opt-in modal

Phase 7: Security Hardening & Audit
├── Threat model review & penetration testing
├── Cryptographic implementation audit
└── Independent third-party vulnerability evaluation
```
