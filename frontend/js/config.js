/**
 * Configuración del frontend CloudShop.
 * Puedes pegar la URL del API aquí O desde la pantalla de Ajustes (se guarda en localStorage).
 */
const DEFAULT_API_BASE_URL = ""; // ej: https://xxxx.execute-api.us-east-1.amazonaws.com/dev

const CONFIG_KEY = "cloudshop_api_base_url";
const TOKEN_KEY = "cloudshop_access_token";
const USER_KEY = "cloudshop_user";

export function getApiBaseUrl() {
  const saved = localStorage.getItem(CONFIG_KEY);
  if (saved && saved.trim()) return saved.trim().replace(/\/$/, "");
  return DEFAULT_API_BASE_URL.replace(/\/$/, "");
}

export function setApiBaseUrl(url) {
  localStorage.setItem(CONFIG_KEY, (url || "").trim().replace(/\/$/, ""));
}

export function getToken() {
  return localStorage.getItem(TOKEN_KEY) || "";
}

export function setSession(token, user) {
  localStorage.setItem(TOKEN_KEY, token || "");
  localStorage.setItem(USER_KEY, JSON.stringify(user || null));
}

export function getUser() {
  try {
    return JSON.parse(localStorage.getItem(USER_KEY) || "null");
  } catch {
    return null;
  }
}

export function clearSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}

export function isLoggedIn() {
  return Boolean(getToken());
}
