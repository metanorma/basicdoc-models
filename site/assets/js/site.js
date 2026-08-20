(() => {
  const chips = [...document.querySelectorAll("[data-domain-filter]")];
  const cards = [...document.querySelectorAll("[data-plate]")];
  const search = document.querySelector("[data-plate-search]");
  const empty = document.querySelector("[data-empty-state]");
  if (!chips.length || !cards.length) return;

  let active = "all";
  let query = "";

  const apply = () => {
    let visible = 0;
    for (const card of cards) {
      const domains = (card.getAttribute("data-domains") || "")
        .split(",")
        .filter(Boolean);
      const hay = (card.getAttribute("data-search") || "").toLowerCase();
      const domainOk = active === "all" || domains.includes(active);
      const queryOk = !query || hay.includes(query);
      const show = domainOk && queryOk;
      card.classList.toggle("is-hidden", !show);
      if (show) visible += 1;
    }
    if (empty) empty.classList.toggle("is-visible", visible === 0);
  };

  for (const chip of chips) {
    chip.addEventListener("click", () => {
      active = chip.getAttribute("data-domain-filter") || "all";
      for (const c of chips) {
        c.setAttribute("aria-pressed", String(c === chip));
      }
      apply();
    });
  }

  if (search) {
    search.addEventListener("input", () => {
      query = search.value.trim().toLowerCase();
      apply();
    });
  }
})();
