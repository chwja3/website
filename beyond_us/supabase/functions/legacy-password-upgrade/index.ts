// 기존 비밀번호 해시를 검증하고 Supabase Auth 비밀번호로 승격하는 Edge Function
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type LegacyHashRow = {
  profile_id: string;
  login_id: string;
  password_hash: string | null;
  migrated_at: string | null;
  failed_attempts: number;
  locked_until: string | null;
};

type ProfileRow = {
  id: string;
  auth_user_id: string | null;
  login_id: string;
  name: string;
  parish: string;
  account_status: string;
  password_migration_required: boolean;
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MAX_FAILED_ATTEMPTS = 5;
const LOCK_MINUTES = 10;
const MIN_SUPABASE_PASSWORD_LENGTH = 6;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return jsonResponse({ ok: true }, 200);
  }
  if (req.method !== 'POST') {
    return jsonResponse({ ok: false, error: 'method_not_allowed' }, 405);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const loginId = text(body.loginId || body.login_id || body.nickname);
    const password = text(body.password);
    const newPassword = text(body.newPassword || body.new_password);

    if (!loginId || !password) {
      return jsonResponse({ ok: false, error: 'missing_fields' }, 400);
    }
    if (password.length < 4) {
      return jsonResponse({ ok: false, error: 'invalid_password' }, 400);
    }

    const supabaseUrl = requiredEnv('SUPABASE_URL');
    const serviceRoleKey = getSupabaseServiceRoleKey();
    const pepper = requiredEnv('LEGACY_PASSWORD_PEPPER');
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: profileData, error: profileError } = await supabase
      .from('profiles')
      .select('id, auth_user_id, login_id, name, parish, account_status, password_migration_required')
      .eq('login_id', loginId)
      .maybeSingle();
    const profile = profileData as ProfileRow | null;

    if (profileError) throw profileError;
    if (!profile || profile.account_status !== 'active') {
      return jsonResponse({ ok: false, error: 'invalid_credentials' }, 401);
    }
    if (!profile.auth_user_id) {
      return jsonResponse({ ok: false, error: 'auth_not_linked' }, 409);
    }
    if (!profile.password_migration_required) {
      return jsonResponse({ ok: false, error: 'already_migrated' }, 409);
    }

    const { data: legacyData, error: legacyError } = await supabase
      .from('legacy_auth_hashes')
      .select('profile_id, login_id, password_hash, migrated_at, failed_attempts, locked_until')
      .eq('profile_id', profile.id)
      .maybeSingle();
    const legacy = legacyData as LegacyHashRow | null;

    if (legacyError) throw legacyError;
    if (!legacy || !legacy.password_hash || legacy.migrated_at) {
      return jsonResponse({ ok: false, error: 'invalid_credentials' }, 401);
    }
    if (legacy.locked_until && new Date(legacy.locked_until).getTime() > Date.now()) {
      return jsonResponse({ ok: false, error: 'temporarily_locked' }, 429);
    }

    const passwordOk = await verifyLegacyPassword(legacy.password_hash, password, pepper);
    if (!passwordOk) {
      await recordFailedAttempt(supabase, profile.id, legacy.failed_attempts);
      return jsonResponse({ ok: false, error: 'invalid_credentials' }, 401);
    }

    const passwordForAuth = newPassword || password;
    const usedNewPassword = Boolean(newPassword);
    if (passwordForAuth.length < MIN_SUPABASE_PASSWORD_LENGTH) {
      return jsonResponse({
        ok: false,
        error: usedNewPassword ? 'invalid_new_password' : 'weak_password_needs_reset',
        minPasswordLength: MIN_SUPABASE_PASSWORD_LENGTH,
      }, usedNewPassword ? 400 : 409);
    }

    const { error: authError } = await supabase.auth.admin.updateUserById(profile.auth_user_id, {
      password: passwordForAuth,
      user_metadata: {
        login_id: profile.login_id,
        display_name: profile.login_id,
        name: profile.name,
        parish: profile.parish,
        password_migrated_at: new Date().toISOString(),
      },
    });
    const weakPasswordReasons = getWeakPasswordReasons(authError);
    if (weakPasswordReasons) {
      return jsonResponse({
        ok: false,
        error: usedNewPassword ? 'invalid_new_password' : 'weak_password_needs_reset',
        minPasswordLength: MIN_SUPABASE_PASSWORD_LENGTH,
        reasons: weakPasswordReasons,
      }, usedNewPassword ? 400 : 409);
    }
    if (authError) throw authError;

    const migratedAt = new Date().toISOString();
    const { error: legacyUpdateError } = await supabase
      .from('legacy_auth_hashes')
      .update({
        password_hash: null,
        migrated_at: migratedAt,
        failed_attempts: 0,
        locked_until: null,
        last_attempt_at: migratedAt,
      })
      .eq('profile_id', profile.id);
    if (legacyUpdateError) throw legacyUpdateError;

    const { error: profileUpdateError } = await supabase
      .from('profiles')
      .update({ password_migration_required: false })
      .eq('id', profile.id);
    if (profileUpdateError) throw profileUpdateError;

    await supabase.from('events').insert({
      profile_id: profile.id,
      event_type: 'auth.password_migrated',
      ref_type: 'auth',
      payload: {
        method: 'legacy_hash_upgrade',
        password_source: usedNewPassword ? 'new_password' : 'legacy_password',
      },
      source: 'server',
    });

    return jsonResponse({ ok: true, passwordMigrated: true }, 200);
  } catch (error) {
    console.error(error);
    return jsonResponse({ ok: false, error: 'server_error' }, 500);
  }
});

async function recordFailedAttempt(
  supabase: ReturnType<typeof createClient>,
  profileId: string,
  previousFailedAttempts: number,
) {
  const nextFailedAttempts = previousFailedAttempts + 1;
  const now = new Date().toISOString();
  const lockedUntil = nextFailedAttempts >= MAX_FAILED_ATTEMPTS
    ? new Date(Date.now() + LOCK_MINUTES * 60 * 1000).toISOString()
    : null;

  const { error } = await supabase
    .from('legacy_auth_hashes')
    .update({
      failed_attempts: nextFailedAttempts,
      locked_until: lockedUntil,
      last_attempt_at: now,
    })
    .eq('profile_id', profileId);
  if (error) throw error;
}

async function verifyLegacyPassword(stored: string, password: string, pepper: string): Promise<boolean> {
  const parsed = parseLegacyHash(stored);
  if (!parsed) return false;
  const computed = await computeLegacyHash(password, parsed.salt, pepper, parsed.iterations);
  return secureCompare(computed, parsed.hash);
}

function parseLegacyHash(stored: string): { iterations: number; salt: string; hash: string } | null {
  const parts = String(stored || '').trim().split('$');
  if (parts.length !== 4 || parts[0] !== 'pwv1') return null;
  const iterations = Number(parts[1]) || 0;
  if (!iterations || iterations > 10000 || !parts[2] || !parts[3]) return null;
  return { iterations, salt: parts[2], hash: parts[3] };
}

async function computeLegacyHash(
  password: string,
  salt: string,
  pepper: string,
  iterations: number,
): Promise<string> {
  let digest = `${salt}\n${password}\n${pepper}`;
  for (let index = 0; index < iterations; index += 1) {
    const bytes = new TextEncoder().encode(digest);
    const hashBuffer = await crypto.subtle.digest('SHA-256', bytes);
    digest = base64Encode(new Uint8Array(hashBuffer));
  }
  return digest;
}

function secureCompare(leftValue: string, rightValue: string): boolean {
  const left = String(leftValue || '');
  const right = String(rightValue || '');
  let diff = left.length ^ right.length;
  const max = Math.max(left.length, right.length);
  for (let index = 0; index < max; index += 1) {
    diff |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }
  return diff === 0;
}

function base64Encode(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function requiredEnv(key: string): string {
  const value = Deno.env.get(key);
  if (!value) throw new Error(`Missing env: ${key}`);
  return value;
}

function getSupabaseServiceRoleKey(): string {
  const legacyKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacyKey) return legacyKey;

  const secretKeys = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (secretKeys) {
    const parsed = JSON.parse(secretKeys) as Record<string, string>;
    if (parsed.default) return parsed.default;
  }

  throw new Error('Missing Supabase service role secret');
}

function text(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value).trim();
}

function getWeakPasswordReasons(error: unknown): string[] | null {
  if (!error || typeof error !== 'object') return null;
  const value = error as { code?: unknown; name?: unknown; reasons?: unknown };
  if (value.code !== 'weak_password' && value.name !== 'AuthWeakPasswordError') return null;
  if (!Array.isArray(value.reasons)) return [];
  return value.reasons.map((reason) => String(reason));
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}
