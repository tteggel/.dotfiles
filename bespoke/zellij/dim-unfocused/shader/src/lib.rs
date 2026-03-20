#![no_std]

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}

// --- Color space math ---

fn srgb_to_linear(c: f32) -> f32 {
    let c = c / 255.0;
    if c <= 0.04045 {
        c / 12.92
    } else {
        powf((c + 0.055) / 1.055, 2.4)
    }
}

fn linear_to_srgb(c: f32) -> f32 {
    let c = clamp(c, 0.0, 1.0);
    if c <= 0.0031308 {
        c * 12.92
    } else {
        1.055 * powf(c, 1.0 / 2.4) - 0.055
    }
}

fn rgb_to_oklch(r: f32, g: f32, b: f32) -> (f32, f32, f32) {
    let rl = srgb_to_linear(r);
    let gl = srgb_to_linear(g);
    let bl = srgb_to_linear(b);

    let l_ = 0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl;
    let m_ = 0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl;
    let s_ = 0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl;

    let l_ = cbrtf(l_);
    let m_ = cbrtf(m_);
    let s_ = cbrtf(s_);

    let lab_l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
    let lab_a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    let lab_b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;

    let c = sqrtf(lab_a * lab_a + lab_b * lab_b);
    let mut h = atan2f(lab_b, lab_a) * (180.0 / core::f32::consts::PI);
    if h < 0.0 {
        h += 360.0;
    }
    (lab_l, c, h)
}

fn oklch_to_rgb(l: f32, c: f32, h: f32) -> (f32, f32, f32) {
    let h_rad = h * (core::f32::consts::PI / 180.0);
    let lab_a = c * cosf(h_rad);
    let lab_b = c * sinf(h_rad);

    let l_ = l + 0.3963377774 * lab_a + 0.2158037573 * lab_b;
    let m_ = l - 0.1055613458 * lab_a - 0.0638541728 * lab_b;
    let s_ = l - 0.0894841775 * lab_a - 1.2914855480 * lab_b;

    let l_ = l_ * l_ * l_;
    let m_ = m_ * m_ * m_;
    let s_ = s_ * s_ * s_;

    let rl = 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_;
    let gl = -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_;
    let bl = -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_;

    (
        linear_to_srgb(rl) * 255.0,
        linear_to_srgb(gl) * 255.0,
        linear_to_srgb(bl) * 255.0,
    )
}

// --- no_std math helpers ---

fn clamp(x: f32, lo: f32, hi: f32) -> f32 {
    if x < lo {
        lo
    } else if x > hi {
        hi
    } else {
        x
    }
}

fn mix(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

fn absf(x: f32) -> f32 {
    if x < 0.0 { -x } else { x }
}

fn maxf(a: f32, b: f32) -> f32 {
    if a > b { a } else { b }
}

// Approximate sqrt via Newton's method
fn sqrtf(x: f32) -> f32 {
    if x <= 0.0 {
        return 0.0;
    }
    // Use bit manipulation for initial guess
    let i = x.to_bits();
    let i = 0x1FBD1DF5 + (i >> 1);
    let mut y = f32::from_bits(i);
    // Newton iterations
    y = 0.5 * (y + x / y);
    y = 0.5 * (y + x / y);
    y = 0.5 * (y + x / y);
    y
}

// Approximate cbrt
fn cbrtf(x: f32) -> f32 {
    if x == 0.0 {
        return 0.0;
    }
    let sign = if x < 0.0 { -1.0f32 } else { 1.0f32 };
    let x = absf(x);
    // Initial guess via bit manipulation
    let i = x.to_bits();
    let i = i / 3 + 0x2A508C2F;
    let mut y = f32::from_bits(i);
    // Halley iterations for cbrt
    y = y - (y * y * y - x) / (3.0 * y * y);
    y = y - (y * y * y - x) / (3.0 * y * y);
    y = y - (y * y * y - x) / (3.0 * y * y);
    sign * y
}

// Approximate pow(base, exp) = exp2(exp * log2(base))
fn powf(base: f32, exp: f32) -> f32 {
    if base <= 0.0 {
        return 0.0;
    }
    exp2f(exp * log2f(base))
}

// Approximate log2 using bit manipulation + polynomial
fn log2f(x: f32) -> f32 {
    if x <= 0.0 {
        return -1e30; // -infinity substitute
    }
    let bits = x.to_bits();
    let exponent = ((bits >> 23) & 0xFF) as i32 - 127;
    // Normalize mantissa to [1, 2)
    let m_bits = (bits & 0x007FFFFF) | 0x3F800000;
    let m = f32::from_bits(m_bits);
    // Minimax polynomial for log2(m) where m in [1, 2)
    let a = m - 1.0;
    let log2_m = a * (1.4426950408 - a * (0.7213475 - a * 0.4808983));
    exponent as f32 + log2_m
}

// Approximate exp2 using bit manipulation
fn exp2f(x: f32) -> f32 {
    if x < -126.0 {
        return 0.0;
    }
    if x > 127.0 {
        return f32::MAX;
    }
    // Split x into integer and fractional parts
    let xi = x as i32 - if x < 0.0 { 1 } else { 0 };
    let xf = x - xi as f32;
    // Polynomial approximation of 2^xf for xf in [0, 1)
    let two_xf = 1.0 + xf * (0.6931472 + xf * (0.2402265 + xf * (0.0555041 + xf * 0.009618)));
    // Combine with integer exponent
    let bits = ((xi + 127) as u32) << 23;
    f32::from_bits(bits) * two_xf
}

// Approximate sin/cos via polynomial
fn sinf(x: f32) -> f32 {
    // Reduce to [-pi, pi]
    let mut x = x;
    const TWO_PI: f32 = 2.0 * core::f32::consts::PI;
    // Round to nearest integer
    let n = (x / TWO_PI) as i32;
    x = x - (n as f32) * TWO_PI;
    // Bring into [-pi, pi]
    if x > core::f32::consts::PI {
        x -= TWO_PI;
    } else if x < -core::f32::consts::PI {
        x += TWO_PI;
    }
    // Bhaskara-style or Taylor
    let x2 = x * x;
    let x3 = x2 * x;
    let x5 = x3 * x2;
    let x7 = x5 * x2;
    x - x3 / 6.0 + x5 / 120.0 - x7 / 5040.0
}

fn cosf(x: f32) -> f32 {
    sinf(x + core::f32::consts::FRAC_PI_2)
}

fn atan2f(y: f32, x: f32) -> f32 {
    if x == 0.0 {
        if y > 0.0 {
            return core::f32::consts::FRAC_PI_2;
        } else if y < 0.0 {
            return -core::f32::consts::FRAC_PI_2;
        } else {
            return 0.0;
        }
    }
    let a = atanf(y / x);
    if x > 0.0 {
        a
    } else if y >= 0.0 {
        a + core::f32::consts::PI
    } else {
        a - core::f32::consts::PI
    }
}

fn atanf(x: f32) -> f32 {
    // Range reduction: atan(x) for |x| > 1 => pi/2 - atan(1/x)
    if absf(x) > 1.0 {
        let sign = if x > 0.0 { 1.0 } else { -1.0 };
        return sign * core::f32::consts::FRAC_PI_2 - atanf(1.0 / x);
    }
    // Polynomial approximation for |x| <= 1
    let x2 = x * x;
    x * (1.0 - x2 * (0.3333333 - x2 * (0.2 - x2 * 0.142857)))
}

// --- Shader entry points ---

// Linear memory layout for shade_batch:
// colors_ptr points to count entries, each 6 x i32 (24 bytes):
//   [r, g, b, x, y, is_fg]
// shade_batch reads these, transforms in-place, writes back r,g,b.

#[no_mangle]
pub extern "C" fn shade_batch(
    colors_ptr: i32,
    count: i32,
    w: i32,
    h: i32,
    cursor_x: i32,
    cursor_y: i32,
    time_ms: i32,
) {
    let ptr = colors_ptr as usize;
    let count = count as usize;
    let w_f = w as f32;
    let h_f = h as f32;
    let cx = cursor_x as f32;
    let cy = cursor_y as f32;
    let t = time_ms as f32;

    for i in 0..count {
        let base = ptr + i * 24; // 6 * 4 bytes per entry
        unsafe {
            let r = read_i32(base) as f32;
            let g = read_i32(base + 4) as f32;
            let b = read_i32(base + 8) as f32;
            let x = read_i32(base + 12) as f32;
            let y = read_i32(base + 16) as f32;
            let is_fg = read_i32(base + 20) != 0;

            let (nr, ng, nb) = shade(r, g, b, x, y, w_f, h_f, cx, cy, t, is_fg);

            write_i32(base, nr as i32);
            write_i32(base + 4, ng as i32);
            write_i32(base + 8, nb as i32);
        }
    }
}

// Returns count of rows needing re-render.
// Writes row indices to out_ptr. Returns 0 = no animation needed.
#[no_mangle]
pub extern "C" fn invalidate(
    out_ptr: i32,
    max_rows: i32,
    _w: i32,
    h: i32,
    _t_ms: i32,
    cx: i32,
    cy: i32,
    prev_cx: i32,
    prev_cy: i32,
) -> i32 {
    // Always animate: the glare breathes with time.
    // Return all rows (simple strategy — the shader changes globally).
    let out = out_ptr as usize;
    let max = max_rows as usize;
    let rows = h as usize;
    let count = if rows < max { rows } else { max };

    // If cursor moved, invalidate all rows (glare shifts).
    // Otherwise still invalidate all rows because of breathing.
    let _ = (cx, cy, prev_cx, prev_cy); // used for future selective invalidation
    for i in 0..count {
        unsafe {
            write_i32(out + i * 4, i as i32);
        }
    }
    count as i32
}

unsafe fn read_i32(addr: usize) -> i32 {
    core::ptr::read(addr as *const i32)
}

unsafe fn write_i32(addr: usize, val: i32) {
    core::ptr::write(addr as *mut i32, val);
}

fn shade(
    r: f32, g: f32, b: f32,
    x: f32, y: f32, w: f32, h: f32,
    cx: f32, cy: f32, t: f32,
    is_fg: bool,
) -> (f32, f32, f32) {
    let (l, c, hue) = rgb_to_oklch(r, g, b);

    // Pane-local coordinates
    let lx = x % maxf(w, 1.0);
    let ly = y % maxf(h, 1.0);

    // --- Breathing: slow pulsation driven by time ---
    // ~4 second cycle (0.25 Hz)
    let breath = sinf(t * 0.0015) * 0.5 + 0.5; // 0..1

    // --- Vignette: edge darkening with subtle breathing ---
    let nx = lx / maxf(w, 1.0);
    let ny = ly / maxf(h, 1.0);
    let vx = (nx - 0.5) * 2.0;
    let vy = (ny - 0.5) * 2.0;
    let vdist = sqrtf(vx * vx + vy * vy);
    let vig_strength = 0.38 + breath * 0.04; // breathes between 0.38-0.42
    let vignette = clamp(1.2 - vdist * vig_strength, 0.55, 1.0);

    // --- Glare: elliptical highlight near top-right, warm tint ---
    let gx = (w * 0.8 - lx) / maxf(w, 1.0);
    let gy = (ly - h * 0.15) * 2.5 / maxf(h, 1.0);
    let gdist = sqrtf(gx * gx * 0.6 + gy * gy);
    let glare_base = clamp(1.0 - gdist / 0.8, 0.0, 1.0);
    let glare_intensity = 0.50 + breath * 0.10; // breathes between 0.50-0.60
    let glare = glare_base * glare_base * glare_base * glare_intensity;
    // Warm shift: push hue toward amber (70 deg) in glare zone
    let hue = mix(hue, 70.0, glare * 0.5);

    // --- Cursor glow: subtle brightening near cursor position ---
    let cdx = (lx - cx) / maxf(w, 1.0) * 6.0;
    let cdy = (ly - cy) / maxf(h, 1.0) * 6.0;
    let cdist = sqrtf(cdx * cdx + cdy * cdy);
    let cursor_glow = clamp(1.0 - cdist, 0.0, 1.0) * 0.08;

    // --- Scanlines: faint darkening on alternating rows ---
    let scanline = if (y as i32) % 2 == 0 { 0.97 } else { 1.0 };

    // --- Noise: pseudo-random per-cell grain ---
    let n = absf(((x * 12.9898 + y * 78.233) * 43758.5453) % 1.0);
    let noise = (n - 0.5) * 0.035;

    // --- Combine ---
    let nl = l * vignette * scanline + noise + cursor_glow;

    if is_fg {
        let nc = c * 0.18;
        let nl = clamp(mix(nl, 1.0, glare), 0.0, 1.0);
        let nc = nc * (1.0 - glare);
        let (or, og, ob) = oklch_to_rgb(nl, nc, hue);
        (clamp(or, 0.0, 255.0), clamp(og, 0.0, 255.0), clamp(ob, 0.0, 255.0))
    } else {
        let nc = c * 0.25;
        let nl = clamp(mix(nl, 0.85, glare), 0.0, 1.0);
        let nc = nc * (1.0 - glare * 0.8);
        let (or, og, ob) = oklch_to_rgb(nl, nc, hue);
        (clamp(or, 0.0, 255.0), clamp(og, 0.0, 255.0), clamp(ob, 0.0, 255.0))
    }
}
