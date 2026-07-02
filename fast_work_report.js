const { spawnSync } = require("node:child_process");
const path = require("node:path");

// Thin cross-tooling wrapper. Keeping the real logic in PowerShell avoids
// Windows .cmd argument escaping problems when passing JavaScript to OpenCLI.
const script = path.join(__dirname, "fast_work_report.ps1");
const args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, ...process.argv.slice(2)];
const result = spawnSync("pwsh", args, { stdio: "inherit", windowsHide: true });

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
process.exit(result.status ?? 0);
