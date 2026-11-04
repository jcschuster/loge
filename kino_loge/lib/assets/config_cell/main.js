export function init(ctx, data) {
  ctx.importCSS("main.css");
  ctx.root.innerHTML = `<div class="loge-settings"></div>`;
  const root = ctx.root.querySelector(".loge-settings");
  const groups = ["connection", "defaults", "advanced"];
  const status = {};

  const input = (engine, field) => {
    const el = document.createElement("input");
    const push = (value) => ctx.pushEvent("set", { engine: engine.id, key: field.key, value });

    if (field.type === "boolean" && !field.secret) {
      el.type = "checkbox";
      el.checked = field.value ?? field.default === true;
      el.addEventListener("change", () => push(el.checked));
    } else {
      el.type = field.type === "integer" && !field.secret ? "number" : "text";
      el.value = field.value ?? "";
      el.placeholder = field.secret ? "Livebook secret name" : String(field.default ?? "");
      el.addEventListener("change", () => push(el.value));
    }

    return el;
  };

  const render = () => {
    root.replaceChildren(
      ...data.engines
        .filter((engine) => engine.fields.length > 0)
        .map((engine) => {
          const section = document.createElement("details");
          const summary = document.createElement("summary");
          summary.textContent = engine.label;
          const verify = document.createElement("button");
          verify.textContent = "Verify";
          verify.addEventListener("click", (event) => {
            event.preventDefault();
            status[engine.id] = { pending: true };
            render();
            ctx.pushEvent("verify", { engine: engine.id });
          });
          const result = document.createElement("span");
          const s = status[engine.id];
          result.className = s?.pending ? "" : s?.ok ? "loge-ok" : "loge-failed";
          result.textContent = s?.pending ? "checking…" : s ? (s.ok ? "reachable" : s.message) : "";
          summary.append(" ", verify, " ", result);
          section.append(summary);

          for (const group of groups) {
            const fields = engine.fields.filter((f) => f.group === group);
            if (fields.length === 0) continue;
            const heading = document.createElement("h4");
            heading.textContent = group;
            section.append(heading);
            for (const field of fields) {
              const label = document.createElement("label");
              label.textContent = field.label + (field.required ? " *" : "");
              if (field.doc) label.title = field.doc;
              label.append(input(engine, field));
              section.append(label);
            }
          }

          return section;
        })
    );
  };

  render();

  ctx.handleEvent("values", (values) => {
    for (const engine of data.engines) {
      for (const field of engine.fields) field.value = values[engine.id]?.[field.key] ?? null;
    }
    render();
  });

  ctx.handleEvent("verified", ({ engine, ok, message }) => {
    status[engine] = { ok, message };
    render();
  });
}
