(() => {
  const REPO = "soumyachk101/Ensembyte";
  const RELEASES_PAGE = `https://github.com/${REPO}/releases`;
  const LATEST_DOWNLOAD = `${RELEASES_PAGE}/latest/download/`;

  const MAC_DIRECT = `${LATEST_DOWNLOAD}Ensembyte.dmg`;
  const WIN_DIRECT = `${LATEST_DOWNLOAD}ensembyte-1.0.0-windows-x86_64-setup.exe`;
  const LINUX_DIRECT = `${LATEST_DOWNLOAD}ensembyte-1.0.0-linux-x86_64.tar.gz`;
  const LINUX_ARM_DIRECT = `${LATEST_DOWNLOAD}ensembyte-1.0.0-linux-aarch64.tar.gz`;

  const ua = navigator.userAgent || "";
  const platform = navigator.userAgentData?.platform || navigator.platform || "";
  const mobile = /Android|iPhone|iPad|iPod/i.test(ua) || navigator.userAgentData?.mobile
    || (/Mac/i.test(platform) && navigator.maxTouchPoints > 1);
  const os = mobile ? null : /Win/i.test(platform) ? "windows"
    : /Mac/i.test(platform) ? "macos" : /Linux/i.test(platform)
    ? (/aarch64|arm64/i.test(`${platform} ${ua}`) ? "linux-arm" : "linux") : null;

  const applyLinks = (info) => {
    const { version, macUrl, winUrl, linuxUrl, linuxArmUrl } = info;

    // Platform-specific direct download buttons in downloads section
    const macLink = document.querySelector('[data-platform-download="macos"]');
    if (macLink) {
      macLink.href = macUrl || MAC_DIRECT;
      macLink.textContent = "Download";
    }

    const winLink = document.querySelector('[data-platform-download="windows"]');
    if (winLink) {
      winLink.href = winUrl || WIN_DIRECT;
      winLink.textContent = "Download";
      const meta = winLink.parentElement?.querySelector(".dl-meta");
      if (meta) meta.textContent = "x64 · executable (.exe)";
    }

    const linuxLink = document.querySelector('[data-platform-download="linux"]');
    if (linuxLink) {
      linuxLink.href = linuxUrl || LINUX_DIRECT;
      linuxLink.textContent = "Download";
      const meta = linuxLink.parentElement?.querySelector(".dl-meta");
      if (meta) meta.textContent = "x64 · tar.gz";
    }

    const linuxArmLink = document.querySelector('[data-platform-download="linux-arm"]');
    if (linuxArmLink) {
      linuxArmLink.href = linuxArmUrl || LINUX_ARM_DIRECT;
      linuxArmLink.textContent = "Download";
      const meta = linuxArmLink.parentElement?.querySelector(".dl-meta");
      if (meta) meta.textContent = "arm64 · tar.gz";
    }

    // Hero, nav, and closing CTA direct download buttons
    let mainHref = MAC_DIRECT;
    let mainLabel = "Download";
    let mainDetail = "Apple silicon · dmg";

    if (os === "macos") {
      mainHref = macUrl || MAC_DIRECT;
      mainLabel = "Download for macOS";
      mainDetail = "Apple silicon · dmg";
    } else if (os === "windows") {
      mainHref = winUrl || WIN_DIRECT;
      mainLabel = "Download for Windows";
      mainDetail = "Windows x64 (.exe)";
    } else if (os === "linux") {
      mainHref = linuxUrl || LINUX_DIRECT;
      mainLabel = "Download for Linux";
      mainDetail = "Linux x64";
    } else if (os === "linux-arm") {
      mainHref = linuxArmUrl || LINUX_ARM_DIRECT;
      mainLabel = "Download for Linux";
      mainDetail = "Linux ARM64";
    }

    const nav = document.getElementById("nav-download");
    if (nav) {
      nav.href = mainHref;
      nav.textContent = "Download";
    }

    const hero = document.getElementById("hero-download");
    if (hero) {
      hero.href = mainHref;
      hero.textContent = mainLabel;
      hero.setAttribute("aria-label", `${mainLabel} (${mainDetail})`);
      hero.title = mainDetail;
    }

    const closing = document.getElementById("closing-download");
    if (closing) {
      closing.href = mainHref;
      closing.textContent = mainLabel;
      closing.setAttribute("aria-label", `${mainLabel} (${mainDetail})`);
      closing.title = mainDetail;
    }

    const verEl = document.getElementById("ver");
    if (verEl && version) {
      verEl.textContent = version.startsWith("v") ? version : `v${version}`;
    }
  };

  // Set direct downloads immediately so clicking always triggers file download
  applyLinks({
    version: "1.1.2",
    macUrl: MAC_DIRECT,
    winUrl: WIN_DIRECT,
    linuxUrl: LINUX_DIRECT,
    linuxArmUrl: LINUX_ARM_DIRECT,
  });

  // Query GitHub API to get dynamic latest release assets if updated
  fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { credentials: "omit" })
    .then((r) => r.ok ? r.json() : Promise.reject())
    .then((release) => {
      if (!release || !Array.isArray(release.assets)) return;
      const tag = release.tag_name || "1.1.2";
      const cleanVer = tag.replace(/^v/, "");
      const assets = release.assets;

      const macAsset = assets.find((a) => a.name === "Orbit.dmg")
        || assets.find((a) => a.name.toLowerCase().endsWith(".dmg"));
      const winAsset = assets.find((a) => a.name.toLowerCase().endsWith(".exe"))
        || assets.find((a) => a.name.toLowerCase().includes("windows") && a.name.toLowerCase().endsWith(".zip"));
      const linuxAsset = assets.find((a) => a.name.toLowerCase().includes("linux-x86_64") || (a.name.toLowerCase().includes("linux") && !a.name.toLowerCase().includes("aarch64") && !a.name.toLowerCase().includes("arm")));
      const linuxArmAsset = assets.find((a) => a.name.toLowerCase().includes("linux-aarch64") || a.name.toLowerCase().includes("linux-arm64"));

      applyLinks({
        version: tag,
        macUrl: macAsset ? macAsset.browser_download_url : MAC_DIRECT,
        winUrl: winAsset ? winAsset.browser_download_url : `${LATEST_DOWNLOAD}orbit-${cleanVer}-windows-x86_64.exe`,
        linuxUrl: linuxAsset ? linuxAsset.browser_download_url : `${LATEST_DOWNLOAD}orbit-${cleanVer}-linux-x86_64.tar.gz`,
        linuxArmUrl: linuxArmAsset ? linuxArmAsset.browser_download_url : `${LATEST_DOWNLOAD}orbit-${cleanVer}-linux-aarch64.tar.gz`,
      });
    })
    .catch(() => {});
})();
