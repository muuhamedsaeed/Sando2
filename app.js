const cfg = window.SANDO2_CONFIG;
const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
const DEFAULTS = { siteName: "sando2", tagline: "Monthly income and expense log", homeTitle: "Monthly ledger", homeDesc: "Income and expenses for the month you pick.", currency: "EGP" };
const $ = id => document.getElementById(id);
const pad = n => String(n).padStart(2, "0");
const esc = s => String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const money = n => new Intl.NumberFormat("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n);

const THEME_KEY = "sando2-theme";
const themeMedia = window.matchMedia ? window.matchMedia("(prefers-color-scheme: dark)") : null;
function getThemePreference() {
  try {
    const saved = localStorage.getItem(THEME_KEY);
    return ["light", "dark", "system"].includes(saved) ? saved : "system";
  } catch (_) { return "system"; }
}
function applyTheme(preference = getThemePreference()) {
  const resolved = preference === "system" && themeMedia && themeMedia.matches ? "dark" : preference === "system" ? "light" : preference;
  document.documentElement.dataset.theme = resolved;
  document.documentElement.dataset.themePreference = preference;
}
function setThemePreference(preference) {
  const value = ["light", "dark", "system"].includes(preference) ? preference : "system";
  try { localStorage.setItem(THEME_KEY, value); } catch (_) { /* Storage can be unavailable in private contexts. */ }
  applyTheme(value);
  document.querySelectorAll("[data-theme-select]").forEach(select => { select.value = value; });
}
function initThemeControls() {
  const preference = getThemePreference();
  applyTheme(preference);
  document.querySelectorAll("[data-theme-select]").forEach(select => {
    select.value = preference;
    select.onchange = () => setThemePreference(select.value);
  });
}
if (themeMedia) {
  const updateSystemTheme = () => { if (getThemePreference() === "system") applyTheme("system"); };
  if (themeMedia.addEventListener) themeMedia.addEventListener("change", updateSystemTheme);
  else if (themeMedia.addListener) themeMedia.addListener(updateSystemTheme);
}

function brand(s) {
  document.querySelectorAll("[data-site]").forEach(e => e.textContent = s.siteName);
  document.querySelectorAll("[data-logo]").forEach(e => e.textContent = (s.siteName[0] || "s").toLowerCase());
  document.querySelectorAll("[data-tagline]").forEach(e => e.textContent = s.tagline);
  document.title = s.siteName;
}
function showError(e) {
  console.error(e);
  const el = $("err"); if (el) el.textContent = "Something went wrong: " + (e.message || e) + ". Check your connection and try again.";
}
async function requireLogin() {
  const { data } = await sb.auth.getSession();
  if (!data.session) { location.replace("index.html"); return null; }
  document.querySelectorAll(".logout").forEach(b => b.onclick = async () => {
    await sb.auth.signOut();
    location.href = "index.html";
  });
  return data.session;
}
async function loadSettings() {
  const { data, error } = await sb.from("settings").select("*").maybeSingle();
  if (error) throw error;
  return data ? { siteName: data.site_name, tagline: data.tagline, homeTitle: data.home_title, homeDesc: data.home_desc, currency: data.currency } : { ...DEFAULTS };
}
async function loadCategories() {
  const { data, error } = await sb.from("categories").select("id,type,name").order("name");
  if (error) throw error;
  return { income: data.filter(c => c.type === "income"), expense: data.filter(c => c.type === "expense") };
}
