(() => {
  function fallbackCopy(text) {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.left = "-9999px";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    textarea.remove();
  }

  document.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-copy-command]");
    if (!button) return;

    const command = button.getAttribute("data-copy-command");
    if (!command) return;

    const previousText = button.textContent;
    try {
      if (navigator.clipboard) {
        await navigator.clipboard.writeText(command);
      } else {
        fallbackCopy(command);
      }
      button.textContent = "copied";
      window.setTimeout(() => {
        button.textContent = previousText;
      }, 1400);
    } catch {
      fallbackCopy(command);
      button.textContent = "copied";
      window.setTimeout(() => {
        button.textContent = previousText;
      }, 1400);
    }
  });
})();
