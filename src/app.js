// No bundler in this project, so the Tauri API comes from the global that
// `withGlobalTauri` installs rather than from a bare module specifier.
const { invoke } = window.__TAURI__.core;
const { open, save } = window.__TAURI__.dialog;

// ---------------------------------------------------------------- strings

const STRINGS = {
    en: {
        appName: "Sigil",
        tagline: "Put an unsupported NVMe in the PS5 expansion slot.",
        patchAction: "Patch your SSD",
        patchActionBusy: "Patching…",
        chooseOwnImage: "Use my own image",
        chooseOwnImagePrompt: "Choose a header image",
        catalogLoading: "Checking GitHub for published headers…",
        catalogOfflineTitle: "Can't reach GitHub",
        catalogOfflineBody:
            "The published headers could not be fetched. You can still point Sigil at an image file you already have.",
        catalogEmptyTitle: "No header published for current firmware",
        catalogEmptyBody:
            "Nothing has been published for firmware past 4.03 yet. If you already have an image, use it below.",
        catalogSectionLabel: "Published headers",
        retry: "Try again",
        download: "Download",
        contributeQuiet: "Have your own Gen4 NVMe SSD and want to dump from it? Click here",
        contributeNeedsDrive:
            "Connect the drive in a USB enclosure and pick it under Connected drives first.",
        driveSectionLabel: "Connected drives",
        noDriveTitle: "No external drive connected",
        noDriveBody: "Connect the NVMe in a USB enclosure and it shows up here.",
        internalExcluded: "Internal and boot volumes are never listed.",
        rescan: "Scan again",
        confirmWrite: (image, drive, path) =>
            `Write ${image} to ${drive} (${path})?\n\nThis overwrites the beginning of the destination drive and cannot be undone. Check the disk identifier before continuing.`,
        succeeded: "Done. Put the drive in the console and see if it mounts.",
        captureDone: "Saved. A draft is open in your mail app — attach the file it revealed.",
        cancelled: "Cancelled.",
    },
    pt: {
        appName: "Sigil",
        tagline: "Use um NVMe sem suporte no slot de expansão do PS5.",
        patchAction: "Preparar seu SSD",
        patchActionBusy: "Preparando…",
        chooseOwnImage: "Usar imagem própria",
        chooseOwnImagePrompt: "Escolha uma imagem de cabeçalho",
        catalogLoading: "Procurando cabeçalhos publicados no GitHub…",
        catalogOfflineTitle: "Não deu para acessar o GitHub",
        catalogOfflineBody:
            "Os cabeçalhos publicados não puderam ser baixados. Você ainda pode apontar o Sigil para um arquivo de imagem que já tenha.",
        catalogEmptyTitle: "Nenhum cabeçalho publicado para os firmwares atuais",
        catalogEmptyBody:
            "Ainda não há nada publicado para firmware acima do 4.03. Se você já tem uma imagem, use ela abaixo.",
        catalogSectionLabel: "Cabeçalhos publicados",
        retry: "Tentar de novo",
        download: "Baixar",
        contributeQuiet: "Tem seu próprio SSD NVMe Gen4 e quer dumpar dele? Clique aqui",
        contributeNeedsDrive:
            "Ligue o drive numa case USB e escolha ele em Drives conectados primeiro.",
        driveSectionLabel: "Drives conectados",
        noDriveTitle: "Nenhum drive externo conectado",
        noDriveBody: "Ligue o NVMe numa case USB e ele aparece aqui.",
        internalExcluded: "Volumes internos e de inicialização nunca são listados.",
        rescan: "Procurar de novo",
        confirmWrite: (image, drive, path) =>
            `Gravar ${image} em ${drive} (${path})?\n\nIsto sobrescreve o começo do drive de destino e não tem volta. Confira o identificador do disco antes de continuar.`,
        succeeded: "Pronto. Ponha o drive no console e veja se ele monta.",
        captureDone: "Salvo. Abriu um rascunho no seu app de e-mail — anexe o arquivo revelado.",
        cancelled: "Cancelado.",
    },
};

// System language decides the default; the choice is remembered after that.
const stored = localStorage.getItem("language");
let language =
    stored ?? ((navigator.language ?? "en").toLowerCase().startsWith("pt") ? "pt" : "en");

const t = (key) => STRINGS[language][key];

// ---------------------------------------------------------------- state

const state = {
    drives: [],
    selected: null,
    image: null,
    busy: false,
};

const el = {
    language: document.getElementById("language"),
    mark: document.getElementById("mark"),
    catalog: document.getElementById("catalog"),
    picked: document.getElementById("picked"),
    patch: document.getElementById("patch"),
    pick: document.getElementById("pick"),
    capture: document.getElementById("capture"),
    notice: document.getElementById("notice"),
    driveList: document.getElementById("driveList"),
};

function applyStrings() {
    document.documentElement.lang = language;
    for (const node of document.querySelectorAll("[data-i18n]")) {
        node.textContent = t(node.dataset.i18n);
    }
    el.patch.textContent = state.busy ? t("patchActionBusy") : t("patchAction");
}

function setBusy(busy) {
    state.busy = busy;
    el.mark.classList.toggle("busy", busy);
    render();
}

function notify(message) {
    el.notice.textContent = message ?? "";
    el.notice.hidden = !message;
}

function render() {
    applyStrings();

    el.patch.disabled = !state.image || !state.selected || state.busy;
    el.pick.disabled = state.busy;
    el.capture.disabled = state.busy;

    el.picked.hidden = !state.image;
    if (state.image) el.picked.textContent = state.image.split(/[\\/]/).pop();

    renderDrives();
}

// ---------------------------------------------------------------- drives

function renderDrives() {
    el.driveList.replaceChildren();

    if (state.drives.length === 0) {
        const empty = document.createElement("div");
        empty.className = "empty";
        empty.innerHTML = `<p class="title"></p><p class="body"></p>`;
        empty.querySelector(".title").textContent = t("noDriveTitle");
        empty.querySelector(".body").textContent = t("noDriveBody");

        const again = document.createElement("button");
        again.className = "link";
        again.textContent = t("rescan");
        again.addEventListener("click", rescan);
        empty.append(again);

        el.driveList.append(empty);
        return;
    }

    for (const drive of state.drives) {
        const row = document.createElement("button");
        row.className = "row";
        row.setAttribute("aria-pressed", String(state.selected === drive.id));
        row.innerHTML = `<span class="dot"></span><span><span class="name"></span><br><span class="path"></span></span><span class="size"></span>`;
        row.querySelector(".name").textContent = drive.name;
        row.querySelector(".path").textContent = drive.device_path;
        row.querySelector(".size").textContent = formatBytes(drive.byte_size);
        row.addEventListener("click", () => {
            state.selected = state.selected === drive.id ? null : drive.id;
            render();
        });
        el.driveList.append(row);
    }

    const footnote = document.createElement("p");
    footnote.className = "empty";
    footnote.style.marginTop = "12px";
    footnote.innerHTML = `<p></p>`;
    footnote.querySelector("p").textContent = t("internalExcluded");
    el.driveList.append(footnote);
}

function formatBytes(bytes) {
    const units = ["B", "KB", "MB", "GB", "TB"];
    let value = bytes;
    let unit = 0;
    while (value >= 1000 && unit < units.length - 1) {
        value /= 1000;
        unit += 1;
    }
    return `${value.toFixed(value >= 100 || unit === 0 ? 0 : 1)} ${units[unit]}`;
}

async function rescan() {
    try {
        state.drives = await invoke("list_drives");
        if (!state.drives.some((drive) => drive.id === state.selected)) state.selected = null;
    } catch (error) {
        state.drives = [];
        notify(String(error));
    }
    render();
}

// ---------------------------------------------------------------- catalog

function panel(title, body, detail) {
    const node = document.createElement("div");
    node.className = "panel";
    node.innerHTML = `<h3></h3><p></p>`;
    node.querySelector("h3").textContent = title;
    node.querySelector("p").textContent = body;
    if (detail) {
        const line = document.createElement("p");
        line.className = "detail";
        line.textContent = detail;
        node.append(line);
    }
    return node;
}

async function loadCatalog() {
    el.catalog.replaceChildren(panel("", t("catalogLoading")));

    let entries;
    try {
        entries = await invoke("load_catalog");
    } catch (error) {
        const node = panel(t("catalogOfflineTitle"), t("catalogOfflineBody"), String(error));
        const again = document.createElement("button");
        again.className = "link";
        again.style.marginTop = "10px";
        again.textContent = t("retry");
        again.addEventListener("click", loadCatalog);
        node.append(again);
        el.catalog.replaceChildren(node);
        return;
    }

    if (entries.length === 0) {
        el.catalog.replaceChildren(panel(t("catalogEmptyTitle"), t("catalogEmptyBody")));
        return;
    }

    const list = document.createElement("div");
    const heading = document.createElement("h2");
    heading.className = "label";
    heading.textContent = t("catalogSectionLabel");
    list.append(heading);

    for (const entry of entries) {
        const row = document.createElement("div");
        row.className = "row";
        row.innerHTML = `<span><span class="name"></span><br><span class="path"></span></span>`;
        row.querySelector(".name").textContent = entry.title;
        row.querySelector(".path").textContent =
            `${entry.firmware} · ${formatBytes(entry.byte_size)}`;

        const get = document.createElement("button");
        get.className = "link";
        get.style.marginLeft = "auto";
        get.textContent = t("download");
        get.addEventListener("click", () => downloadHeader(entry));
        row.append(get);
        list.append(row);
    }
    el.catalog.replaceChildren(list);
}

async function downloadHeader(entry) {
    setBusy(true);
    notify(null);
    try {
        state.image = await invoke("download_header", { entry });
    } catch (error) {
        notify(String(error));
    }
    setBusy(false);
}

// ---------------------------------------------------------------- actions

el.pick.addEventListener("click", async () => {
    const chosen = await open({ multiple: false, title: t("chooseOwnImagePrompt") });
    if (!chosen) return;
    state.image = chosen;
    notify(null);
    render();
});

el.patch.addEventListener("click", async () => {
    const drive = state.drives.find((candidate) => candidate.id === state.selected);
    if (!drive || !state.image) return;

    const name = state.image.split(/[\\/]/).pop();
    if (!confirm(t("confirmWrite")(name, drive.name, drive.device_path))) return;

    setBusy(true);
    notify(null);
    try {
        await invoke("write_header", { image: state.image, driveId: drive.id });
        notify(t("succeeded"));
    } catch (error) {
        notify(String(error).includes("cancelled") ? t("cancelled") : String(error));
    }
    setBusy(false);
});

// Stays live with no drive selected on purpose: disabling it made the copy
// promise an action and then do nothing at all when clicked.
el.capture.addEventListener("click", async () => {
    const drive = state.drives.find((candidate) => candidate.id === state.selected);
    if (!drive) {
        notify(t("contributeNeedsDrive"));
        return;
    }

    const destination = await save({ defaultPath: `${drive.id}-header.img` });
    if (!destination) return;

    setBusy(true);
    notify(null);
    try {
        const path = await invoke("capture_header", { driveId: drive.id, destination });
        await invoke("open_contribution", { path, driveName: drive.name, language });
        notify(t("captureDone"));
    } catch (error) {
        notify(String(error).includes("cancelled") ? t("cancelled") : String(error));
    }
    setBusy(false);
});

el.language.addEventListener("change", (event) => {
    language = event.target.value;
    localStorage.setItem("language", language);
    render();
    loadCatalog();
});

// ---------------------------------------------------------------- backdrop

const SYMBOLS = [
    ["triangle", 0.06, 0.085, 38, 0.0, 46, 2.0, 0.85],
    ["circle", 0.13, 0.13, 52, 0.42, -70, 1.7, 0.65],
    ["cross", 0.02, 0.07, 44, 0.71, 38, 2.2, 0.75],
    ["square", 0.17, 0.055, 33, 0.18, -52, 1.8, 0.55],
    ["square", 0.94, 0.1, 48, 0.11, 60, 1.9, 0.8],
    ["cross", 0.87, 0.075, 36, 0.55, -42, 2.1, 0.7],
    ["triangle", 0.98, 0.06, 41, 0.86, 55, 1.8, 0.6],
    ["circle", 0.83, 0.15, 58, 0.3, -80, 1.6, 0.5],
    // Far background: small and faint enough to pass behind the centre column
    // without fighting the text.
    ["triangle", 0.34, 0.032, 66, 0.63, 90, 1.2, 0.3],
    ["circle", 0.66, 0.028, 74, 0.24, -96, 1.2, 0.26],
    ["cross", 0.5, 0.03, 62, 0.91, 84, 1.2, 0.24],
    ["square", 0.26, 0.026, 70, 0.07, -88, 1.2, 0.28],
];

function startField() {
    const canvas = document.getElementById("field");
    const context = canvas.getContext("2d");
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let width = 0;
    let height = 0;

    function resize() {
        const ratio = window.devicePixelRatio || 1;
        width = canvas.clientWidth;
        height = canvas.clientHeight;
        canvas.width = width * ratio;
        canvas.height = height * ratio;
        context.setTransform(ratio, 0, 0, ratio, 0, 0);
    }

    function draw(now) {
        const time = reduced ? 0 : now / 1000;
        const unit = Math.min(width, height);
        context.clearRect(0, 0, width, height);
        context.strokeStyle = "#ffffff";
        context.lineCap = "round";
        context.lineJoin = "round";

        for (const [kind, column, extent, fall, phase, spin, weight, alpha] of SYMBOLS) {
            const side = extent * unit;
            // Adding the phase inside the modulo is what keeps the loop
            // seamless instead of snapping when the cycle restarts.
            const progress = (time / fall + phase) % 1;
            const y = -0.12 * height + progress * height * 1.24;
            const sway = Math.sin(progress * Math.PI * 2 + phase * 6) * side * 0.35;

            context.save();
            context.globalAlpha = alpha;
            context.lineWidth = weight;
            context.translate(column * width + sway, y);
            context.rotate((time * Math.PI * 2) / spin + phase * 4);
            trace(context, kind, side);
            context.restore();
        }

        if (!reduced) requestAnimationFrame(draw);
    }

    function trace(ctx, kind, side) {
        const half = side / 2;
        ctx.beginPath();
        if (kind === "triangle") {
            ctx.moveTo(0, -half * 0.88);
            ctx.lineTo(half * 0.88, half * 0.8);
            ctx.lineTo(-half * 0.88, half * 0.8);
            ctx.closePath();
        } else if (kind === "circle") {
            ctx.arc(0, 0, half * 0.88, 0, Math.PI * 2);
        } else if (kind === "cross") {
            const arm = half * 0.72;
            ctx.moveTo(-arm, -arm);
            ctx.lineTo(arm, arm);
            ctx.moveTo(arm, -arm);
            ctx.lineTo(-arm, arm);
        } else {
            const s = half * 0.8;
            ctx.roundRect(-s, -s, s * 2, s * 2, side * 0.06);
        }
        ctx.stroke();
    }

    resize();
    window.addEventListener("resize", resize);
    requestAnimationFrame(draw);
}

// ---------------------------------------------------------------- boot

el.language.value = language;
applyStrings();
startField();
render();
rescan();
loadCatalog();
