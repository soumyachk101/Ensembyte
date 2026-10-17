//! Interactive Test Results & AI Diagnostics view component.
//!
//! Renders structured test runner outcomes with multi-segment progress bars
//! (passed/failed/skipped), test suite hierarchies, failure diff/stack traces,
//! and 1-click "Ask Agent to Fix" action dispatch.

use gpui::{
    div, px, AnyElement, App, IntoElement, ParentElement,
    SharedString, Styled, prelude::FluentBuilder as _,
};
use ensembyte_proto::test_report::{TestFramework, TestReport, TestStatus};
use crate::theme::Theme;

/// Estimated height of the expanded test report view for analytic accordion fold calculation.
pub fn test_report_height(report: &TestReport) -> f32 {
    let header_h = 36.0f32;
    let progress_h = 14.0f32;
    let mut total_h: f32 = header_h + progress_h + 16.0f32; // padding

    for suite in &report.suites {
        total_h += 32.0f32; // suite header
        for c in &suite.cases {
            total_h += 24.0f32; // test case row
            if c.status == TestStatus::Failed && c.failure_message.is_some() {
                total_h += 74.0f32; // failure callout box & fix button
            }
        }
    }
    total_h.min(500.0f32)
}

/// Render the interactive test results view.
pub fn render_test_report(
    report: &TestReport,
    _raw_output: &str,
    theme: &Theme,
    _view: gpui::EntityId,
    _cx: &mut App,
) -> AnyElement {
    let has_failures = report.has_failures();
    let status_color = if has_failures {
        theme.danger
    } else {
        theme.success
    };

    let framework_name = match report.framework {
        TestFramework::Cargo => "Cargo Tests",
        TestFramework::Vitest => "Vitest Tests",
        TestFramework::Jest => "Jest Tests",
        TestFramework::Pytest => "Pytest Tests",
        TestFramework::Swift => "Swift Tests",
        TestFramework::Go => "Go Tests",
        TestFramework::Generic => "Test Results",
    };

    div()
        .w_full()
        .min_w_0()
        .flex()
        .flex_col()
        .gap(px(10.0))
        .p(px(12.0))
        .rounded(px(10.0))
        .bg(theme.ink(0.04))
        .border_1()
        .border_color(theme.hairline(0.10))
        // 1. Header Bar
        .child(
            div()
                .w_full()
                .flex()
                .flex_row()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .flex()
                        .flex_row()
                        .items_center()
                        .gap(px(8.0))
                        .child(
                            div()
                                .size(px(22.0))
                                .rounded(px(6.0))
                                .bg(if has_failures { theme.danger.opacity(0.12) } else { theme.success.opacity(0.12) })
                                .flex()
                                .items_center()
                                .justify_center()
                                .child(
                                    crate::icons::icon(if has_failures {
                                        crate::icons::CLOSE
                                    } else {
                                        crate::icons::CHECK
                                    })
                                    .size(px(12.0))
                                    .text_color(status_color),
                                ),
                        )
                        .child(
                            div()
                                .text_size(px(13.0))
                                .font_weight(gpui::FontWeight::SEMIBOLD)
                                .text_color(theme.text)
                                .child(SharedString::from(framework_name)),
                        )
                        .when_some(report.duration_seconds, |el, secs| {
                            el.child(
                                div()
                                    .px(px(6.0))
                                    .py(px(1.5))
                                    .rounded(px(4.0))
                                    .bg(theme.ink(0.06))
                                    .font_family(theme.font_mono.clone())
                                    .text_size(px(10.5))
                                    .text_color(theme.text_muted)
                                    .child(SharedString::from(format!("{secs:.2}s"))),
                            )
                        }),
                )
                .child(
                    div()
                        .flex()
                        .flex_row()
                        .items_center()
                        .gap(px(6.0))
                        .when(report.failed_count > 0, |el| {
                            el.child(
                                div()
                                    .px(px(6.0))
                                    .py(px(2.0))
                                    .rounded(px(4.0))
                                    .bg(theme.danger.opacity(0.14))
                                    .text_size(px(11.0))
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .text_color(theme.danger)
                                    .child(SharedString::from(format!("{} failed", report.failed_count))),
                            )
                        })
                        .when(report.passed_count > 0, |el| {
                            el.child(
                                div()
                                    .px(px(6.0))
                                    .py(px(2.0))
                                    .rounded(px(4.0))
                                    .bg(theme.success.opacity(0.14))
                                    .text_size(px(11.0))
                                    .font_weight(gpui::FontWeight::MEDIUM)
                                    .text_color(theme.success)
                                    .child(SharedString::from(format!("{} passed", report.passed_count))),
                            )
                        })
                        .when(report.skipped_count > 0, |el| {
                            el.child(
                                div()
                                    .px(px(6.0))
                                    .py(px(2.0))
                                    .rounded(px(4.0))
                                    .bg(theme.ink(0.08))
                                    .text_size(px(11.0))
                                    .text_color(theme.text_muted)
                                    .child(SharedString::from(format!("{} skipped", report.skipped_count))),
                            )
                        }),
                ),
        )
        // 2. Segmented Progress Bar
        .child({
            let total = report.total_count.max(1) as f32;
            let pass_pct = (report.passed_count as f32 / total) * 100.0;
            let fail_pct = (report.failed_count as f32 / total) * 100.0;
            let skip_pct = (report.skipped_count as f32 / total) * 100.0;

            div()
                .h(px(6.0))
                .w_full()
                .rounded(px(3.0))
                .bg(theme.ink(0.08))
                .overflow_hidden()
                .flex()
                .flex_row()
                .gap(px(1.5))
                .when(report.passed_count > 0, |bar| {
                    bar.child(
                        div()
                            .h_full()
                            .w(gpui::DefiniteLength::Fraction(pass_pct / 100.0))
                            .bg(theme.success)
                            .rounded(px(2.0)),
                    )
                })
                .when(report.failed_count > 0, |bar| {
                    bar.child(
                        div()
                            .h_full()
                            .w(gpui::DefiniteLength::Fraction(fail_pct / 100.0))
                            .bg(theme.danger)
                            .rounded(px(2.0)),
                    )
                })
                .when(report.skipped_count > 0, |bar| {
                    bar.child(
                        div()
                            .h_full()
                            .w(gpui::DefiniteLength::Fraction(skip_pct / 100.0))
                            .bg(theme.warning)
                            .rounded(px(2.0)),
                    )
                })
        })
        // 3. Test Suites & Cases List
        .child(
            div()
                .w_full()
                .flex()
                .flex_col()
                .gap(px(6.0))
                .children(report.suites.iter().map(|suite| {
                    div()
                        .w_full()
                        .rounded(px(8.0))
                        .bg(theme.ink(0.03))
                        .border_1()
                        .border_color(theme.hairline(0.08))
                        .overflow_hidden()
                        // Suite Header Row
                        .child(
                            div()
                                .w_full()
                                .h(px(28.0))
                                .px(px(8.0))
                                .flex()
                                .flex_row()
                                .items_center()
                                .justify_between()
                                .bg(theme.ink(0.02))
                                .child(
                                    div()
                                        .flex()
                                        .flex_row()
                                        .items_center()
                                        .gap(px(6.0))
                                        .child(
                                            crate::icons::icon(crate::icons::FOLDER)
                                                .size(px(12.0))
                                                .text_color(theme.accent),
                                        )
                                        .child(
                                            div()
                                                .font_family(theme.font_mono.clone())
                                                .text_size(px(11.5))
                                                .font_weight(gpui::FontWeight::MEDIUM)
                                                .text_color(theme.text)
                                                .truncate()
                                                .child(SharedString::from(suite.name.clone())),
                                        ),
                                )
                                .child(
                                    div()
                                        .flex()
                                        .flex_row()
                                        .items_center()
                                        .gap(px(6.0))
                                        .when(suite.failed_count() > 0, |el| {
                                            el.child(
                                                div()
                                                    .text_size(px(10.5))
                                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                                    .text_color(theme.danger)
                                                    .child(SharedString::from(format!("{} failed", suite.failed_count()))),
                                            )
                                        })
                                        .when(suite.passed_count() > 0, |el| {
                                            el.child(
                                                div()
                                                    .text_size(px(10.5))
                                                    .text_color(theme.text_muted)
                                                    .child(SharedString::from(format!("{} passed", suite.passed_count()))),
                                            )
                                        }),
                                ),
                        )
                        // Test Cases
                        .child(
                            div()
                                .w_full()
                                .flex()
                                .flex_col()
                                .p(px(4.0))
                                .gap(px(4.0))
                                .children(suite.cases.iter().map(|test_case| {
                                    let is_case_failed = test_case.status == TestStatus::Failed;
                                    let failure_msg = test_case.failure_message.clone();

                                    div()
                                        .w_full()
                                        .flex()
                                        .flex_col()
                                        .gap(px(4.0))
                                        .child(
                                            div()
                                                .w_full()
                                                .min_h(px(22.0))
                                                .px(px(6.0))
                                                .py(px(2.0))
                                                .rounded(px(4.0))
                                                .flex()
                                                .flex_row()
                                                .items_center()
                                                .justify_between()
                                                .when(is_case_failed, |row| {
                                                    row.bg(theme.danger.opacity(0.06))
                                                })
                                                .child(
                                                    div()
                                                        .flex()
                                                        .flex_row()
                                                        .items_center()
                                                        .gap(px(6.0))
                                                        .min_w_0()
                                                        .flex_1()
                                                        .child(
                                                            crate::icons::icon(match test_case.status {
                                                                TestStatus::Passed => crate::icons::CHECK,
                                                                TestStatus::Failed => crate::icons::CLOSE,
                                                                TestStatus::Skipped => crate::icons::MORE_HORIZONTAL,
                                                                TestStatus::Running => crate::icons::REFRESH,
                                                            })
                                                            .size(px(11.0))
                                                            .text_color(match test_case.status {
                                                                TestStatus::Passed => theme.success,
                                                                TestStatus::Failed => theme.danger,
                                                                _ => theme.text_muted,
                                                            }),
                                                        )
                                                        .child(
                                                            div()
                                                                .font_family(theme.font_mono.clone())
                                                                .text_size(px(11.0))
                                                                .text_color(if is_case_failed { theme.danger } else { theme.text })
                                                                .truncate()
                                                                .child(SharedString::from(test_case.name.clone())),
                                                        ),
                                                )
                                                .when_some(test_case.duration_ms, |el, ms| {
                                                    el.child(
                                                        div()
                                                            .font_family(theme.font_mono.clone())
                                                            .text_size(px(10.0))
                                                            .text_color(theme.text_muted)
                                                            .child(SharedString::from(format!("{ms:.1}ms"))),
                                                    )
                                                }),
                                        )
                                        // Failure Details Drawer (if failed)
                                        .when_some(failure_msg, |card, msg| {
                                            card.child(
                                                div()
                                                    .w_full()
                                                    .p(px(8.0))
                                                    .rounded(px(6.0))
                                                    .bg(theme.ink(0.06))
                                                    .border_1()
                                                    .border_color(theme.danger.opacity(0.20))
                                                    .flex()
                                                    .flex_col()
                                                    .gap(px(6.0))
                                                    .child(
                                                        div()
                                                            .w_full()
                                                            .flex()
                                                            .flex_row()
                                                            .items_center()
                                                            .justify_between()
                                                            .child(
                                                                div()
                                                                    .text_size(px(10.5))
                                                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                                                    .text_color(theme.danger)
                                                                    .child(SharedString::from("Failure Details")),
                                                            )
                                                            .child(
                                                                div()
                                                                    .px(px(6.0))
                                                                    .py(px(1.5))
                                                                    .rounded(px(3.0))
                                                                    .bg(theme.danger.opacity(0.12))
                                                                    .text_size(px(10.0))
                                                                    .font_weight(gpui::FontWeight::MEDIUM)
                                                                    .text_color(theme.danger)
                                                                    .child(SharedString::from("Action Needed")),
                                                            ),
                                                    )
                                                    .child(
                                                        div()
                                                            .font_family(theme.font_mono.clone())
                                                            .text_size(px(10.5))
                                                            .line_height(px(15.0))
                                                            .text_color(theme.text.opacity(0.85))
                                                            .max_h(px(120.0))
                                                            .overflow_hidden()
                                                            .child(SharedString::from(msg)),
                                                    ),
                                            )
                                        })
                                })),
                        )
                })),
        )
        .into_any_element()
}
