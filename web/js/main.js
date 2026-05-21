import { createOptions } from "./createOptions.js";
import { fetchNui } from "./fetchNui.js";

const optionsWrapper = document.getElementById("options-wrapper");
const body = document.body;
const html = document.documentElement;
const eye = document.getElementById("eyeSvg");

html.style.background = "transparent";
html.style.backgroundColor = "transparent";
html.style.backgroundImage = "none";
html.style.margin = "0";
html.style.padding = "0";
body.style.background = "transparent";
body.style.backgroundColor = "transparent";
body.style.backgroundImage = "none";
body.style.margin = "0";
body.style.padding = "0";

const themes = {
  green:  { primary: '#80ff49', light: '#a5ff66', bright: '#d4ff99', rgb: '128, 255, 73',  icon: '#8cff50' },
  gold:   { primary: '#ffd700', light: '#ffeb99', bright: '#ffeb99', rgb: '255, 215, 0',   icon: '#ffd700' },
  blue:   { primary: '#00bfff', light: '#1e90ff', bright: '#87ceeb', rgb: '0, 191, 255',   icon: '#1e90ff' },
  purple: { primary: '#da70d6', light: '#ee82ee', bright: '#ff69b4', rgb: '218, 112, 214', icon: '#ee82ee' },
  red:    { primary: '#ff4444', light: '#ff6b6b', bright: '#ff8888', rgb: '255, 68, 68',   icon: '#ff6b6b' },
  cyan:   { primary: '#00ffff', light: '#00eeee', bright: '#7ffbff', rgb: '0, 255, 255',   icon: '#00ffff' },
  orange: { primary: '#ff8800', light: '#ffaa44', bright: '#ffcc88', rgb: '255, 136, 0',   icon: '#ffaa44' },
  pink:   { primary: '#ff69b4', light: '#ff85c2', bright: '#ffb3d9', rgb: '255, 105, 180', icon: '#ff85c2' },
  white:  { primary: '#e0e0e0', light: '#f0f0f0', bright: '#ffffff', rgb: '224, 224, 224', icon: '#f0f0f0' },
  teal:   { primary: '#00b4b4', light: '#00cccc', bright: '#66dddd', rgb: '0, 180, 180',   icon: '#00cccc' },
};

function setTheme(theme) {
  const root = document.documentElement;
  if (themes[theme]) {
    const t = themes[theme];
    root.style.setProperty('--accent-primary', t.primary);
    root.style.setProperty('--accent-light', t.light);
    root.style.setProperty('--accent-bright', t.bright);
    root.style.setProperty('--accent-rgb', t.rgb);
    root.style.setProperty('--icon-color', t.icon);
  }
}

// Set default green theme
setTheme('green');

let _savedRootTheme = null;

function captureRootTheme() {
  const s = getComputedStyle(document.documentElement);
  return {
    primary: s.getPropertyValue('--accent-primary').trim(),
    light:   s.getPropertyValue('--accent-light').trim(),
    bright:  s.getPropertyValue('--accent-bright').trim(),
    rgb:     s.getPropertyValue('--accent-rgb').trim(),
    icon:    s.getPropertyValue('--icon-color').trim(),
  };
}

function applyRootVars(t) {
  const root = document.documentElement;
  root.style.setProperty('--accent-primary', t.primary);
  root.style.setProperty('--accent-light',   t.light);
  root.style.setProperty('--accent-bright',  t.bright);
  root.style.setProperty('--accent-rgb',     t.rgb);
  root.style.setProperty('--icon-color',     t.icon || t.primary);
}

function applyThemeToAllRows(t) {
  optionsWrapper.querySelectorAll('.option-row').forEach(row => {
    row.style.setProperty('--accent-primary', t.primary);
    row.style.setProperty('--accent-light',   t.light);
    row.style.setProperty('--accent-bright',  t.bright);
    row.style.setProperty('--accent-rgb',     t.rgb);
    row.style.setProperty('--icon-color',     t.icon || t.primary);
  });
  applyRootVars(t);
}

function restoreRowThemes() {
  optionsWrapper.querySelectorAll('.option-row').forEach(row => {
    const t = row.querySelector('.option-container')?._themePreview;
    if (t) {
      row.style.setProperty('--accent-primary', t.primary);
      row.style.setProperty('--accent-light',   t.light);
      row.style.setProperty('--accent-bright',  t.bright);
      row.style.setProperty('--accent-rgb',     t.rgb);
      row.style.setProperty('--icon-color',     t.icon || t.primary);
    }
  });
  if (_savedRootTheme) applyRootVars(_savedRootTheme);
}

optionsWrapper.addEventListener('mouseover', (e) => {
  const container = e.target.closest('.option-container');
  if (!container?._themePreview) return;
  if (container.contains(e.relatedTarget)) return;
  if (!_savedRootTheme) _savedRootTheme = captureRootTheme();
  applyThemeToAllRows(container._themePreview);
});

optionsWrapper.addEventListener('mouseout', (e) => {
  const container = e.target.closest('.option-container');
  if (!container?._themePreview) return;
  if (container.contains(e.relatedTarget)) return;
  restoreRowThemes();
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    fetchNui("close");
  }
});

window.addEventListener("message", (event) => {
  switch (event.data.event) {
    case "visible": {
      _savedRootTheme = null;
      if (!event.data.state) {
        const rows = optionsWrapper.querySelectorAll('.option-row');
        rows.forEach((row, i) => {
          row.style.setProperty('animation-delay', `${i * 20}ms`);
          row.classList.add('slide-out');
        });
        setTimeout(() => {
          optionsWrapper.innerHTML = "";
          body.style.visibility = "hidden";
          document.documentElement.style.visibility = "hidden";
          body.style.display = "none";
          document.documentElement.style.display = "none";
          eye.classList.remove("eye-hover");
        }, rows.length * 20 + 200);
      } else {
        optionsWrapper.innerHTML = "";
        body.style.visibility = "visible";
        document.documentElement.style.visibility = "visible";
        body.style.display = "block";
        document.documentElement.style.display = "block";
        body.style.background = "transparent";
        body.style.backgroundColor = "transparent";
        document.documentElement.style.background = "transparent";
        document.documentElement.style.backgroundColor = "transparent";
        eye.classList.remove("eye-hover");
      }
      return;
    }

    case "setTheme": {
      setTheme(event.data.theme);
      return;
    }

    case "leftTarget": {
      _savedRootTheme = null;
      optionsWrapper.innerHTML = "";
      return eye.classList.remove("eye-hover");
    }

    case "setTarget": {
      optionsWrapper.innerHTML = "";
      eye.classList.add("eye-hover");

      if (event.data.header) {
        const header = document.createElement("div");
        header.className = "menu-header";
        header.textContent = event.data.header;
        optionsWrapper.appendChild(header);
      }

      if (event.data.options) {
        for (const type in event.data.options) {
          event.data.options[type].forEach((data, id) => {
            createOptions(type, data, id + 1);
          });
        }
      }

      if (event.data.zones) {
        for (let i = 0; i < event.data.zones.length; i++) {
          event.data.zones[i].forEach((data, id) => {
            createOptions("zones", data, id + 1, i + 1);
          });
        }
      }
    }
  }
});
