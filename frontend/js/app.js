import {
  getApiBaseUrl,
  setApiBaseUrl,
  getUser,
  setSession,
  clearSession,
  isLoggedIn,
} from "./config.js";
import { api, ApiError } from "./api.js";

const views = {
  auth: document.getElementById("view-auth"),
  app: document.getElementById("view-app"),
};

const els = {
  alertAuth: document.getElementById("alert-auth"),
  alertApp: document.getElementById("alert-app"),
  loginForm: document.getElementById("form-login"),
  registerForm: document.getElementById("form-register"),
  settingsForm: document.getElementById("form-settings"),
  apiUrlInput: document.getElementById("api-url"),
  apiUrlSettings: document.getElementById("api-url-settings"),
  userChip: document.getElementById("user-chip"),
  productsGrid: document.getElementById("products-grid"),
  cartBody: document.getElementById("cart-body"),
  ordersBody: document.getElementById("orders-body"),
  cartTotal: document.getElementById("cart-total"),
};

let currentPage = "products";

function showAlert(target, message, type = "error") {
  if (!target) return;
  if (!message) {
    target.className = "alert hidden";
    target.textContent = "";
    return;
  }
  target.className = `alert alert-${type}`;
  target.textContent = message;
}

function setAuthMode(mode) {
  document.getElementById("tab-login").classList.toggle("active", mode === "login");
  document.getElementById("tab-register").classList.toggle("active", mode === "register");
  els.loginForm.classList.toggle("hidden", mode !== "login");
  els.registerForm.classList.toggle("hidden", mode !== "register");
}

function showApp(loggedIn) {
  views.auth.classList.toggle("hidden", loggedIn);
  views.app.classList.toggle("hidden", !loggedIn);
  if (loggedIn) {
    const user = getUser();
    els.userChip.textContent = user
      ? `${user.fullName || user.email} · ${user.role}`
      : "Sesión activa";
    navigate(currentPage);
  }
}

function navigate(page) {
  currentPage = page;
  document.querySelectorAll("[data-page]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.page === page);
  });
  document.querySelectorAll("[data-view]").forEach((panel) => {
    panel.classList.toggle("hidden", panel.dataset.view !== page);
  });
  showAlert(els.alertApp, "");

  if (page === "products") loadProducts();
  if (page === "cart") loadCart();
  if (page === "orders") loadOrders();
  if (page === "settings") {
    els.apiUrlSettings.value = getApiBaseUrl();
  }
}

async function loadProducts() {
  els.productsGrid.innerHTML = `<div class="empty">Cargando productos…</div>`;
  try {
    const data = await api.listProducts();
    const products = data.products || data.items || [];
    if (!products.length) {
      els.productsGrid.innerHTML = `<div class="empty">No hay productos todavía.</div>`;
      return;
    }
    els.productsGrid.innerHTML = products
      .map(
        (p, i) => `
      <article class="card" style="animation-delay:${i * 40}ms">
        <h3>${escapeHtml(p.name || "Producto")}</h3>
        <div class="meta">${escapeHtml(p.description || p.category || "Sin descripción")}</div>
        <div class="meta">Stock: ${p.stock ?? "—"} · Tienda: ${escapeHtml(p.storeId || "—")}</div>
        <div class="price">$${formatMoney(p.price)}</div>
        <div class="row-actions">
          <input type="number" min="1" value="1" id="qty-${escapeAttr(p.productId)}" />
          <button class="btn btn-primary" data-add="${escapeAttr(p.productId)}">Agregar</button>
        </div>
      </article>`
      )
      .join("");

    els.productsGrid.querySelectorAll("[data-add]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.getAttribute("data-add");
        const qtyInput = document.getElementById(`qty-${id}`);
        const qty = Number(qtyInput?.value || 1);
        try {
          btn.disabled = true;
          await api.addCartItem(id, qty);
          showAlert(els.alertApp, "Producto agregado al carrito.", "ok");
        } catch (err) {
          handleError(err, els.alertApp);
        } finally {
          btn.disabled = false;
        }
      });
    });
  } catch (err) {
    handleError(err, els.alertApp);
    els.productsGrid.innerHTML = `<div class="empty">No se pudieron cargar los productos.</div>`;
  }
}

async function loadCart() {
  els.cartBody.innerHTML = `<tr><td colspan="4" class="empty">Cargando carrito…</td></tr>`;
  try {
    const data = await api.getCart();
    const cart = data.cart || {};
    const items = cart.items || [];
    if (!items.length) {
      els.cartBody.innerHTML = `<tr><td colspan="4" class="empty">Tu carrito está vacío.</td></tr>`;
      els.cartTotal.textContent = "$0.00";
      return;
    }

    let total = 0;
    els.cartBody.innerHTML = items
      .map((item) => {
        const line = Number(item.price || 0) * Number(item.quantity || 0);
        total += line;
        return `
        <tr>
          <td>${escapeHtml(item.name || item.productId)}</td>
          <td>
            <input type="number" min="0" value="${Number(item.quantity || 0)}"
              data-qty="${escapeAttr(item.productId)}" style="width:4.5rem;padding:.4rem;border-radius:10px;border:1px solid var(--line)" />
          </td>
          <td>$${formatMoney(item.price)}</td>
          <td>
            <button class="btn btn-secondary" data-update="${escapeAttr(item.productId)}">Actualizar</button>
            <button class="btn btn-danger" data-remove="${escapeAttr(item.productId)}">Quitar</button>
          </td>
        </tr>`;
      })
      .join("");

    els.cartTotal.textContent = `$${formatMoney(total)}`;

    els.cartBody.querySelectorAll("[data-update]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.getAttribute("data-update");
        const input = els.cartBody.querySelector(`[data-qty="${CSS.escape(id)}"]`);
        try {
          await api.setCartItemQty(id, Number(input.value || 0));
          showAlert(els.alertApp, "Carrito actualizado.", "ok");
          loadCart();
        } catch (err) {
          handleError(err, els.alertApp);
        }
      });
    });

    els.cartBody.querySelectorAll("[data-remove]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        try {
          await api.removeCartItem(btn.getAttribute("data-remove"));
          showAlert(els.alertApp, "Producto eliminado.", "ok");
          loadCart();
        } catch (err) {
          handleError(err, els.alertApp);
        }
      });
    });
  } catch (err) {
    handleError(err, els.alertApp);
    els.cartBody.innerHTML = `<tr><td colspan="4" class="empty">No se pudo cargar el carrito.</td></tr>`;
  }
}

async function loadOrders() {
  els.ordersBody.innerHTML = `<tr><td colspan="4" class="empty">Cargando pedidos…</td></tr>`;
  try {
    const data = await api.listOrders();
    const orders = data.orders || data.items || [];
    if (!orders.length) {
      els.ordersBody.innerHTML = `<tr><td colspan="4" class="empty">Aún no tienes pedidos.</td></tr>`;
      return;
    }
    els.ordersBody.innerHTML = orders
      .map(
        (o) => `
      <tr>
        <td>${escapeHtml(o.orderId || "—")}</td>
        <td>${escapeHtml(o.status || "—")}</td>
        <td>$${formatMoney(o.total ?? o.totalAmount)}</td>
        <td>${escapeHtml(formatDate(o.createdAt))}</td>
      </tr>`
      )
      .join("");
  } catch (err) {
    handleError(err, els.alertApp);
    els.ordersBody.innerHTML = `<tr><td colspan="4" class="empty">No se pudieron cargar los pedidos.</td></tr>`;
  }
}

function handleError(err, target) {
  const msg = err instanceof ApiError ? err.message : "Error inesperado";
  showAlert(target, msg, "error");
  if (err instanceof ApiError && err.status === 401) {
    showApp(false);
  }
}

function formatMoney(value) {
  const n = Number(value);
  if (Number.isNaN(n)) return "0.00";
  return n.toFixed(2);
}

function formatDate(value) {
  if (!value) return "—";
  try {
    return new Date(value).toLocaleString();
  } catch {
    return String(value);
  }
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function escapeAttr(value) {
  return escapeHtml(value).replaceAll("'", "&#39;");
}

// ---- Eventos ----
document.getElementById("tab-login").addEventListener("click", () => setAuthMode("login"));
document.getElementById("tab-register").addEventListener("click", () => setAuthMode("register"));

els.loginForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  showAlert(els.alertAuth, "");
  const url = els.apiUrlInput.value.trim();
  if (url) setApiBaseUrl(url);

  const email = document.getElementById("login-email").value.trim();
  const password = document.getElementById("login-password").value;
  const btn = els.loginForm.querySelector("button[type=submit]");
  try {
    btn.disabled = true;
    const data = await api.login({ email, password });
    setSession(data.accessToken, data.user);
    showAlert(els.alertAuth, "Login correcto.", "ok");
    showApp(true);
  } catch (err) {
    handleError(err, els.alertAuth);
  } finally {
    btn.disabled = false;
  }
});

els.registerForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  showAlert(els.alertAuth, "");
  const url = els.apiUrlInput.value.trim();
  if (url) setApiBaseUrl(url);

  const body = {
    email: document.getElementById("reg-email").value.trim(),
    password: document.getElementById("reg-password").value,
    fullName: document.getElementById("reg-name").value.trim(),
    role: "CLIENT",
  };
  const btn = els.registerForm.querySelector("button[type=submit]");
  try {
    btn.disabled = true;
    await api.register(body);
    showAlert(els.alertAuth, "Cuenta creada. Ahora inicia sesión.", "ok");
    setAuthMode("login");
    document.getElementById("login-email").value = body.email;
  } catch (err) {
    handleError(err, els.alertAuth);
  } finally {
    btn.disabled = false;
  }
});

els.settingsForm.addEventListener("submit", (e) => {
  e.preventDefault();
  setApiBaseUrl(els.apiUrlSettings.value);
  showAlert(els.alertApp, "URL del API guardada en este navegador.", "ok");
});

document.getElementById("btn-logout").addEventListener("click", () => {
  clearSession();
  showApp(false);
  showAlert(els.alertAuth, "Sesión cerrada.", "info");
});

document.getElementById("btn-checkout").addEventListener("click", async () => {
  try {
    await api.createOrder();
    showAlert(els.alertApp, "Pedido creado correctamente.", "ok");
    navigate("orders");
  } catch (err) {
    handleError(err, els.alertApp);
  }
});

document.getElementById("btn-clear-cart").addEventListener("click", async () => {
  try {
    await api.clearCart();
    showAlert(els.alertApp, "Carrito vaciado.", "ok");
    loadCart();
  } catch (err) {
    handleError(err, els.alertApp);
  }
});

document.querySelectorAll("[data-page]").forEach((btn) => {
  btn.addEventListener("click", () => navigate(btn.dataset.page));
});

// Boot
els.apiUrlInput.value = getApiBaseUrl();
els.apiUrlSettings.value = getApiBaseUrl();
setAuthMode("login");
showApp(isLoggedIn());
