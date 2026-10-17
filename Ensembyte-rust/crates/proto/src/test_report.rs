//! Interactive Test Results & Diagnostics data models and output parsers.
//!
//! Provides structured status reporting, segmented progress metrics,
//! and automated failure extraction for test runner executions (Cargo, Vitest,
//! Jest, Pytest, Swift, Go).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TestStatus {
    Passed,
    Failed,
    Skipped,
    Running,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TestFramework {
    Vitest,
    Jest,
    Cargo,
    Pytest,
    Swift,
    Go,
    Generic,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TestCase {
    pub id: String,
    pub name: String,
    pub status: TestStatus,
    pub duration_ms: Option<f64>,
    pub failure_message: Option<String>,
}

impl TestCase {
    pub fn new(name: impl Into<String>, status: TestStatus) -> Self {
        let n = name.into();
        Self {
            id: n.clone(),
            name: n,
            status,
            duration_ms: None,
            failure_message: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TestSuite {
    pub id: String,
    pub name: String,
    pub status: TestStatus,
    pub cases: Vec<TestCase>,
}

impl TestSuite {
    pub fn new(name: impl Into<String>, status: TestStatus, cases: Vec<TestCase>) -> Self {
        let n = name.into();
        Self {
            id: n.clone(),
            name: n,
            status,
            cases,
        }
    }

    pub fn passed_count(&self) -> usize {
        self.cases.iter().filter(|c| c.status == TestStatus::Passed).count()
    }

    pub fn failed_count(&self) -> usize {
        self.cases.iter().filter(|c| c.status == TestStatus::Failed).count()
    }

    pub fn skipped_count(&self) -> usize {
        self.cases.iter().filter(|c| c.status == TestStatus::Skipped).count()
    }

    pub fn total_count(&self) -> usize {
        self.cases.len()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TestReport {
    pub id: String,
    pub command: String,
    pub framework: TestFramework,
    pub suites: Vec<TestSuite>,
    pub passed_count: usize,
    pub failed_count: usize,
    pub skipped_count: usize,
    pub total_count: usize,
    pub duration_seconds: Option<f64>,
    pub summary_text: String,
}

impl TestReport {
    pub fn has_failures(&self) -> bool {
        self.failed_count > 0
    }

    pub fn is_success(&self) -> bool {
        self.failed_count == 0 && self.total_count > 0
    }

    pub fn failure_summary(&self) -> String {
        let mut lines = Vec::new();
        for suite in &self.suites {
            if suite.failed_count() > 0 {
                lines.push(format!("Suite: {}", suite.name));
                for c in &suite.cases {
                    if c.status == TestStatus::Failed {
                        let msg = c.failure_message.as_deref().unwrap_or("").trim();
                        let first_line = msg.lines().next().unwrap_or(msg);
                        if !first_line.is_empty() {
                            lines.push(format!("  - {}: {}", c.name, first_line));
                        } else {
                            lines.push(format!("  - {}", c.name));
                        }
                    }
                }
            }
        }
        lines.join("\n")
    }
}

pub struct TestOutputParser;

impl TestOutputParser {
    pub fn is_test_command(command: &str) -> bool {
        let lower = command.to_ascii_lowercase();
        const COMMANDS: &[&str] = &[
            "cargo test", "cargo nextest",
            "npm test", "npm run test", "pnpm test", "yarn test", "bun test",
            "vitest", "jest", "pytest", "python -m unittest",
            "swift test", "xcodebuild test",
            "go test", "ctest", "playwright test",
        ];
        COMMANDS.iter().any(|cmd| lower.contains(cmd))
    }

    pub fn contains_test_output(output: &str) -> bool {
        const SIGNATURES: &[&str] = &[
            "test result:", "Test Suites:", "=== RUN", "=== FAIL",
            "PASSED [", "FAILED [", "tests passed", "failures:",
        ];
        SIGNATURES.iter().any(|sig| output.contains(sig))
    }

    pub fn parse(command: &str, output: &str) -> Option<TestReport> {
        let lower = command.to_ascii_lowercase();
        if lower.contains("cargo") || output.contains("test result:") {
            if let Some(report) = Self::parse_cargo(command, output) {
                return Some(report);
            }
        }
        if lower.contains("vitest")
            || lower.contains("jest")
            || lower.contains("npm")
            || lower.contains("bun")
            || lower.contains("pnpm")
            || lower.contains("yarn")
            || output.contains("Test Suites:")
        {
            if let Some(report) = Self::parse_vitest_or_jest(command, output) {
                return Some(report);
            }
        }
        if lower.contains("pytest") || output.contains("PASSED [") || output.contains("FAILED [") {
            if let Some(report) = Self::parse_pytest(command, output) {
                return Some(report);
            }
        }
        if lower.contains("swift test") || lower.contains("xcodebuild") || output.contains("Test Case '-") {
            if let Some(report) = Self::parse_swift_test(command, output) {
                return Some(report);
            }
        }
        if lower.contains("go test") || output.contains("=== RUN") {
            if let Some(report) = Self::parse_go_test(command, output) {
                return Some(report);
            }
        }
        Self::parse_generic(command, output)
    }

    fn parse_cargo(command: &str, output: &str) -> Option<TestReport> {
        let mut cases = Vec::new();
        let mut passed = 0;
        let mut failed = 0;
        let mut skipped = 0;
        let mut duration = None;

        let mut collecting_failures = false;
        let mut current_failed_name: Option<String> = None;
        let mut current_failure_lines: Vec<&str> = Vec::new();
        let mut failure_details: std::collections::HashMap<String, String> = std::collections::HashMap::new();

        for line in output.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("test ")
                && (trimmed.ends_with(" ... ok")
                    || trimmed.ends_with(" ... FAILED")
                    || trimmed.ends_with(" ... ignored"))
            {
                let parts: Vec<&str> = trimmed.split(" ... ").collect();
                if parts.len() >= 2 {
                    let name = parts[0].trim_start_matches("test ");
                    let status_str = parts[1];
                    let status = if status_str.contains("ok") {
                        passed += 1;
                        TestStatus::Passed
                    } else if status_str.contains("FAILED") {
                        failed += 1;
                        TestStatus::Failed
                    } else {
                        skipped += 1;
                        TestStatus::Skipped
                    };
                    cases.push(TestCase::new(name, status));
                }
            } else if trimmed == "failures:" {
                collecting_failures = true;
            } else if collecting_failures && trimmed.starts_with("---- ") && trimmed.ends_with(" ----") {
                if let Some(prev) = current_failed_name.take() {
                    failure_details.insert(prev, current_failure_lines.join("\n"));
                    current_failure_lines.clear();
                }
                let name = trimmed.trim_start_matches("---- ").trim_end_matches(" ----");
                current_failed_name = Some(name.to_string());
            } else if collecting_failures && trimmed.starts_with("test result:") {
                if let Some(prev) = current_failed_name.take() {
                    failure_details.insert(prev, current_failure_lines.join("\n"));
                    current_failure_lines.clear();
                }
                collecting_failures = false;
                if let Some(idx) = trimmed.find("finished in ") {
                    let rest = &trimmed[idx + "finished in ".len()..];
                    let sec_str = rest.trim_end_matches('s').trim();
                    duration = sec_str.parse::<f64>().ok();
                }
            } else if collecting_failures && current_failed_name.is_some() {
                current_failure_lines.push(line);
            }
        }

        for c in &mut cases {
            if c.status == TestStatus::Failed {
                if let Some(detail) = failure_details.get(&c.name) {
                    c.failure_message = Some(detail.trim().to_string());
                }
            }
        }

        if cases.is_empty() && !output.contains("test result:") {
            return None;
        }

        let summary = if failed > 0 {
            format!("{failed} failed, {passed} passed")
        } else {
            format!("{passed} passed")
        };

        let suite = TestSuite::new("Cargo Test Suite", if failed > 0 { TestStatus::Failed } else { TestStatus::Passed }, cases);
        let total = passed + failed + skipped;

        Some(TestReport {
            id: uuid::Uuid::new_v4().to_string(),
            command: command.to_string(),
            framework: TestFramework::Cargo,
            suites: vec![suite],
            passed_count: passed,
            failed_count: failed,
            skipped_count: skipped,
            total_count: total,
            duration_seconds: duration,
            summary_text: summary,
        })
    }

    fn parse_vitest_or_jest(command: &str, output: &str) -> Option<TestReport> {
        let mut suites = Vec::new();
        let mut current_suite: Option<TestSuite> = None;
        let mut current_cases = Vec::new();

        let mut passed = 0;
        let mut failed = 0;
        let mut skipped = 0;
        let mut duration = None;

        for line in output.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("PASS ") || trimmed.starts_with("FAIL ") {
                if let Some(mut s) = current_suite.take() {
                    s.cases = std::mem::take(&mut current_cases);
                    suites.push(s);
                }
                let is_pass = trimmed.starts_with("PASS ");
                let name = trimmed
                    .trim_start_matches("PASS ")
                    .trim_start_matches("FAIL ")
                    .trim();
                current_suite = Some(TestSuite::new(name, if is_pass { TestStatus::Passed } else { TestStatus::Failed }, Vec::new()));
            } else if trimmed.contains("✓ ") || trimmed.contains("✕ ") || trimmed.contains("↓ ") || trimmed.contains("○ ") {
                let status = if trimmed.contains("✓ ") {
                    passed += 1;
                    TestStatus::Passed
                } else if trimmed.contains("✕ ") {
                    failed += 1;
                    TestStatus::Failed
                } else {
                    skipped += 1;
                    TestStatus::Skipped
                };
                let mut name = trimmed.to_string();
                for glyph in &["✓ ", "✕ ", "↓ ", "○ "] {
                    name = name.replace(glyph, "");
                }
                current_cases.push(TestCase::new(name.trim(), status));
            } else if trimmed.starts_with("Time:") {
                let parts: Vec<&str> = trimmed.split_whitespace().collect();
                if parts.len() >= 2 {
                    let sec_str = parts[1].replace('s', "");
                    duration = sec_str.parse::<f64>().ok();
                }
            }
        }

        if let Some(mut s) = current_suite.take() {
            s.cases = current_cases;
            suites.push(s);
        }

        if suites.is_empty() && !output.contains("Test Suites:") {
            return None;
        }

        let total = passed + failed + skipped;
        let summary = if failed > 0 {
            format!("{failed} failed, {passed} passed")
        } else {
            format!("{passed} passed")
        };

        Some(TestReport {
            id: uuid::Uuid::new_v4().to_string(),
            command: command.to_string(),
            framework: TestFramework::Vitest,
            suites,
            passed_count: passed,
            failed_count: failed,
            skipped_count: skipped,
            total_count: total,
            duration_seconds: duration,
            summary_text: summary,
        })
    }

    fn parse_pytest(command: &str, output: &str) -> Option<TestReport> {
        let mut cases = Vec::new();
        let mut passed = 0;
        let mut failed = 0;
        let mut skipped = 0;
        let mut duration = None;

        for line in output.lines() {
            let trimmed = line.trim();
            if trimmed.contains(" PASSED") || trimmed.contains(" FAILED") || trimmed.contains(" SKIPPED") {
                let status = if trimmed.contains(" PASSED") {
                    passed += 1;
                    TestStatus::Passed
                } else if trimmed.contains(" FAILED") {
                    failed += 1;
                    TestStatus::Failed
                } else {
                    skipped += 1;
                    TestStatus::Skipped
                };
                let name = trimmed.split_whitespace().next().unwrap_or(trimmed);
                cases.push(TestCase::new(name, status));
            } else if trimmed.contains(" in ") && trimmed.ends_with("s ====") {
                let parts: Vec<&str> = trimmed.split(" in ").collect();
                if parts.len() == 2 {
                    let sec_str = parts[1].replace("s ====", "").trim().to_string();
                    duration = sec_str.parse::<f64>().ok();
                }
            }
        }

        if cases.is_empty() && !output.contains("pytest") {
            return None;
        }

        let total = passed + failed + skipped;
        let summary = if failed > 0 {
            format!("{failed} failed, {passed} passed")
        } else {
            format!("{passed} passed")
        };

        let suite = TestSuite::new("Pytest Suite", if failed > 0 { TestStatus::Failed } else { TestStatus::Passed }, cases);

        Some(TestReport {
            id: uuid::Uuid::new_v4().to_string(),
            command: command.to_string(),
            framework: TestFramework::Pytest,
            suites: vec![suite],
            passed_count: passed,
            failed_count: failed,
            skipped_count: skipped,
            total_count: total,
            duration_seconds: duration,
            summary_text: summary,
        })
    }

    fn parse_swift_test(command: &str, output: &str) -> Option<TestReport> {
        let mut cases = Vec::new();
        let mut passed = 0;
        let mut failed = 0;
        let mut duration = None;

        for line in output.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("Test Case '") && (trimmed.contains("passed") || trimmed.contains("failed")) {
                let is_pass = trimmed.contains("passed");
                let status = if is_pass {
                    passed += 1;
                    TestStatus::Passed
                } else {
                    failed += 1;
                    TestStatus::Failed
                };
                let parts: Vec<&str> = trimmed.split("' ").collect();
                let name = parts.first().map(|s| s.trim_start_matches("Test Case '")).unwrap_or(trimmed);
                cases.push(TestCase::new(name, status));
            } else if trimmed.starts_with("Executed ") && trimmed.contains("seconds") {
                if let Some(idx) = trimmed.find(" in ") {
                    let rest = &trimmed[idx + 4..];
                    let sec_str = rest.split_whitespace().next().unwrap_or("");
                    duration = sec_str.parse::<f64>().ok();
                }
            }
        }

        if cases.is_empty() {
            return None;
        }

        let total = passed + failed;
        let summary = if failed > 0 {
            format!("{failed} failed, {passed} passed")
        } else {
            format!("{passed} passed")
        };

        let suite = TestSuite::new("Swift Test Suite", if failed > 0 { TestStatus::Failed } else { TestStatus::Passed }, cases);

        Some(TestReport {
            id: uuid::Uuid::new_v4().to_string(),
            command: command.to_string(),
            framework: TestFramework::Swift,
            suites: vec![suite],
            passed_count: passed,
            failed_count: failed,
            skipped_count: 0,
            total_count: total,
            duration_seconds: duration,
            summary_text: summary,
        })
    }

    fn parse_go_test(command: &str, output: &str) -> Option<TestReport> {
        let mut cases = Vec::new();
        let mut passed = 0;
        let mut failed = 0;

        for line in output.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("--- PASS:") || trimmed.starts_with("--- FAIL:") {
                let is_pass = trimmed.starts_with("--- PASS:");
                let status = if is_pass {
                    passed += 1;
                    TestStatus::Passed
                } else {
                    failed += 1;
                    TestStatus::Failed
                };
                let parts: Vec<&str> = trimmed.split_whitespace().collect();
                let name = if parts.len() >= 3 { parts[2] } else { trimmed };
                cases.push(TestCase::new(name, status));
            }
        }

        if cases.is_empty() {
            return None;
        }

        let total = passed + failed;
        let summary = if failed > 0 {
            format!("{failed} failed, {passed} passed")
        } else {
            format!("{passed} passed")
        };

        let suite = TestSuite::new("Go Tests", if failed > 0 { TestStatus::Failed } else { TestStatus::Passed }, cases);

        Some(TestReport {
            id: uuid::Uuid::new_v4().to_string(),
            command: command.to_string(),
            framework: TestFramework::Go,
            suites: vec![suite],
            passed_count: passed,
            failed_count: failed,
            skipped_count: 0,
            total_count: total,
            duration_seconds: None,
            summary_text: summary,
        })
    }

    fn parse_generic(command: &str, output: &str) -> Option<TestReport> {
        if !Self::contains_test_output(output) && !Self::is_test_command(command) {
            return None;
        }
        Some(TestReport {
            id: uuid::Uuid::new_v4().to_string(),
            command: command.to_string(),
            framework: TestFramework::Generic,
            suites: Vec::new(),
            passed_count: 0,
            failed_count: 0,
            skipped_count: 0,
            total_count: 0,
            duration_seconds: None,
            summary_text: "Completed test execution".to_string(),
        })
    }
}
