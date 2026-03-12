const revealItems = document.querySelectorAll('.reveal');

const revealObserver = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        revealObserver.unobserve(entry.target);
      }
    }
  },
  {
    threshold: 0.12,
  },
);

for (const item of revealItems) {
  revealObserver.observe(item);
}

const yearNode = document.getElementById('current-year');
if (yearNode) {
  yearNode.textContent = String(new Date().getFullYear());
}
