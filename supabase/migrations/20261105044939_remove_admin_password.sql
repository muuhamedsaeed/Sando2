-- The Admin area now relies on the normal Supabase Auth session. Remove the
-- retired secondary-password storage and API surface.
drop function if exists public.admin_password_exists();
drop function if exists public.verify_admin_password(text);
drop function if exists public.set_admin_password(text, text);
drop table if exists public.admin_secret;
