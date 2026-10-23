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
    const code = typeof body.code === 'string' ? body.code.trim().toUpperCase() : ''
    const clientDeviceId = typeof body.clientDeviceId === 'string' ? body.clientDeviceId : ''
    // 12 random base32-like characters; never accept arbitrary SQL/hash input from the client.
    if (!/^[A-HJ-NP-Z2-9]{12}$/.test(code) || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(clientDeviceId)) {
      return new Response(JSON.stringify({ error: 'invalid_request' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    const encoder = new TextEncoder()
    const digest = await crypto.subtle.digest('SHA-256', encoder.encode(code))
    const codeHash = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('')
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
    const { data: pairId, error } = await admin.rpc('redeem_pairing_code_atomic', {
      p_owner_id: user.id,
      p_code_hash: codeHash,
      p_client_device_id: clientDeviceId,
    })
    if (error) return new Response(JSON.stringify({ error: 'pairing_rejected' }), { status: 403, headers: { ...cors, 'Content-Type': 'application/json' } })
    return new Response(JSON.stringify({ ok: true, pairId }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (_) {
    return new Response(JSON.stringify({ error: 'invalid_request' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
