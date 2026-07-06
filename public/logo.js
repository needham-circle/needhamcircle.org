(function () {
  "use strict";

  var brand = document.querySelector(".site-brand");
  var logo = brand && brand.querySelector(".logo");
  if (!logo || !logo.animate) return;

  var figures = Array.prototype.slice.call(logo.querySelectorAll(".figure"));

  brand.addEventListener("mouseenter", function () {
    figures.forEach(function (figure) {
      if (figure._settle) {
        figure._settle.cancel();
        figure._settle = null;
      }
    });
    logo.classList.add("rocking");
  });

  brand.addEventListener("mouseleave", function () {
    var froms = figures.map(function (figure) {
      return getComputedStyle(figure).transform;
    });

    logo.classList.remove("rocking");

    figures.forEach(function (figure, idx) {
      if (froms[idx] === "none") return;

      figure._settle = figure.animate(
        [{ transform: froms[idx] }, { transform: "rotate(0deg)" }],
        { duration: 400, easing: "ease-out" }
      );
    });
  });
})();
