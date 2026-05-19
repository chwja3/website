// 사용자 앱 인증 보조 기능을 Supabase Auth와 profiles 기준으로 처리한다.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type ProfileRow = {
  id: string;
  auth_user_id: string | null;
  login_id: string;
  display_name: string | null;
  name: string;
  parish: string;
  role: string;
  account_status: string;
  is_dev: boolean;
  raffle_excluded: boolean;
  password_migration_required: boolean;
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MIN_PASSWORD_LENGTH = 6;
const RAFFLE_EXCLUDED_PARISHES = new Set(['목양교구', '교회학교', '교회학교/목양교구']);
const SYNTHETIC_AUTH_EMAIL_DOMAIN = 'auth.beyond-us.local';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return jsonResponse({ ok: true }, 200);
  }
  if (req.method !== 'POST') {
    return jsonResponse({ ok: false, error: 'method_not_allowed' }, 405);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const action = text(body.action);
    const supabaseUrl = requiredEnv('SUPABASE_URL');
    const serviceRoleKey = getSupabaseServiceRoleKey();
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    if (action === 'register') {
      return jsonResponse(await registerProfile(supabase, body), 200);
    }
    if (action === 'resetPassword') {
      return jsonResponse(await resetPasswordByProfile(supabase, body), 200);
    }
    if (action === 'findNickname') {
      return jsonResponse(await findNickname(supabase, body), 200);
    }
    if (action === 'session') {
      return jsonResponse(await currentSessionProfile(supabase, req), 200);
    }

    return jsonResponse({ ok: false, error: 'unknown_action' }, 400);
  } catch (error) {
    console.error(error);
    return jsonResponse({ ok: false, error: 'server_error' }, 500);
  }
});

async function registerProfile(supabase: ReturnType<typeof createClient>, body: Record<string, unknown>) {
  const loginId = text(body.nickname || body.loginId || body.login_id);
  const password = text(body.password);
  const name = text(body.name);
  const parish = text(body.parish);

  if (!loginId || !password || !name || !parish) {
    return { ok: false, error: 'missing_fields' };
  }
  if (loginId.length < 2) {
    return { ok: false, error: 'invalid_login_id' };
  }
  if (password.length < MIN_PASSWORD_LENGTH) {
    return { ok: false, error: 'invalid_password', minPasswordLength: MIN_PASSWORD_LENGTH };
  }

  const { data: existing, error: existingError } = await supabase
    .from('profiles')
    .select('id, account_status')
    .eq('login_id', loginId)
    .maybeSingle();

  if (existingError) throw existingError;
  if (existing) {
    return { ok: false, error: existing.account_status === 'active' ? 'duplicate' : 'inactive_user' };
  }

  const profileId = crypto.randomUUID();
  const email = await syntheticAuthEmail(loginId);
  const participantNo = await nextParticipantNo(supabase);
  const raffleExcluded = RAFFLE_EXCLUDED_PARISHES.has(parish);

  const { data: authData, error: authError } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      login_id: loginId,
      display_name: loginId,
      name,
      parish,
    },
    app_metadata: {
      source: 'beyond_us_app',
      role: 'user',
      profile_id: profileId,
    },
  });

  if (isDuplicateAuthError(authError)) {
    return { ok: false, error: 'duplicate' };
  }
  if (authError || !authData.user) throw authError || new Error('auth_user_create_failed');

  const profile: Partial<ProfileRow> & { id: string } = {
    id: profileId,
    auth_user_id: authData.user.id,
    participant_no: participantNo,
    login_id: loginId,
    display_name: loginId,
    name,
    parish,
    role: 'user',
    account_status: 'active',
    is_dev: false,
    is_test: false,
    raffle_excluded: raffleExcluded,
    password_migration_required: false,
  } as Partial<ProfileRow> & { id: string };

  const { data: profileData, error: profileError } = await supabase
    .from('profiles')
    .insert(profile)
    .select('id, auth_user_id, login_id, display_name, name, parish, role, account_status, is_dev, raffle_excluded, password_migration_required')
    .single();

  if (profileError) {
    await supabase.auth.admin.deleteUser(authData.user.id).catch(() => {});
    if (isDuplicateDbError(profileError)) return { ok: false, error: 'duplicate' };
    throw profileError;
  }

  await supabase.from('retreat_attendance').upsert({
    profile_id: profileId,
    attendance_status: 'pending',
    attended: false,
  }, { onConflict: 'profile_id' });
  await supabase.from('user_inventory').upsert({ profile_id: profileId }, { onConflict: 'profile_id' });
  await supabase.from('user_summary').upsert({ profile_id: profileId }, { onConflict: 'profile_id' });
  await supabase.from('events').insert({
    profile_id: profileId,
    event_type: 'auth.registered',
    ref_type: 'auth',
    ref_id: authData.user.id,
    amount: 0,
    payload: { loginId, parish },
    source: 'web',
    created_by: profileId,
  });
  await supabase.rpc('bu_sync_profile_raffle_tickets', {
    p_profile_id: profileId,
    p_source: 'web',
    p_created_by: profileId,
  });

  const appOpenDate = await getAppOpenDate(supabase);
  return publicProfile(profileData as ProfileRow, appOpenDate);
}

async function resetPasswordByProfile(supabase: ReturnType<typeof createClient>, body: Record<string, unknown>) {
  const loginId = text(body.nickname || body.loginId || body.login_id);
  const name = text(body.name);
  const parish = text(body.parish);
  const newPassword = text(body.newPassword || body.new_password || body.password);

  if (!name || !parish || !newPassword) {
    return { ok: false, error: 'missing_fields' };
  }
  if (newPassword.length < MIN_PASSWORD_LENGTH) {
    return { ok: false, error: 'invalid_password', minPasswordLength: MIN_PASSWORD_LENGTH };
  }

  let query = supabase
    .from('profiles')
    .select('id, auth_user_id, login_id, display_name, name, parish, role, account_status, is_dev, raffle_excluded, password_migration_required')
    .eq('name', name)
    .eq('parish', parish)
    .eq('account_status', 'active');

  if (loginId) query = query.eq('login_id', loginId);

  const { data: profiles, error } = await query.order('login_id', { ascending: true }).limit(10);
  if (error) throw error;
  const rows = (profiles || []) as ProfileRow[];

  if (!rows.length) return { ok: false, error: 'not_found' };
  if (!loginId && rows.length > 1) {
    return { ok: false, duplicates: rows.map((row) => row.login_id) };
  }

  const target = rows[0];
  if (!target.auth_user_id) {
    return { ok: false, error: 'auth_not_linked' };
  }

  const { error: authError } = await supabase.auth.admin.updateUserById(target.auth_user_id, {
    password: newPassword,
    user_metadata: {
      login_id: target.login_id,
      display_name: target.display_name || target.login_id,
      name: target.name,
      parish: target.parish,
      password_reset_at: new Date().toISOString(),
    },
  });
  if (authError) {
    if (isWeakPasswordError(authError)) {
      return { ok: false, error: 'invalid_password', minPasswordLength: MIN_PASSWORD_LENGTH };
    }
    throw authError;
  }

  await supabase
    .from('profiles')
    .update({ password_migration_required: false })
    .eq('id', target.id);
  await supabase
    .from('legacy_auth_hashes')
    .update({
      password_hash: null,
      migrated_at: new Date().toISOString(),
      failed_attempts: 0,
      locked_until: null,
    })
    .eq('profile_id', target.id);
  await supabase.from('events').insert({
    profile_id: target.id,
    event_type: 'auth.password_reset.self',
    ref_type: 'auth',
    ref_id: target.auth_user_id,
    amount: 0,
    payload: { loginId: target.login_id },
    source: 'web',
    created_by: target.id,
  });

  return { ok: true };
}

async function findNickname(supabase: ReturnType<typeof createClient>, body: Record<string, unknown>) {
  const name = text(body.name);
  const parish = text(body.parish);
  if (!name || !parish) return { ok: false, error: 'missing_fields' };

  const { data, error } = await supabase
    .from('profiles')
    .select('login_id')
    .eq('name', name)
    .eq('parish', parish)
    .eq('account_status', 'active')
    .order('login_id', { ascending: true });

  if (error) throw error;
  const nicknames = (data || []).map((row: { login_id: string }) => row.login_id);
  if (!nicknames.length) return { ok: false, error: 'not_found' };
  return { ok: true, nicknames };
}

async function currentSessionProfile(supabase: ReturnType<typeof createClient>, req: Request) {
  const authHeader = req.headers.get('authorization') || '';
  const accessToken = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!accessToken) return { ok: false, error: 'unauthorized' };

  const { data: userData, error: userError } = await supabase.auth.getUser(accessToken);
  if (userError || !userData.user) {
    return { ok: false, error: 'unauthorized' };
  }

  const { data: profileData, error: profileError } = await supabase
    .from('profiles')
    .select('id, auth_user_id, login_id, display_name, name, parish, role, account_status, is_dev, raffle_excluded, password_migration_required')
    .eq('auth_user_id', userData.user.id)
    .maybeSingle();

  if (profileError) throw profileError;
  const profile = profileData as ProfileRow | null;
  if (!profile || profile.account_status !== 'active') {
    return { ok: false, error: 'inactive_user' };
  }

  await supabase
    .from('profiles')
    .update({ last_login_at: new Date().toISOString() })
    .eq('id', profile.id);

  const appOpenDate = await getAppOpenDate(supabase);
  return publicProfile(profile, appOpenDate);
}

async function getAppOpenDate(supabase: ReturnType<typeof createClient>): Promise<string> {
  const { data, error } = await supabase
    .from('app_settings')
    .select('value_json')
    .eq('key', 'app_open_date')
    .maybeSingle();
  if (error) throw error;
  return settingText(data && (data as { value_json?: unknown }).value_json);
}

async function nextParticipantNo(supabase: ReturnType<typeof createClient>): Promise<number | null> {
  const { data, error } = await supabase
    .from('profiles')
    .select('participant_no')
    .not('participant_no', 'is', null)
    .order('participant_no', { ascending: false })
    .limit(1);
  if (error) throw error;
  const current = Number(data && data[0] && data[0].participant_no);
  return Number.isFinite(current) && current > 0 ? current + 1 : 1;
}

function publicProfile(profile: ProfileRow, appOpenDate: string) {
  const role = String(profile.role || 'user');
  return {
    ok: true,
    source: 'supabase',
    nickname: profile.login_id,
    parish: profile.parish,
    isStaff: role === 'admin' || role === 'dev' || profile.is_dev === true,
    isDev: profile.is_dev === true || role === 'dev',
    role,
    appOpenDate,
    passwordMigrationRequired: profile.password_migration_required === true,
  };
}

async function syntheticAuthEmail(loginId: string): Promise<string> {
  const hash = await sha256Hex(loginId.trim());
  return `u_${hash}@${SYNTHETIC_AUTH_EMAIL_DOMAIN}`;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function settingText(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value.trim();
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (typeof value === 'object') {
    const record = value as Record<string, unknown>;
    return text(record.value || record.date || record.text || '');
  }
  return '';
}

function isDuplicateAuthError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const value = error as { code?: unknown; message?: unknown; status?: unknown };
  const message = String(value.message || '').toLowerCase();
  return value.status === 422 && (message.includes('already') || message.includes('registered'));
}

function isDuplicateDbError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const value = error as { code?: unknown; message?: unknown };
  return value.code === '23505' || String(value.message || '').toLowerCase().includes('duplicate');
}

function isWeakPasswordError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const value = error as { code?: unknown; name?: unknown };
  return value.code === 'weak_password' || value.name === 'AuthWeakPasswordError';
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

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}
