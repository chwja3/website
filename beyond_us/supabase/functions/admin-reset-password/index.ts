// 관리자가 Supabase Auth 유저 비밀번호를 초기화하는 Edge Function
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type ProfileRow = {
  id: string;
  auth_user_id: string | null;
  login_id: string;
  name: string;
  parish: string;
  role: string;
  account_status: string;
  is_dev: boolean;
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MIN_SUPABASE_PASSWORD_LENGTH = 6;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return jsonResponse({ ok: true }, 200);
  }
  if (req.method !== 'POST') {
    return jsonResponse({ ok: false, error: 'method_not_allowed' }, 405);
  }

  try {
    const authHeader = req.headers.get('authorization') || '';
    const accessToken = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!accessToken) {
      return jsonResponse({ ok: false, error: 'supabase_admin_session_required' }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const targetLoginId = text(body.loginId || body.login_id || body.nickname);
    const newPassword = text(body.newPassword || body.new_password || body.password);

    if (!targetLoginId || !newPassword) {
      return jsonResponse({ ok: false, error: 'missing_fields' }, 400);
    }
    if (newPassword.length < MIN_SUPABASE_PASSWORD_LENGTH) {
      return jsonResponse({
        ok: false,
        error: 'invalid_new_password',
        minPasswordLength: MIN_SUPABASE_PASSWORD_LENGTH,
      }, 400);
    }

    const supabaseUrl = requiredEnv('SUPABASE_URL');
    const serviceRoleKey = getSupabaseServiceRoleKey();
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } = await supabase.auth.getUser(accessToken);
    if (userError || !userData.user) {
      return jsonResponse({ ok: false, error: 'unauthorized' }, 401);
    }

    const { data: adminData, error: adminError } = await supabase
      .from('profiles')
      .select('id, auth_user_id, login_id, name, parish, role, account_status, is_dev')
      .eq('auth_user_id', userData.user.id)
      .maybeSingle();
    const admin = adminData as ProfileRow | null;

    if (adminError) throw adminError;
    if (!isAdminProfile(admin)) {
      return jsonResponse({ ok: false, error: 'admin_required' }, 403);
    }

    const { data: targetData, error: targetError } = await supabase
      .from('profiles')
      .select('id, auth_user_id, login_id, name, parish, role, account_status, is_dev')
      .eq('login_id', targetLoginId)
      .maybeSingle();
    const target = targetData as ProfileRow | null;

    if (targetError) throw targetError;
    if (!target || target.account_status !== 'active') {
      return jsonResponse({ ok: false, error: 'user_not_found' }, 404);
    }
    if (!target.auth_user_id) {
      return jsonResponse({ ok: false, error: 'auth_not_linked' }, 409);
    }

    const { error: authError } = await supabase.auth.admin.updateUserById(target.auth_user_id, {
      password: newPassword,
      user_metadata: {
        login_id: target.login_id,
        display_name: target.login_id,
        name: target.name,
        parish: target.parish,
        password_reset_by_admin_at: new Date().toISOString(),
      },
    });
    const weakPasswordReasons = getWeakPasswordReasons(authError);
    if (weakPasswordReasons) {
      return jsonResponse({
        ok: false,
        error: 'invalid_new_password',
        minPasswordLength: MIN_SUPABASE_PASSWORD_LENGTH,
        reasons: weakPasswordReasons,
      }, 400);
    }
    if (authError) throw authError;

    const resetAt = new Date().toISOString();
    const { error: profileUpdateError } = await supabase
      .from('profiles')
      .update({ password_migration_required: false })
      .eq('id', target.id);
    if (profileUpdateError) throw profileUpdateError;

    const { error: legacyUpdateError } = await supabase
      .from('legacy_auth_hashes')
      .update({
        password_hash: null,
        migrated_at: resetAt,
        failed_attempts: 0,
        locked_until: null,
        last_attempt_at: resetAt,
      })
      .eq('profile_id', target.id);
    if (legacyUpdateError) throw legacyUpdateError;

    await supabase.from('events').insert({
      profile_id: target.id,
      event_type: 'auth.password_reset_by_admin',
      ref_type: 'auth',
      amount: 0,
      payload: {
        adminLoginId: admin.login_id,
      },
      source: 'admin',
      created_by: admin.id,
    });

    return jsonResponse({
      ok: true,
      source: 'supabase',
      nickname: target.login_id,
      passwordReset: true,
    }, 200);
  } catch (error) {
    console.error(error);
    return jsonResponse({ ok: false, error: 'server_error' }, 500);
  }
});

function isAdminProfile(profile: ProfileRow | null): boolean {
  if (!profile || profile.account_status !== 'active') return false;
  return profile.role === 'admin' || profile.role === 'dev' || profile.is_dev === true;
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
