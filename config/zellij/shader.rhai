fn shade(r, g, b, x, y, w, h, is_fg) {
    let lch = rgb_to_oklch(r, g, b);
    let l = lch[0];
    let c = lch[1];
    let hue = lch[2];

    // Pane-local coordinates (x,y are screen-global)
    let lx = x % max(w, 1.0);
    let ly = y % max(h, 1.0);

    // --- Vignette: edge darkening ---
    let nx = lx / max(w, 1.0);
    let ny = ly / max(h, 1.0);
    let vx = (nx - 0.5) * 2.0;
    let vy = (ny - 0.5) * 2.0;
    let vdist = sqrt(vx * vx + vy * vy);
    let vignette = clamp(1.2 - vdist * 0.4, 0.55, 1.0);

    // --- Glare: elliptical highlight near top-right, warm tint ---
    let gx = (w * 0.8 - lx) / max(w, 1.0);
    let gy = (ly - h * 0.15) * 2.5 / max(h, 1.0);
    let gdist = sqrt(gx * gx * 0.6 + gy * gy);
    let glare = clamp(1.0 - gdist / 0.8, 0.0, 1.0);
    let glare = glare * glare * glare * 0.55;
    // Warm shift: push hue toward amber in glare zone
    let hue = mix(hue, 70.0, glare * 0.5);

    // --- Scanlines: faint darkening on alternating rows ---
    let scanline = if y % 2.0 < 1.0 { 0.97 } else { 1.0 };

    // --- Noise: pseudo-random per-cell grain ---
    let n = abs(((x * 12.9898 + y * 78.233) * 43758.5453) % 1.0);
    let noise = (n - 0.5) * 0.035;

    // --- Combine ---
    let nl = l * vignette * scanline + noise;

    if is_fg {
        let nc = c * 0.18;
        // Glare washes out toward white
        let nl = clamp(mix(nl, 1.0, glare), 0.0, 1.0);
        let nc = nc * (1.0 - glare);
        let rgb = oklch_to_rgb(nl, nc, hue);
        [clamp(rgb[0], 0.0, 255.0), clamp(rgb[1], 0.0, 255.0), clamp(rgb[2], 0.0, 255.0)]
    } else {
        let nc = c * 0.25;
        let nl = clamp(mix(nl, 0.85, glare), 0.0, 1.0);
        let nc = nc * (1.0 - glare * 0.8);
        let rgb = oklch_to_rgb(nl, nc, hue);
        [clamp(rgb[0], 0.0, 255.0), clamp(rgb[1], 0.0, 255.0), clamp(rgb[2], 0.0, 255.0)]
    }
}
