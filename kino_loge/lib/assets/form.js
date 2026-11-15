const FONTS =
  "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono&display=swap";

export function mount(ctx, html) {
  ctx.importCSS(FONTS);
  ctx.importCSS("loge.css");
  ctx.root.innerHTML = `<div class="app">${html}</div>`;
  ctx.handleSync(sync);
  return ctx.root.firstElementChild;
}

export function sync() {
  document.activeElement?.dispatchEvent(new Event("change"));
}

export function element(tag, props = {}, ...children) {
  const el = Object.assign(document.createElement(tag), props);
  el.append(...children);
  return el;
}

export function field(label, ...children) {
  return element(
    "label",
    { className: "field" },
    element("span", { className: "field-label", textContent: label }),
    ...children
  );
}

export function select(options, push) {
  const el = element("select", { className: "input" }, ...choices(options));
  el.addEventListener("change", () => push(el.value));
  return el;
}

// Options that name a group are gathered under it, in the order they come.
const choices = (options) =>
  options.reduce((children, { id, label, group }) => {
    const option = new Option(label, id);
    if (group === undefined) return [...children, option];
    const last = children.at(-1);
    if (last instanceof HTMLOptGroupElement && last.label === group) last.append(option);
    else children.push(element("optgroup", { label: group }, option));
    return children;
  }, []);

export function input(type, push) {
  if (type === "boolean") {
    const el = element("input", { type: "checkbox", className: "switch" });
    el.addEventListener("change", () => push(el.checked));
    return el;
  }

  const el = element("input", { type: type === "integer" ? "number" : "text", className: "input" });
  el.addEventListener("change", () => push(el.value));
  return el;
}

export function assign(el, value) {
  if (el === document.activeElement) return;
  if (el.type === "checkbox") el.checked = value === true;
  else el.value = value ?? "";
}
