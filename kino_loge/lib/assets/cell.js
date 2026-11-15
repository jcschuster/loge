import { viewer } from "./editor.js";
import { mount, element, field, input, select, assign } from "./form.js";
import { edit } from "./editing.js";

export function init(ctx, data) {
  const app = mount(
    ctx,
    `<div class="panel">
      <div class="header"></div>
      <div class="options"></div>
      <div class="editor"></div>
      <div class="bound"></div>
      <ul class="diagnostics"></ul>
    </div>`
  );
  const header = app.querySelector(".header");
  const options = app.querySelector(".options");
  const own = app.querySelector(".editor");
  const bound = app.querySelector(".bound");
  const list = app.querySelector(".diagnostics");
  const source = edit(ctx, own, list, data);
  let shape = null;
  let shown = null;
  let inputs = {};
  let roles = new Map();
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

  const role = (r) => {
    const el = select(r.choices, (name) => ctx.pushEvent("set_role", { key: r.key, name: name || null }));
    roles.set(r.key, el);
    return field(r.required ? r.label : `${r.label} (optional)`, el);
  };

  const build = (setup) => {
    inputs = {
      language: select(setup.languages, (id) => ctx.pushEvent("set_language", { id })),
      engine: select(setup.engines, (id) => ctx.pushEvent("set_engine", { id })),
      input: select(setup.inputs, (name) => ctx.pushEvent("set_input", { name: name || null })),
      variable: input("text", (name) => ctx.pushEvent("set_variable", { name })),
    };
    inputs.variable.placeholder = "none";
    roles = new Map();
    header.replaceChildren(
      field("Language", inputs.language),
      field("Engine", inputs.engine),
      ...(setup.inputs.length > 1 ? [field("Input", inputs.input)] : []),
      ...setup.roles.map(role),
      field("Bind to", inputs.variable)
    );
    controls = new Map();
    options.replaceChildren(...setup.controls.map(control));
  };

  // A bound input is shown read-only where the editor was; the editor keeps its text.
  const show = (setup) => {
    const next = JSON.stringify([setup.input, setup.input_text, setup.editor_language]);
    if (next === shown) return;
    shown = next;
    own.hidden = list.hidden = setup.input !== null;
    bound.hidden = setup.input === null;
    if (setup.input === null) bound.replaceChildren();
    else if (setup.input_text === null)
      bound.replaceChildren(
        element("p", { className: "empty", textContent: `${setup.input} is not bound: evaluate the cell that binds it.` })
      );
    else {
      bound.replaceChildren();
      viewer(bound, setup.input_text, setup.editor_language);
    }
  };

  const renderSetup = (setup) => {
    const next = JSON.stringify([
      setup.languages,
      setup.engines,
      setup.inputs,
      setup.roles.map(({ value, ...r }) => r),
      setup.engine,
      setup.controls.map(({ value, ...c }) => c),
    ]);
    if (next !== shape) build(setup);
    shape = next;

    assign(inputs.language, setup.language);
    assign(inputs.engine, setup.engine);
    assign(inputs.input, setup.input ?? "");
    for (const r of setup.roles) assign(roles.get(r.key), r.value ?? "");
    assign(inputs.variable, setup.variable);
    for (const c of setup.controls) assign(controls.get(c.key), c.value);
    source.setLanguage(setup.editor_language);
    show(setup);
  };

  renderSetup(data);
  ctx.handleEvent("setup", renderSetup);
}
