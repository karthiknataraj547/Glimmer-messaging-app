-- PostgreSQL 16 Migration 001: Initial NEXA Core Schema
-- Enforces Zero-Knowledge Metadata Segregation & Cryptographic Key Store

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. USERS & IDENTITY
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nexa_id VARCHAR(16) NOT NULL UNIQUE,       -- E.g. NX-7K4M-29QP
    username VARCHAR(32) UNIQUE,
    phone_hash VARCHAR(64) UNIQUE,              -- Salted HMAC-SHA256 of E.164 phone
    phone_encrypted BYTEA,                      -- Client-decryptable or null
    display_name VARCHAR(64) NOT NULL,
    avatar_url TEXT,
    bio TEXT,
    phone_discovery_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    username_discovery_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    account_status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (account_status IN ('active', 'suspended', 'deactivated')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_nexa_id ON users(nexa_id);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username) WHERE username IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_phone_hash ON users(phone_hash) WHERE phone_hash IS NOT NULL;

-- User Privacy Settings
CREATE TABLE IF NOT EXISTS user_privacy_settings (
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
CREATE TABLE IF NOT EXISTS user_devices (
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

CREATE INDEX IF NOT EXISTS idx_devices_user ON user_devices(user_id, is_active);

-- Signed Prekeys per Device
CREATE TABLE IF NOT EXISTS device_signed_prekeys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES user_devices(id) ON DELETE CASCADE,
    key_id INT NOT NULL,
    public_key BYTEA NOT NULL,                 -- X25519 Public Key (32 bytes)
    signature BYTEA NOT NULL,                  -- Signature by device Identity Key (64 bytes)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(device_id, key_id)
);

-- One-Time Prekeys Pool
CREATE TABLE IF NOT EXISTS device_one_time_prekeys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES user_devices(id) ON DELETE CASCADE,
    key_id INT NOT NULL,
    public_key BYTEA NOT NULL,                 -- X25519 Public Key (32 bytes)
    is_consumed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(device_id, key_id)
);

CREATE INDEX IF NOT EXISTS idx_opk_unconsumed ON device_one_time_prekeys(device_id) WHERE is_consumed = FALSE;

-- ============================================================================
-- 3. MESSAGING & MAILBOX (ZERO-KNOWLEDGE CIPHERTEXT RELAY)
-- ============================================================================
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(16) NOT NULL CHECK (type IN ('direct', 'group', 'community_channel')),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conversation_participants (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(16) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (conversation_id, user_id)
);

-- Ephemeral Message Mailbox Queue (Ciphertext only, purged upon ACK)
CREATE TABLE IF NOT EXISTS message_mailbox (
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

CREATE INDEX IF NOT EXISTS idx_mailbox_recipient ON message_mailbox(recipient_device_id, created_at ASC);

-- ============================================================================
-- 4. GROUPS & COMMUNITIES
-- ============================================================================
CREATE TABLE IF NOT EXISTS communities (
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

CREATE TABLE IF NOT EXISTS community_channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    community_id UUID NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    name VARCHAR(64) NOT NULL,
    is_announcement BOOLEAN NOT NULL DEFAULT FALSE,
    channel_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS community_members (
    community_id UUID NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(16) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (community_id, user_id)
);

-- ============================================================================
-- 5. CALLING SESSIONS (WEBRTC SIGNALING LOGS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS call_sessions (
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
-- 6. PERSONAL ASSISTANT & REMINDERS (CLIENT-SEALED BLOB)
-- ============================================================================
CREATE TABLE IF NOT EXISTS personal_reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_payload BYTEA NOT NULL,         -- Reminders encrypted with user sync key
    remind_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'snoozed', 'cancelled')),
    recurrence_rule VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reminders_trigger ON personal_reminders(user_id, remind_at, status);

-- ============================================================================
-- 7. AUDIT & REPUTATION (ZERO-KNOWLEDGE ABUSE CONTROLS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS account_security_audits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type VARCHAR(32) NOT NULL,
    ip_subnet VARCHAR(45) NOT NULL,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
