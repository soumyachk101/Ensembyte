//! Loaders: the ensembyte pulse loader, the gradient matrix spinner, and the boot
//! splash content. All motion routes through `crate::motion` pure helpers, so
//! the math is unit-tested and these elements are testable-by-compile.
//!
//! Rendering pattern: cells share a self-parking pulse clock; per-cell offsets
//! come from [`motion::staggered_phase`], so all cells stay phase-locked.
//! Cells animate inside fixed-size slots — opacity and inner size
//! are paint-local and never move surrounding layout. Reduced motion snaps every
//! cell to its rest state automatically (gpui `reduce_motion`).

use gpui::{
    AnyElement, App, AppContext, Context, Entity, EntityId, IntoElement, ParentElement,
    PathBuilder, Render, RenderOnce, SharedString, Styled, Window, canvas, div, point, px,
};

use crate::motion::{self, GRADIENT_SPIN, PULSE_STAGGER, SPLASH_OUT, ENSEMBYTE_PULSE};
use crate::theme::{GlyphPalette, Theme};

// Shared with the terminal viewport (`ensembyte_proto::motion`) so both animate the
// same loaders from the same numbers.
pub use ensembyte_proto::motion::{
    MARK_CELLS, MARK_SPREAD, MATRIX_SIDE, ENSEMBYTE_CELLS, mark_cell_stagger,
};

/// The animated ensembyte mark (ensembyte-loader.tsx `OrbitLoader`): the full logo
/// pixel grid with a light wave sweeping tail→head. Each cell rests dim
/// (opacity 0.08, scale 0.9) and flares to full as the crest passes; per-cell
/// stagger follows the flight axis. `height_px` sets the mark's height (width
/// follows the 820:940 canvas).
pub fn ensembyte_mark_loader(
    _id: &'static str,
    theme: &Theme,
    height_px: f32,
    view: EntityId,
    cx: &mut App,
) -> impl IntoElement {
    let color = theme.text;
    let scale = height_px / 940.0;
    let cell = 100.0 * scale;
    let delta = motion::pulse_delta(&ENSEMBYTE_PULSE, view, cx);
    div()
        .relative()
        .w(px(820.0 * scale))
        .h(px(height_px))
        .children(MARK_CELLS.iter().map(move |&(x, y)| {
            let stagger = mark_cell_stagger(x, y);
            // Fixed slot; the animated cell breathes inside it (paint-local).
            div()
                .absolute()
                .left(px(x * scale))
                .top(px(y * scale))
                .size(px(cell))
                .flex()
                .items_center()
                .justify_center()
                .child({
                    // Negative CSS delay ⇒ the cell starts mid-cycle:
                    // the stagger ADDS phase (ensembyte-loader.tsx delayFor).
                    let phase = (delta + stagger).rem_euclid(1.0);
                    div()
                        .rounded(px(16.0 * scale))
                        .bg(color)
                        .opacity(motion::pulse_opacity(phase))
                        .size(px(cell * motion::pulse_scale(phase)))
                })
        }))
}

/// The ensembyte wave loader: a row of cells pulsing opacity 0.08→1 / scale 0.9→1
/// over 2.4s with a 0.15s stagger per cell.
///
/// `id` scopes the per-cell animation state — give each loader instance a
/// distinct id.
pub fn ensembyte_loader(
    _id: &'static str,
    theme: &Theme,
    cell_px: f32,
    view: EntityId,
    cx: &mut App,
) -> impl IntoElement {
    let color = theme.text;
    let slot = cell_px;
    let delta = motion::pulse_delta(&ENSEMBYTE_PULSE, view, cx);
    div()
        .flex()
        .flex_row()
        .items_center()
        .gap(px(slot / 2.0))
        .children((0..ENSEMBYTE_CELLS).map(move |i| {
            // Fixed slot; the animated cell breathes inside it.
            div()
                .size(px(slot))
                .flex()
                .items_center()
                .justify_center()
                .child({
                    let phase = motion::staggered_phase(delta, i, PULSE_STAGGER);
                    div()
                        .rounded(px(slot / 4.0))
                        .bg(color)
                        .opacity(motion::pulse_opacity(phase))
                        .size(px(slot * motion::pulse_scale(phase)))
                })
        }))
}

pub use ensembyte_proto::motion::{GSPIN_DIM, GSPIN_ROW_TINTS};

/// The gradient matrix spinner (WorkingIndicator), ported from ensembyte's
/// gradient-spin.tsx: a 3×3 grid of round cells tinted per row from the
/// sunrise gradient. Each cell pulses opacity once per 750ms period; the
/// per-cell phase follows the "arrow-up" pattern (the pulse enters at the
/// bottom edge and converges toward the top-center cell), so the wave reads
/// as travelling upward.
pub fn gradient_spinner(
    _id: &'static str,
    _theme: &Theme,
    cell_px: f32,
    view: EntityId,
    cx: &mut App,
) -> impl IntoElement {
    let center = (MATRIX_SIDE as f32 - 1.0) / 2.0;
    let max = MATRIX_SIDE as f32 - 1.0 + center;
    let delta = motion::pulse_delta_slow(&GRADIENT_SPIN, view, cx);
    div()
        .flex()
        .flex_col()
        .gap(px(cell_px / 2.0))
        .children((0..MATRIX_SIDE).map(move |row| {
            let tint: gpui::Hsla = gpui::rgb(GSPIN_ROW_TINTS[row]).into();
            div()
                .flex()
                .flex_row()
                .gap(px(cell_px / 2.0))
                .children((0..MATRIX_SIDE).map(move |col| {
                    // Distance of this cell from the wave origin, normalized
                    // into a phase offset (gradient-spin's `--gspin-phase`).
                    let d = MATRIX_SIDE as f32 - 1.0 - row as f32 + (col as f32 - center).abs();
                    let phase = if max == 0.0 { 0.0 } else { d / (max + 1.0) };
                    div()
                        .size(px(cell_px))
                        .rounded(px(cell_px / 2.0))
                        .bg(tint)
                        .opacity(motion::gspin_opacity(delta + phase, GSPIN_DIM))
                }))
        }))
}

/// A 2×3 activity glyph sized for compact status slots. Its color is an
/// explicit accent-preset role supplied by the caller, while brightness snakes
/// around the grid's perimeter as a tiny radial chase.
pub fn mini_glyph_spinner(
    key: impl Into<SharedString>,
    cell_px: f32,
    palette: GlyphPalette,
    view: EntityId,
    cx: &mut App,
) -> impl IntoElement {
    mini_spinner_tinted(key, cell_px, palette.rows(), view, cx)
}

/// Grayscale variant for surfaces where an accent would pull focus (the
/// sidebar connection line): same grid, snake, and timing, color left to the
/// caller.
pub fn mini_mono_spinner(
    key: impl Into<SharedString>,
    cell_px: f32,
    tint: gpui::Hsla,
    view: EntityId,
    cx: &mut App,
) -> impl IntoElement {
    mini_spinner_tinted(key, cell_px, [tint; 3], view, cx)
}

fn mini_spinner_tinted(
    key: impl Into<SharedString>,
    cell_px: f32,
    row_tints: [gpui::Hsla; 3],
    _view: EntityId,
    _cx: &mut App,
) -> impl IntoElement {
    MiniSpinner {
        key: key.into(),
        cell_px,
        row_tints,
    }
}

#[derive(IntoElement)]
struct MiniSpinner {
    key: SharedString,
    cell_px: f32,
    row_tints: [gpui::Hsla; 3],
}

impl RenderOnce for MiniSpinner {
    fn render(self, window: &mut Window, cx: &mut App) -> impl IntoElement {
        // Keep pulse invalidation separate from container state changes so
        // cached sibling rows can be reused while these six cells animate.
        let view = window.with_global_id(self.key.into(), |id, window| {
            window.with_element_state(id, |previous: Option<Entity<MiniSpinnerView>>, _| {
                let view = previous.unwrap_or_else(|| {
                    cx.new(|_| MiniSpinnerView {
                        cell_px: self.cell_px,
                        row_tints: self.row_tints,
                    })
                });
                view.update(cx, |view, cx| {
                    if view.cell_px != self.cell_px || view.row_tints != self.row_tints {
                        view.cell_px = self.cell_px;
                        view.row_tints = self.row_tints;
                        cx.notify();
                    }
                });
                (view.clone(), view)
            })
        });
        view.cached(
            gpui::StyleRefinement::default()
                .w(px(self.cell_px * 2.5))
                .h(px(self.cell_px * 4.0)),
        )
    }
}

struct MiniSpinnerView {
    cell_px: f32,
    row_tints: [gpui::Hsla; 3],
}

impl Render for MiniSpinnerView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        mini_spinner_cells(self.cell_px, self.row_tints, cx.entity_id(), cx)
    }
}

fn mini_spinner_cells(
    cell_px: f32,
    row_tints: [gpui::Hsla; 3],
    view: EntityId,
    cx: &mut App,
) -> impl IntoElement {
    const COLS: usize = 2;
    const ROWS: usize = 3;
    /// Clockwise ring position of each `(row, col)` cell, top-left first:
    /// (0,0) → (0,1) → (1,1) → (2,1) → (2,0) → (1,0).
    const RING: [[usize; COLS]; ROWS] = [[0, 1], [5, 2], [4, 3]];
    const RING_LEN: f32 = (COLS * ROWS) as f32;
    let delta = motion::pulse_delta(&GRADIENT_SPIN, view, cx);
    div()
        .flex()
        .flex_col()
        .gap(px(cell_px / 2.0))
        .children((0..ROWS).map(move |row| {
            let tint = row_tints[row];
            div()
                .flex()
                .flex_row()
                .gap(px(cell_px / 2.0))
                .children((0..COLS).map(move |col| {
                    let phase = RING[row][col] as f32 / RING_LEN;
                    div()
                        .size(px(cell_px))
                        .rounded(px(cell_px / 2.0))
                        .bg(tint)
                        .opacity(motion::gspin_opacity(delta + phase, GSPIN_DIM))
                }))
        }))
}

/// Stroke width of [`upload_progress_ring`].
const RING_STROKE: f32 = 2.5;
/// Polyline segments for a full circle — plenty for a ≤40px ring.
const RING_SEGMENTS: f32 = 64.0;

/// Radial upload-progress ring with the percent centered — overlaid on a
/// sending echo's attachment thumbnail while its bytes cross the relay
/// (2026-08-18 "Sending… forever" report; the thumbnail is where the wait
/// visibly belongs). A faint full track plus a bright arc growing clockwise
/// from 12 o'clock; gpui paths have no arc primitive, so both are stroked
/// polylines. Fixed white-on-wash palette: the caller dims the image behind
/// it, which reads in both themes.
pub fn upload_progress_ring(percent: u8, diameter: f32) -> AnyElement {
    let frac = f32::from(percent.min(100)) / 100.0;
    let ring = canvas(
        |_, _, _| (),
        move |bounds, _, window, _| {
            let center = bounds.center();
            let radius = diameter / 2.0 - RING_STROKE;
            let mut paint_arc = |sweep: f32, color: gpui::Hsla| {
                if sweep <= 0.0 {
                    return;
                }
                let steps = ((RING_SEGMENTS * sweep).ceil() as usize).max(2);
                let at = |i: usize| {
                    // Clockwise from 12 o'clock.
                    let theta = -std::f32::consts::FRAC_PI_2
                        + std::f32::consts::TAU * sweep * (i as f32 / steps as f32);
                    point(
                        center.x + px(radius * theta.cos()),
                        center.y + px(radius * theta.sin()),
                    )
                };
                let mut builder = PathBuilder::stroke(px(RING_STROKE));
                builder.move_to(at(0));
                for i in 1..=steps {
                    builder.line_to(at(i));
                }
                if let Ok(path) = builder.build() {
                    window.paint_path(path, color);
                }
            };
            paint_arc(1.0, gpui::hsla(0.0, 0.0, 1.0, 0.22));
            paint_arc(frac, gpui::hsla(0.0, 0.0, 1.0, 0.95));
        },
    )
    .absolute()
    .inset_0();
    div()
        .relative()
        .size(px(diameter))
        .flex()
        .items_center()
        .justify_center()
        .child(ring)
        .child(
            div()
                .text_size(px(9.0))
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .text_color(gpui::hsla(0.0, 0.0, 1.0, 0.95))
                .child(SharedString::from(format!("{percent}%"))),
        )
        .into_any_element()
}

/// Full-window boot splash: the app's dot loader (the same [`gradient_spinner`]
/// the session list and the reconnecting line pulse — user request, replacing
/// the hero ascii) over the app background with a quiet status line. While
/// `fading` it plays `splash-out` (150ms hold, then 0.5s fade + 6px lift); the
/// shell removes it once [`SPLASH_OUT`] has run its course.
pub fn splash_overlay(theme: &Theme, fading: bool, view: EntityId, cx: &mut App) -> AnyElement {
    let content = div()
        .absolute()
        .inset_0()
        // Frosted glass, not the opaque page tone (user request): the boot
        // overlay reads like the rest of the chrome — the frost tint over
        // the blurred window background (opaque platforms get the surface
        // tone, since `glass()` collapses to it there).
        .bg(theme.glass())
        .flex()
        .flex_col()
        .items_center()
        .justify_center()
        .gap(px(12.0))
        // Cell 2.5 — the size every other surface runs this spinner at (the
        // "Sending…" strip, the transcript working trailer).
        .child(gradient_spinner(
            "boot-splash-spinner",
            theme,
            2.5,
            view,
            cx,
        ))
        .child(
            div()
                .text_size(crate::typography::ui_rems(12.0))
                .text_color(theme.text_muted.opacity(0.7))
                .child(SharedString::from("Setting up Ensembyte environment")),
        );
    if fading {
        motion::splash_out("boot-splash-out", content).into_any_element()
    } else {
        content.into_any_element()
    }
}

// Compile-time proof the specs referenced here stay wired to the catalog.
const _: () = {
    assert!(SPLASH_OUT.delay_ms == 150);
    assert!(ENSEMBYTE_PULSE.duration_ms == 2400);
    assert!(GRADIENT_SPIN.duration_ms == 750);
};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mark_stagger_follows_flight_axis() {
        // Tail tip (720, 0) leads: near-maximal stagger (starts deepest into
        // the cycle); head (0, 840) trails with stagger 0.
        let tail = mark_cell_stagger(720.0, 0.0);
        let head = mark_cell_stagger(0.0, 840.0);
        assert!(tail > head, "tail {tail} should lead head {head}");
        assert!((head - 0.0).abs() < 1e-6, "head stagger ≈ 0, got {head}");
        assert!(tail <= MARK_SPREAD + 1e-6, "stagger capped at SPREAD");
        // Every logo cell stays inside [0, SPREAD].
        for &(x, y) in &MARK_CELLS {
            let s = mark_cell_stagger(x, y);
            assert!(
                (0.0..=MARK_SPREAD + 1e-6).contains(&s),
                "cell ({x},{y}) stagger {s}"
            );
        }
    }
}

/// An animated, glowing AI reasoning shader orb with dynamic multi-color rotation
/// (cyan, violet, fuchsia, blue) and breathing pulse effect while thinking,
/// settling to a calm gradient orb when done.
pub fn thinking_shader_orb(
    size_px: f32,
    is_thinking: bool,
    view: EntityId,
    cx: &mut App,
) -> impl IntoElement {
    let delta = if is_thinking {
        motion::pulse_delta(&motion::THINKING_ORB_SPIN, view, cx)
    } else {
        0.0
    };

    let diameter = size_px.max(8.0);
    let radius = diameter / 2.0;

    div()
        .relative()
        .size(px(diameter))
        .flex()
        .items_center()
        .justify_center()
        .child(
            canvas(
                move |_, _, _| (),
                move |bounds, _, window, _| {
                    let center = bounds.center();
                    if is_thinking {
                        // Breathing pulse scale factor: 0.90..1.08
                        let breathe = 0.92 + 0.14 * (delta * std::f32::consts::TAU * 2.0).sin().abs();
                        let active_radius = radius * breathe;
                        let rotation_offset = delta * std::f32::consts::TAU;

                        // 4 vibrant chromatic color stops:
                        // 0: Cyan   (0.22, 0.74, 0.97) -> hsl(198, 93%, 60%)
                        // 1: Violet (0.55, 0.36, 0.96) -> hsl(259, 89%, 66%)
                        // 2: Fuchsia(0.91, 0.30, 0.65) -> hsl(326, 85%, 61%)
                        // 3: Blue   (0.23, 0.51, 0.96) -> hsl(217, 92%, 60%)
                        const STOPS: [(f32, f32, f32); 4] = [
                            (198.0 / 360.0, 0.93, 0.60),
                            (259.0 / 360.0, 0.89, 0.66),
                            (326.0 / 360.0, 0.85, 0.61),
                            (217.0 / 360.0, 0.92, 0.60),
                        ];

                        // Draw outer soft chromatic halo (16 angular wedges)
                        let glow_radius = active_radius * 1.35;
                        const WEDGES: usize = 16;
                        for i in 0..WEDGES {
                            let f0 = i as f32 / WEDGES as f32;
                            let f1 = (i + 1) as f32 / WEDGES as f32;
                            let theta0 = rotation_offset + f0 * std::f32::consts::TAU;
                            let theta1 = rotation_offset + f1 * std::f32::consts::TAU;

                            let stop_idx = (f0 * 4.0) as usize % 4;
                            let next_stop = (stop_idx + 1) % 4;
                            let local_f = (f0 * 4.0).fract();
                            let h = STOPS[stop_idx].0 + (STOPS[next_stop].0 - STOPS[stop_idx].0) * local_f;
                            let s = STOPS[stop_idx].1 + (STOPS[next_stop].1 - STOPS[stop_idx].1) * local_f;
                            let l = STOPS[stop_idx].2 + (STOPS[next_stop].2 - STOPS[stop_idx].2) * local_f;

                            // Outer glow wedge
                            let mut glow_path = PathBuilder::fill();
                            glow_path.move_to(center);
                            glow_path.line_to(point(
                                center.x + px(glow_radius * theta0.cos()),
                                center.y + px(glow_radius * theta0.sin()),
                            ));
                            glow_path.line_to(point(
                                center.x + px(glow_radius * theta1.cos()),
                                center.y + px(glow_radius * theta1.sin()),
                            ));
                            glow_path.close();
                            if let Ok(p) = glow_path.build() {
                                window.paint_path(p, gpui::hsla(h, s, l, 0.28));
                            }

                            // Inner sharp wedge
                            let mut inner_path = PathBuilder::fill();
                            inner_path.move_to(center);
                            inner_path.line_to(point(
                                center.x + px(active_radius * theta0.cos()),
                                center.y + px(active_radius * theta0.sin()),
                            ));
                            inner_path.line_to(point(
                                center.x + px(active_radius * theta1.cos()),
                                center.y + px(active_radius * theta1.sin()),
                            ));
                            inner_path.close();
                            if let Ok(p) = inner_path.build() {
                                window.paint_path(p, gpui::hsla(h, s, l, 0.92));
                            }
                        }

                        // Center glowing core highlight
                        let mut core = PathBuilder::fill();
                        let core_radius = active_radius * 0.45;
                        for i in 0..16 {
                            let a = std::f32::consts::TAU * i as f32 / 16.0;
                            let pt = point(center.x + px(core_radius * a.cos()), center.y + px(core_radius * a.sin()));
                            if i == 0 { core.move_to(pt); } else { core.line_to(pt); }
                        }
                        core.close();
                        if let Ok(p) = core.build() {
                            window.paint_path(p, gpui::hsla(0.0, 0.0, 1.0, 0.35));
                        }

                        // Fine perimeter rim
                        let mut rim = PathBuilder::stroke(px(0.6));
                        for i in 0..=24 {
                            let a = std::f32::consts::TAU * i as f32 / 24.0;
                            let pt = point(center.x + px(active_radius * a.cos()), center.y + px(active_radius * a.sin()));
                            if i == 0 { rim.move_to(pt); } else { rim.line_to(pt); }
                        }
                        if let Ok(p) = rim.build() {
                            window.paint_path(p, gpui::hsla(0.0, 0.0, 1.0, 0.40));
                        }
                    } else {
                        // Settled: calm violet & cyan gradient disc
                        const WEDGES: usize = 16;
                        for i in 0..WEDGES {
                            let f0 = i as f32 / WEDGES as f32;
                            let f1 = (i + 1) as f32 / WEDGES as f32;
                            let theta0 = f0 * std::f32::consts::TAU;
                            let theta1 = f1 * std::f32::consts::TAU;
                            // Blend between violet (259°) and cyan (198°)
                            let h = 259.0 / 360.0 - (61.0 / 360.0) * f0;
                            let mut path = PathBuilder::fill();
                            path.move_to(center);
                            path.line_to(point(center.x + px(radius * theta0.cos()), center.y + px(radius * theta0.sin())));
                            path.line_to(point(center.x + px(radius * theta1.cos()), center.y + px(radius * theta1.sin())));
                            path.close();
                            if let Ok(p) = path.build() {
                                window.paint_path(p, gpui::hsla(h, 0.85, 0.65, 0.85));
                            }
                        }

                        // Delicate settled rim
                        let mut rim = PathBuilder::stroke(px(0.5));
                        for i in 0..=24 {
                            let a = std::f32::consts::TAU * i as f32 / 24.0;
                            let pt = point(center.x + px(radius * a.cos()), center.y + px(radius * a.sin()));
                            if i == 0 { rim.move_to(pt); } else { rim.line_to(pt); }
                        }
                        if let Ok(p) = rim.build() {
                            window.paint_path(p, gpui::hsla(0.0, 0.0, 1.0, 0.25));
                        }
                    }
                },
            )
            .absolute()
            .inset_0(),
        )
}
