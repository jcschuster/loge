export function init(ctx, data) {
  ctx.importCSS("main.css");
  ctx.root.innerHTML = `<div class="loge"><div class="loge-setup"></div><ul class="loge-diagnostics"></ul></div>`;
  const setupEl = ctx.root.querySelector(".loge-setup");
  const listEl = ctx.root.querySelector(".loge-diagnostics");

  const field = (label, input) => {
    const wrapper = document.createElement("label");
    wrapper.textContent = label;
    wrapper.append(input);
    return wrapper;
  };

  const select = (options, value, onChange) => {
    const el = document.createElement("select");
    for (const option of options) el.add(new Option(option.label, option.id ?? ""));
    el.value = value ?? "";
    el.addEventListener("change", () => onChange(el.value));
    return el;
  };

  const control = (c) => {
    const push = (value) => ctx.pushEvent("set_option", { key: c.key, value });

    if (c.type === "select") {
      return select(c.choices.map((x) => ({ id: x, label: x })), c.value, push);
    }

    const el = document.createElement("input");

    if (c.type === "boolean") {
      el.type = "checkbox";
      el.checked = c.value === true;
      el.addEventListener("change", () => push(el.checked));
    } else {
      el.type = c.type === "integer" ? "number" : "text";
      el.value = c.value ?? "";
      if (c.choices.length > 0) {
        const list = document.createElement("datalist");
        list.id = `loge-${c.key}`;
        for (const x of c.choices) list.append(new Option(x));
        el.setAttribute("list", list.id);
        el.after(list);
        setupEl.append(list);
      }
      el.addEventListener("change", () => push(el.value));
    }

    return el;
  };

  const renderSetup = (setup) => {
    setupEl.replaceChildren(
      field("Language", select(setup.languages, setup.language, (id) => ctx.pushEvent("set_language", { id }))),
      field(
        "Engine",
        select(
          [...setup.engines, { id: "", label: "None (definitions)" }],
          setup.engine,
          (id) => ctx.pushEvent("set_engine", { id: id === "" ? null : id })
        )
      )
    );

    if (setup.engine === null) {
      const el = document.createElement("input");
      el.value = setup.variable;
      el.placeholder = "variable";
      el.addEventListener("change", () => ctx.pushEvent("set_variable", { name: el.value }));
      setupEl.append(field("Bind to", el));
    }

    for (const c of setup.controls) setupEl.append(field(c.label, control(c)));
  };

  const renderDiagnostics = (diagnostics) => {
    listEl.replaceChildren(
      ...diagnostics.map((d) => {
        const item = document.createElement("li");
        item.className = `loge-${d.severity}`;
        const at = d.column ? `${d.line}:${d.column}` : `${d.line}`;
        item.textContent = `${at} ${d.code} ${d.description}`;
        return item;
      })
    );
  };

  renderSetup(data);
  renderDiagnostics(data.diagnostics);
  ctx.handleEvent("setup", renderSetup);
  ctx.handleEvent("diagnostics", renderDiagnostics);
}
