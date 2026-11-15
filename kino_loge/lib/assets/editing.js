import { editor } from "./editor.js";
import { element, sync } from "./form.js";

export function edit(ctx, parent, list, data) {
  const source = editor(parent, data, (edit) => ctx.pushEvent("push", edit));

  const render = (diagnostics) => {
    source.setDiagnostics(diagnostics);
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

  render(data.diagnostics);
  ctx.handleEvent("diagnostics", render);
  ctx.handleEvent("updates", source.receive);
  ctx.handleSync(() => {
    sync();
    return source.synced();
  });
  return source;
}
