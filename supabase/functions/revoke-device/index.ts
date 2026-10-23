import { createClient } from 'npm:@supabase/supabase-js@2.89.0'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405, headers: { ...cors, 'Content-Type': 'application/json' } })
  const authHeader = req.headers.get('Authorization')
  const url = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!authHeader || !url || !anonKey || !serviceKey) return new Response(JSON.stringify({ error: 'server_not_configured' }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  try {
    const authClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false, autoRefreshToken: false } })
    const { data: { user }, error: authError } = await authClient.auth.getUser()
    if (authError || !user) return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } })
    const body = await req.json()
    const deviceId = typeof body.deviceId === 'string' ? body.deviceId : ''
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(deviceId)) return new Response(JSON.stringify({ error: 'invalid_request' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
    const { data: revoked, error } = await admin.rpc('revoke_device_atomic', { p_owner_id: user.id, p_device_id: deviceId })
    if (error) return new Response(JSON.stringify({ error: 'revocation_failed' }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
    return new Response(JSON.stringify({ ok: revoked === true }), { status: revoked ? 200 : 404, headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (_) {
    return new Response(JSON.stringify({ error: 'invalid_request' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
