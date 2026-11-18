# Supabase setup

1. **Create the tables**: Supabase Dashboard > SQL Editor > paste `supabase/schema.sql` > Run (safe to re-run).
2. **Create your user**: Dashboard > Authentication > Users > Add user (email + password).
   Optionally disable public sign-ups: Authentication > Providers > Email > turn off "Allow new users to sign up".
3. **Set credentials** (never commit these):
   ```
   export SUPABASE_EMAIL=you@example.com
   export SUPABASE_PASSWORD=your-password
   ```
   URL and publishable key live in `facefusion.ini` (`[supabase]`) and can be overridden with `SUPABASE_URL` / `SUPABASE_KEY`.
4. **Use it**:
   ```python
   from facefusion import supabase_client as db
   run_id = db.create_run({'status': 'running', 'processors': ['face_swapper'], 'target_name': 'a.mp4'})
   db.update_run(run_id, {'status': 'completed', 'finished_at': '2026-11-18T12:00:00Z'})
   db.list_runs(limit = 20)
   db.save_preset('fast', {'face_swapper_model': 'hyperswap_1a_256'})
   ```

## Security
- Tables use Row Level Security: only the signed-in owner can read/write their rows; the `anon` role has no access.
- The publishable key is safe in a public repo **only because of this**. Never commit a `sb_secret_...` / service_role key.
- Outputs bucket `outputs` is private; upload to `<user_id>/<file>`.
