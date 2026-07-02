/**
 * Minimal browser-side helper for experiments inside the work-report iframe.
 *
 * This file intentionally contains no private selectors or values. Load your
 * private config in the runner and pass concrete values to this helper.
 */
function fillWorkReportTiny(options) {
  const frame = document.getElementById(options.frameId);
  if (!frame) return { ok: false, error: "missing frame" };

  const doc = frame.contentDocument || frame.contentWindow.document;
  const win = doc.defaultView || doc.parentWindow;

  doc.getElementById(options.dateInputId).value = options.date;
  doc.getElementById(options.hiddenDateInputId).value = options.date;
  win.jQuery("#" + options.hoursInputId).numberbox("setValue", options.hours);

  const content = doc.getElementById(options.contentInputId);
  content.focus();
  content.value = options.content;
  content.dispatchEvent(new Event("input", { bubbles: true }));
  content.dispatchEvent(new Event("change", { bubbles: true }));
  content.dispatchEvent(new Event("blur", { bubbles: true }));

  return { ok: true };
}
