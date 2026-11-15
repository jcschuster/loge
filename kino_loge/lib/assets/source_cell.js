import { mount, field, input, select, assign } from "./form.js";
import { edit } from "./editing.js";

export function init(ctx, data) {
  const app = mount(
    ctx,
    `<div class="panel">
      <div class="header"></div>
      <div class="editor"></div>
      <ul class="diagnostics"></ul>
    </div>`
  );
  const language = select(data.languages, (id) => ctx.pushEvent("set_language", { id }));
  const variable = input("text", (name) => ctx.pushEvent("set_variable", { name }));
  variable.placeholder = "variable";
  app.querySelector(".header").replaceChildren(field("Language", language), field("Bind to", variable));
  const source = edit(ctx, app.querySelector(".editor"), app.querySelector(".diagnostics"), data);

  const render = (setup) => {
    assign(language, setup.language);
    assign(variable, setup.variable);
    source.setLanguage(setup.editor_language);
  };

  render(data);
  ctx.handleEvent("setup", render);
}
