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

// --- Uniforms ---
//
// The host writes a uniforms block at WASM memory offset 0 before each call.
// Layout: 32 x i32 = 128 bytes.
//
// Offset  Field
// 0       pane_width
// 4       pane_height
// 8       cursor_x          (terminal text cursor)
// 12      cursor_y
// 16      mouse_x           (-1 if not hovering)
// 20      mouse_y
// 24      time_ms
// 28      pane_id
// 32      is_focused         (0 or 1)
// 36      scroll_offset
// 40      pane_x             (pane position on screen)
// 44      pane_y
// 48      screen_width
// 52      screen_height
// 56      pane_count
// 60      has_selection       (0 or 1)
// 64      sel_start_x
// 68      sel_start_y
// 72      sel_end_x
// 76      sel_end_y
// 80      prev_cursor_x
// 84      prev_cursor_y
// 88      prev_mouse_x
// 92      prev_mouse_y
// 96-127  reserved

struct Uniforms {
    w: f32,
    h: f32,
    cursor_x: f32,
    cursor_y: f32,
    mouse_x: f32,
    mouse_y: f32,
    time: f32,
    pane_id: i32,
    is_focused: bool,
    scroll_offset: f32,
    pane_x: f32,
    pane_y: f32,
    screen_w: f32,
    screen_h: f32,
    pane_count: i32,
    has_selection: bool,
    sel_start_x: f32,
    sel_start_y: f32,
    sel_end_x: f32,
    sel_end_y: f32,
    prev_cursor_x: f32,
    prev_cursor_y: f32,
    prev_mouse_x: f32,
    prev_mouse_y: f32,
}

// Uniforms are written by the host at this offset to avoid clobbering
// the WASM module's stack/static data at low addresses.
const UNIFORMS_OFFSET: usize = 65408;

fn read_uniforms() -> Uniforms {
    unsafe {
        let o = UNIFORMS_OFFSET;
        let time_ms = read_i32(o + 24);
        Uniforms {
            w: maxf(read_i32(o) as f32, 1.0),
            h: maxf(read_i32(o + 4) as f32, 1.0),
            cursor_x: read_i32(o + 8) as f32,
            cursor_y: read_i32(o + 12) as f32,
            mouse_x: read_i32(o + 16) as f32,
            mouse_y: read_i32(o + 20) as f32,
            // Reduce time to keep f32 precision in sinf().
            // 10_000_000 ms ≈ 2.8 hours; t * 0.0015 stays under 15 000.
            time: (time_ms % 10_000_000) as f32,
            pane_id: read_i32(o + 28),
            is_focused: read_i32(o + 32) != 0,
            scroll_offset: read_i32(o + 36) as f32,
            pane_x: read_i32(o + 40) as f32,
            pane_y: read_i32(o + 44) as f32,
            screen_w: maxf(read_i32(o + 48) as f32, 1.0),
            screen_h: maxf(read_i32(o + 52) as f32, 1.0),
            pane_count: read_i32(o + 56),
            has_selection: read_i32(o + 60) != 0,
            sel_start_x: read_i32(o + 64) as f32,
            sel_start_y: read_i32(o + 68) as f32,
            sel_end_x: read_i32(o + 72) as f32,
            sel_end_y: read_i32(o + 76) as f32,
            prev_cursor_x: read_i32(o + 80) as f32,
            prev_cursor_y: read_i32(o + 84) as f32,
            prev_mouse_x: read_i32(o + 88) as f32,
            prev_mouse_y: read_i32(o + 92) as f32,
        }
    }
}

// --- Shader entry points ---

// Host writes uniforms at offset 0, then color entries at colors_ptr.
// Each color entry: 6 x i32 (24 bytes) = [r, g, b, x, y, is_fg].
// shade_batch transforms r,g,b in-place.
#[no_mangle]
pub extern "C" fn shade_batch(colors_ptr: i32, count: i32) {
    let u = read_uniforms();
    let ptr = colors_ptr as usize;
    let count = count as usize;

    for i in 0..count {
        let base = ptr + i * 24;
        unsafe {
            let r = read_i32(base) as f32;
            let g = read_i32(base + 4) as f32;
            let b = read_i32(base + 8) as f32;
            let x = read_i32(base + 12) as f32;
            let y = read_i32(base + 16) as f32;
            let is_fg = read_i32(base + 20) != 0;

            let (nr, ng, nb) = shade(r, g, b, x, y, is_fg, &u);

            write_i32(base, nr as i32);
            write_i32(base + 4, ng as i32);
            write_i32(base + 8, nb as i32);
        }
    }
}

// Invalidation state — safe because WASM is single-threaded.
static mut LAST_BREATH: f32 = 0.0;

// Host writes uniforms at offset 0 (including prev_cursor/prev_mouse).
// Returns count of rows needing re-render.
// Writes row indices to out_ptr. Returns 0 = no animation needed.
#[no_mangle]
pub extern "C" fn invalidate(out_ptr: i32, max_rows: i32) -> i32 {
    let u = read_uniforms();
    let out = out_ptr as usize;
    let max = max_rows as usize;
    let h = u.h as usize;
    let rows = if h < max { h } else { max };

    let breath = sinf(u.time * 0.0015) * 0.5 + 0.5;
    let prev_breath = unsafe { LAST_BREATH };

    let cursor_moved = u.cursor_x as i32 != u.prev_cursor_x as i32
        || u.cursor_y as i32 != u.prev_cursor_y as i32;
    let mouse_moved = u.mouse_x as i32 != u.prev_mouse_x as i32
        || u.mouse_y as i32 != u.prev_mouse_y as i32;

    let breath_delta = absf(breath - prev_breath);
    let breath_dirty = breath_delta > 0.03;

    if breath_dirty {
        unsafe { LAST_BREATH = breath; }
    }

    if !cursor_moved && !mouse_moved && !breath_dirty {
        return 0;
    }

    // Full refresh for breathing — every row changes slightly
    if breath_dirty && !cursor_moved && !mouse_moved {
        for i in 0..rows {
            unsafe { write_i32(out + i * 4, i as i32); }
        }
        return rows as i32;
    }

    // For large panes, fall back to full refresh
    if rows > 512 {
        for i in 0..rows {
            unsafe { write_i32(out + i * 4, i as i32); }
        }
        return rows as i32;
    }

    let mut dirty = [false; 512];
    let glow_radius = (h / 6 + 1) as usize;

    // Mark rows near a y position
    let mark_near = |dirty: &mut [bool; 512], cy: usize| {
        let start = if cy >= glow_radius { cy - glow_radius } else { 0 };
        let end = if cy + glow_radius < rows { cy + glow_radius } else { rows.saturating_sub(1) };
        let mut r = start;
        while r <= end {
            dirty[r] = true;
            r += 1;
        }
    };

    if cursor_moved {
        mark_near(&mut dirty, u.prev_cursor_y as usize);
        mark_near(&mut dirty, u.cursor_y as usize);
    }

    if mouse_moved {
        if u.prev_mouse_y >= 0.0 {
            mark_near(&mut dirty, u.prev_mouse_y as usize);
        }
        if u.mouse_y >= 0.0 {
            mark_near(&mut dirty, u.mouse_y as usize);
        }
    }

    if breath_dirty {
        let mut r = 0;
        while r < rows {
            dirty[r] = true;
            r += 1;
        }
    }

    let mut count = 0usize;
    let mut r = 0;
    while r < rows {
        if dirty[r] {
            unsafe { write_i32(out + count * 4, r as i32); }
            count += 1;
        }
        r += 1;
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
    x: f32, y: f32,
    is_fg: bool,
    u: &Uniforms,
) -> (f32, f32, f32) {
    let (l, c, hue) = rgb_to_oklch(r, g, b);

    // Pane-local coordinates
    let lx = x % u.w;
    let ly = y % u.h;

    // --- Breathing: slow pulsation driven by time ---
    let breath = sinf(u.time * 0.0015) * 0.5 + 0.5;

    // --- Vignette: edge darkening with subtle breathing ---
    let nx = lx / u.w;
    let ny = ly / u.h;
    let vx = (nx - 0.5) * 2.0;
    let vy = (ny - 0.5) * 2.0;
    let vdist = sqrtf(vx * vx + vy * vy);
    let vig_strength = 0.38 + breath * 0.04;
    let vignette = clamp(1.2 - vdist * vig_strength, 0.55, 1.0);

    // --- Glare: elliptical highlight near top-right, warm tint ---
    let gx = (u.w * 0.8 - lx) / u.w;
    let gy = (ly - u.h * 0.15) * 2.5 / u.h;
    let gdist = sqrtf(gx * gx * 0.6 + gy * gy);
    let glare_base = clamp(1.0 - gdist / 0.8, 0.0, 1.0);
    let glare_intensity = 0.50 + breath * 0.10;
    let glare = glare_base * glare_base * glare_base * glare_intensity;
    let hue = mix(hue, 70.0, glare * 0.5);

    // --- Mouse glow: brightening near mouse when hovering ---
    let mouse_glow = if u.mouse_x >= 0.0 {
        let mdx = (lx - u.mouse_x) / u.w * 6.0;
        let mdy = (ly - u.mouse_y) / u.h * 6.0;
        let mdist = sqrtf(mdx * mdx + mdy * mdy);
        clamp(1.0 - mdist, 0.0, 1.0) * 0.08
    } else {
        0.0
    };

    // --- Cursor glow: subtle brightening near terminal cursor ---
    let cdx = (lx - u.cursor_x) / u.w * 6.0;
    let cdy = (ly - u.cursor_y) / u.h * 6.0;
    let cdist = sqrtf(cdx * cdx + cdy * cdy);
    let cursor_glow = clamp(1.0 - cdist, 0.0, 1.0) * 0.08;

    // --- Scanlines: faint darkening on alternating rows ---
    let scanline = if (y as i32) % 2 == 0 { 0.97 } else { 1.0 };

    // --- Noise: pseudo-random per-cell grain ---
    let n = absf(((x * 12.9898 + y * 78.233) * 43758.5453) % 1.0);
    let noise = (n - 0.5) * 0.035;

    // --- Combine: use max of mouse and cursor glow ---
    let glow = maxf(mouse_glow, cursor_glow);
    let nl = l * vignette * scanline + noise + glow;

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
