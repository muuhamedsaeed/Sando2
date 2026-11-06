# sando2 – income and expense log (Supabase + Vercel)

Static website (HTML/CSS/JS) with a Supabase database and login. No build step.

## 1. Create the database (Supabase)
1. Create a project at https://supabase.com.
2. SQL Editor > New query > paste `supabase/schema.sql` > Run.
3. Authentication > Users > Add user > Create new user. Enter your email and the password you want for sando2, and tick "Auto Confirm User".
4. Authentication > Sign In / Providers > turn OFF "Allow new users to sign up", so only you can log in.
5. Project Settings > API: copy the Project URL and the publishable (or legacy `anon`) public key.

### Existing database upgrade

If you already ran an older `schema.sql`, open SQL Editor > New query, paste `supabase/migration-002.sql`, and run it once. This adds recurring pinned transactions and the balance carry-over function. It is safe to run again.

If you previously enabled the separate Admin password, also run `supabase/migrations/20261105044939_remove_admin_password.sql`. It removes that no-longer-used secret and its functions. Admin is then protected by the normal website sign-in only.

To add optional notes to income and expense entries, run `supabase/migrations/20261105050425_add_entry_notes.sql` after the earlier migrations.

## 2. Configure the website
Open `config.js` and fill in `supabaseUrl`, `supabaseAnonKey` and `ownerEmail` (the email from step 3).
Only the publishable/anon key goes in the website. Never use the `service_role` key or a database connection string.

Test locally with live reload: run `npx live-server --host=127.0.0.1 --port=4176 --no-browser` in this folder and open http://127.0.0.1:4176/. Saving an HTML, CSS, or JavaScript file reloads the preview automatically.

## 3. Publish on Vercel
1. Push this folder to a GitHub repository.
2. Vercel > Add New > Project > import the repository.
3. Framework Preset: Other. Leave Build Command and Output Directory empty. Deploy.
4. Supabase > Authentication > URL Configuration: set Site URL to your Vercel address (for example https://sando2.vercel.app).

## What is stored where
- `settings`: site name, tagline, home page title and description, currency.
- `categories`: income and expense categories.
- `entries`: every income and expense line (date, description, category, amount).
- `entry_notes`: optional notes linked to an income or expense entry.
- `pinned_items`: active or paused income/expense items that appear from their chosen start month onward.
- `pinned_amounts`: month-specific amounts for pinned items without a fixed amount.
- The login password is handled by Supabase Auth. Once signed in, you can use both Home and Admin with that same password.
Row Level Security means each user can only read and change their own rows.
