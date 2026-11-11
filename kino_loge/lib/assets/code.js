import { viewer } from "./editor.js";
import { mount } from "./form.js";

export function init(ctx, { text, language }) {
  viewer(mount(ctx, `<div class="code"></div>`).firstElementChild, text, language);
}
