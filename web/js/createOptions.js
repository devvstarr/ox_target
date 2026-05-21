import { fetchNui } from "./fetchNui.js";

const optionsWrapper = document.getElementById("options-wrapper");

function onClick() {
  this.style.pointerEvents = "none";
  fetchNui("select", [this.targetType, this.targetId, this.zoneId]);
  setTimeout(() => (this.style.pointerEvents = "auto"), 100);
}

export function createOptions(type, data, id, zoneId) {
  if (data.hide) return;

  // Split label: first word white, rest green accent
  const words = (data.label ?? "").split(" ");
  const main = words[0] ?? "";
  const accent = words.slice(1).join(" ");

  // Wrapper row (handles accent dot/line)
  const row = document.createElement("div");
  row.className = "option-row";
  
  // Apply theme colors if available
  if (data.theme) {
    row.style.setProperty('--accent-primary', data.theme.primary);
    row.style.setProperty('--accent-light', data.theme.light);
    row.style.setProperty('--accent-bright', data.theme.bright);
    row.style.setProperty('--accent-rgb', data.theme.rgb);
    row.style.setProperty('--icon-color', data.theme.icon || data.theme.primary);
  }

  // Stagger animation based on current child count
  const index = optionsWrapper.children.length;

  row.innerHTML = `
    <div class="accent-col">
      <div class="accent-dot"></div>
      <div class="accent-line"></div>
    </div>
    <div class="option-container" style="animation-delay: ${index * 55}ms">
      <div class="option-icon">
        <i class="fa-solid ${data.icon ?? "fa-circle"}"
          ${data.iconColor ? `style="color: ${data.iconColor} !important"` : ""}
        ></i>
      </div>
      <div class="option-text">
        <span class="option-label-main">${main}</span>
        ${accent ? `<span class="option-label-accent">${accent}</span>` : ""}
      </div>
    </div>
  `;

  const option = row.querySelector(".option-container");
  option.targetType = type;
  option.targetId = id;
  option.zoneId = zoneId;
  if (data.theme) option._themePreview = data.theme;
  option.addEventListener("click", onClick);

  optionsWrapper.appendChild(row);
}
