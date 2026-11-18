import { element } from "./form.js";

export function library(ctx, source) {
  const toggles = element("div", { className: "library-toggles" });
  const query = element("input", { type: "search", className: "input" });
  const entries = element("ul", { className: "library-entries" });
  const status = element("p", { className: "library-status" });
  const panel = element("div", { className: "library", hidden: true }, query, entries, status);
  let shown = "[]";
  let open = null;
  let pending = null;

  const search = () => ctx.pushEvent("search", { library: open.id, query: query.value });

  const toggle = (chosen) => {
    open = open?.id === chosen.id ? null : chosen;
    panel.hidden = open === null;
    entries.replaceChildren();
    status.textContent = "";
    if (open === null) return;
    query.placeholder = `Search the ${open.label}`;
    search();
    query.focus();
  };

  const entry = ({ name, description }) => {
    const button = element(
      "button",
      { type: "button", className: "library-entry" },
      element("span", { className: "library-name", textContent: name }),
      element("span", { className: "library-description", textContent: description })
    );
    button.addEventListener("click", () => {
      status.textContent = `Reading ${name}…`;
      ctx.pushEvent("read", { library: open.id, name });
    });
    return element("li", {}, button);
  };

  query.addEventListener("input", () => {
    clearTimeout(pending);
    pending = setTimeout(search, 200);
  });

  ctx.handleEvent("found", (found) => entries.replaceChildren(...found.map(entry)));
  ctx.handleEvent("file", ({ name, text, error }) => {
    if (error === undefined) source.insert(text);
    status.textContent = error === undefined ? `Inserted ${name}` : `${name}: ${error}`;
  });

  return {
    toggles,
    panel,
    render(libraries) {
      const next = JSON.stringify(libraries);
      if (next === shown) return;
      shown = next;
      open = null;
      panel.hidden = true;
      toggles.replaceChildren(
        ...libraries.map((l) => {
          const button = element("button", { type: "button", className: "button", textContent: l.label });
          button.addEventListener("click", () => toggle(l));
          return button;
        })
      );
    },
  };
}
