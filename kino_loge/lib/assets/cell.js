import { mount, element, field, input, select, assign } from "./form.js";

export function init(ctx, data) {
  const app = mount(
    ctx,
    `<div class="panel panel--top">
      <div class="header"></div>
      <div class="options"></div>
      <ul class="diagnostics"></ul>
    </div>`
  );
  const header = app.querySelector(".header");
  const options = app.querySelector(".options");
  const list = app.querySelector(".diagnostics");
  let shape = null;
  let inputs = {};
  let controls = new Map();

  const suggestions = (c, el) => {
    if (c.type !== "text" || c.choices.length === 0) return [];
    const id = `loge-${c.key}`;
    el.setAttribute("list", id);
    return [element("datalist", { id }, ...c.choices.map((x) => new Option(x)))];
  };

  const control = (c) => {
    const push = (value) => ctx.pushEvent("set_option", { key: c.key, value });
    const el =
      c.type === "select" ? select(c.choices.map((x) => ({ id: x, label: x })), push) : input(c.type, push);
    controls.set(c.key, el);
    return field(c.label, el, ...suggestions(c, el));
  };

  const build = (setup) => {
    inputs = {
      language: select(setup.languages, (id) => ctx.pushEvent("set_language", { id })),
      engine: select([...setup.engines, { id: "", label: "None (definitions)" }], (id) =>
        ctx.pushEvent("set_engine", { id: id || null })
      ),
    };
    header.replaceChildren(field("Language", inputs.language), field("Engine", inputs.engine));

    if (setup.engine === null) {
      inputs.variable = input("text", (name) => ctx.pushEvent("set_variable", { name }));
      inputs.variable.placeholder = "variable";
      header.append(field("Bind to", inputs.variable));
    }

    controls = new Map();
    options.replaceChildren(...setup.controls.map(control));
  };

  const renderSetup = (setup) => {
    const next = JSON.stringify([
      setup.languages,
      setup.engines,
      setup.engine,
      setup.controls.map(({ value, ...c }) => c),
    ]);
    if (next !== shape) build(setup);
    shape = next;

    assign(inputs.language, setup.language);
    assign(inputs.engine, setup.engine ?? "");
    if (inputs.variable) assign(inputs.variable, setup.variable);
    for (const c of setup.controls) assign(controls.get(c.key), c.value);
  };

  const renderDiagnostics = (diagnostics) => {
    list.replaceChildren(
      ...diagnostics.map((d) =>
        element(
          "li",
          { className: `diagnostic diagnostic--${d.severity}` },
          element("span", { className: "severity", textContent: d.severity }),
          element("span", { className: "position", textContent: d.column ? `${d.line}:${d.column}` : `${d.line}` }),
          element("span", { className: "message", textContent: d.description }),
          element("span", { className: "code", textContent: d.code })
        )
      )
    );
  };

  renderSetup(data);
  renderDiagnostics(data.diagnostics);
  ctx.handleEvent("setup", renderSetup);
  ctx.handleEvent("diagnostics", renderDiagnostics);
}
