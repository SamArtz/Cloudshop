import { getApiBaseUrl, getToken, clearSession } from "./config.js";

export class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

async function request(path, options = {}) {
  const base = getApiBaseUrl();
  if (!base) {
    throw new ApiError(
      "Falta la URL del API. Ve a Ajustes y pégala (Invoke URL del stage dev).",
      0
    );
  }

  const headers = {
    "Content-Type": "application/json",
    ...(options.headers || {}),
  };

  const token = getToken();
  if (token && options.auth !== false) {
    headers.Authorization = `Bearer ${token}`;
  }

  const res = await fetch(`${base}${path}`, {
    ...options,
    headers,
  });

  let data = null;
  const text = await res.text();
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { error: text || "Respuesta no JSON" };
  }

  if (res.status === 401) {
    clearSession();
    throw new ApiError(data?.error || "Sesión expirada. Vuelve a iniciar sesión.", 401);
  }

  if (!res.ok) {
    throw new ApiError(data?.error || `Error HTTP ${res.status}`, res.status);
  }

  return data;
}

export const api = {
  register: (body) =>
    request("/auth/register", { method: "POST", body: JSON.stringify(body), auth: false }),

  login: (body) =>
    request("/auth/login", { method: "POST", body: JSON.stringify(body), auth: false }),

  me: () => request("/users/me"),

  listProducts: () => request("/products"),
  listStores: () => request("/stores"),

  getCart: () => request("/cart"),
  addCartItem: (productId, quantity) =>
    request("/cart/items", {
      method: "POST",
      body: JSON.stringify({ productId, quantity }),
    }),
  setCartItemQty: (productId, quantity) =>
    request(`/cart/items/${encodeURIComponent(productId)}`, {
      method: "PUT",
      body: JSON.stringify({ quantity }),
    }),
  removeCartItem: (productId) =>
    request(`/cart/items/${encodeURIComponent(productId)}`, { method: "DELETE" }),
  clearCart: () => request("/cart", { method: "DELETE" }),

  listOrders: () => request("/orders"),
  createOrder: () => request("/orders", { method: "POST" }),
};
