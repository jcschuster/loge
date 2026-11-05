import { mount, element, field, input, select, assign } from "./form.js";

const GROUPS = ["connection", "defaults", "advanced"];
const VERDICTS = { pending: "Checking…", ok: "Reachable", failed: "Unreachable" };

export function init(ctx, data) {
  const panel = mount(ctx, `<div class="panel"></div>`).firstElementChild;
  const engines = data.engines.filter((engine) => engine.fields.length > 0);
  const status = {};
  let selected = (engines.find((e) => e.fields.some((f) => f.value !== null)) ?? engines[0])?.id;
  let inputs = new Map();

  if (selected === undefined) {
    panel.append(element("p", { className: "empty", textContent: "No registered engine has settings." }));
    return;
  }

  const picker = select(engines, (id) => {
    selected = id;
    renderEngine();
  });
  picker.value = selected;
  const verdict = element("span", { className: "status" });
  const verify = element("button", { className: "button", textContent: "Verify" });
  const failure = element("div", { className: "failure" });
  const groups = element("div");
  panel.append(element("div", { className: "header" }, field("Engine", picker), verdict, verify), failure, groups);

  verify.addEventListener("click", () => {
    status[selected] = { state: "pending" };
    renderStatus();
    ctx.pushEvent("verify", { engine: selected });
  });

  const setting = (engine, f) => {
    const type = f.secret ? "string" : f.type;
    const el = input(type, (value) => ctx.pushEvent("set", { engine: engine.id, key: f.key, value }));
    inputs.set(f.key, el);

    if (type !== "boolean") {
      el.required = f.required;
      el.placeholder = f.secret ? "Livebook secret" : String(f.default ?? "");
    }

    const doc = f.doc ? [element("span", { className: "field-doc", textContent: f.doc })] : [];
    const label = f.required ? `${f.label} *` : f.label;
    return field(label, f.secret ? secret(engine, f, el) : el, ...doc);
  };

  const secret = (engine, f, el) => {
    const pick = element("button", { type: "button", className: "button", textContent: "Select" });
    pick.addEventListener("click", () =>
      ctx.selectSecret((name) => {
        el.value = name;
        el.dispatchEvent(new Event("change"));
      }, el.value || `${engine.id}_${f.key}`.toUpperCase())
    );
    return element("div", { className: "input-group" }, el, pick);
  };

  const group = (engine, name) => {
    const fields = engine.fields.filter((f) => f.group === name);
    if (fields.length === 0) return [];

    return [
      element(
        "details",
        { className: "group", open: name !== "advanced" },
        element("summary", { className: "group-title", textContent: name }),
        element("div", { className: "fields" }, ...fields.map((f) => setting(engine, f)))
      ),
    ];
  };

  const current = () => engines.find((e) => e.id === selected);

  const renderValues = () => {
    for (const f of current().fields) {
      const el = inputs.get(f.key);
      assign(el, f.value ?? (el.type === "checkbox" ? f.default : null));
    }
  };

  const renderStatus = () => {
    const s = status[selected];
    verdict.className = s ? `status status--${s.state}` : "status";
    verdict.textContent = s ? VERDICTS[s.state] : "";
    failure.textContent = s?.message ?? "";
    verify.disabled = s?.state === "pending";
  };

  const renderEngine = () => {
    inputs = new Map();
    groups.replaceChildren(...GROUPS.flatMap((name) => group(current(), name)));
    renderValues();
    renderStatus();
  };

  renderEngine();

  ctx.handleEvent("values", (values) => {
    for (const e of data.engines) {
      for (const f of e.fields) f.value = values[e.id]?.[f.key] ?? null;
    }
    renderValues();
  });

  ctx.handleEvent("verified", ({ engine, ok, message }) => {
    status[engine] = ok ? { state: "ok" } : { state: "failed", message };
    renderStatus();
  });
}
