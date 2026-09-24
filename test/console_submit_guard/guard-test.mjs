// ── THE CONSOLE SUBMIT GUARD, IN A REAL BROWSER ─────────────────────────────
//
// app/assets/javascripts/karwan_admin.js, driven in Chrome against the REAL
// wallet page markup and the REAL Administrate bundle, counting the POSTs the
// browser actually sends. Not part of the RSpec suite (no browser there);
// the suite holds only that the script is linked and served.
//
//   DUMP_DIR=$(mktemp -d) bundle exec rspec test/console_submit_guard/dump_wallet_page.rb
//   D=$DUMP_DIR node test/console_submit_guard/guard-test.mjs
//
// Playwright is borrowed from karwan-map's node_modules (PLAYWRIGHT_FROM to
// override) and drives the installed Chrome (CHROME to override); nothing is
// downloaded.
//
// WHAT WAS MEASURED WRITING IT, 24 Sept 2026 — each a way this test lied first:
//   * A same-instant double click sends ONE POST even with no guard: Chrome
//     merges it into one navigation. The bug is the second press a moment
//     later on a slow line — 2 POSTs at 100ms, 600ms and 2s with no guard.
//   * Playwright's page.click never delivered that second press (it waits for
//     actionability), so the first version passed with the guard removed.
//     Raw mouse and keyboard input now.
//   * Chrome here RELOADS on Back after a failed request, so the "usable after
//     failure" check holds without the guard's re-enable; block 5 tests the
//     back-forward-cache restore path directly.
//
// Plants, each red: guard not served (6 checks fail); pageshow listener
// renamed so it never fires (block 5 fails).
import { createRequire } from "module";
import fs from "fs";
const require = createRequire(process.env.PLAYWRIGHT_FROM || new URL("../../../karwan-map/package.json", import.meta.url).pathname);
const { chromium } = require("playwright");

const D = process.env.D;
const html = fs.readFileSync(`${D}/wallet.html`, "utf8");
const scripts = Object.fromEntries(fs.readdirSync(D).filter(f => f.endsWith(".js")).map(f => [f, fs.readFileSync(`${D}/${f}`)]));
const PAGE = "http://console.test/admin/courier_wallets/1";

let failures = 0;
const check = (name, ok, detail = "") => { console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); if (!ok) failures++; };

async function fresh(browser, { postMode = "slow" } = {}) {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.addInitScript(() => {
    document.addEventListener("submit", e => {
      const b = e.target.querySelector('input[type="submit"]');
      setTimeout(() => { window.name = b && b.disabled ? "disabled" : "enabled"; }, 30);
    });
  });
  const posts = [];
  await page.route("**/*", async route => {
    const req = route.request();
    const url = new URL(req.url());
    if (req.method() === "POST") {
      posts.push({ path: url.pathname, body: req.postData(), at: Date.now() });
      if (postMode === "abort") return route.abort("internetdisconnected");
      await new Promise(r => setTimeout(r, 1500));
      return route.fulfill({ status: 302, headers: { location: PAGE } });
    }
    if (url.pathname.startsWith("/assets/")) {
      const body = scripts[url.pathname.split("/").pop()];
      return body ? route.fulfill({ status: 200, contentType: "application/javascript", body }) : route.fulfill({ status: 404, body: "" });
    }
    if (url.pathname === "/admin/courier_wallets/1") return route.fulfill({ status: 200, contentType: "text/html", body: html });
    return route.fulfill({ status: 404, body: "" });
  });
  await page.goto(PAGE);
  await page.waitForFunction(() => document.readyState === "complete");
  await page.waitForTimeout(300); // deferred scripts
  return { context, page, posts };
}

const browser = await chromium.launch({ executablePath: process.env.CHROME || "/usr/bin/google-chrome", headless: true });
try {
  const topUp = 'form[action$="/top_up"]';

  // 1. Double click on the money button.
  {
    const { context, page, posts } = await fresh(browser);
    await page.fill(`${topUp} input[name="amount"]`, "500");
    // A second press a moment later, on a slow connection — the case that
    // credits twice. (A true same-instant double click Chrome already merges
    // into one navigation; measured, so it is not the case worth testing.)
    // Raw mouse input: Playwright's page.click waits for the element to be
    // actionable and never delivered the second press — which made this pass
    // with no guard at all. Measured, then changed.
    const box = await (await page.$(`${topUp} input[type="submit"]`)).boundingBox();
    await page.mouse.click(box.x + 5, box.y + 5);
    await page.waitForTimeout(600);
    await page.mouse.click(box.x + 5, box.y + 5);
    await page.waitForTimeout(1900);
    // Read back what the page itself saw 30ms after the submit (window.name
    // survives the navigation that follows).
    const disabled = await page.evaluate(() => window.name);
    await page.waitForTimeout(1600);
    check("a second press 600ms later sends no second POST", posts.length === 1, `${posts.length} POST(s)`);
    check("the button is disabled while it is in flight", disabled === "disabled", String(disabled));
    check("the amount still reaches the server", /amount=500/.test(posts[0]?.body || ""), posts[0]?.body);
    await context.close();
  }

  // 2. Enter pressed repeatedly in the amount field.
  {
    const { context, page, posts } = await fresh(browser);
    await page.fill(`${topUp} input[name="amount"]`, "500");
    await page.focus(`${topUp} input[name="amount"]`);
    await page.keyboard.press("Enter");
    await page.waitForTimeout(600);
    await page.keyboard.press("Enter");
    await page.waitForTimeout(600);
    await page.keyboard.press("Enter");
    await page.waitForTimeout(1900);
    check("Enter pressed three times, 600ms apart, sends one POST", posts.length === 1, `${posts.length} POST(s)`);
    await context.close();
  }

  // 3. The confirm that was never asked.
  const adjust = 'form[action$="/adjust"]';
  {
    const { context, page, posts } = await fresh(browser);
    const asked = [];
    page.on("dialog", d => { asked.push(d.message()); d.dismiss(); });
    await page.fill(`${adjust} input[name="amount"]`, "-50");
    await page.fill(`${adjust} [name="note"]`, "miscount");
    await page.click(`${adjust} input[type="submit"]`);
    await page.waitForTimeout(500);
    const enabled = await page.$eval(`${adjust} input[type="submit"]`, b => !b.disabled).catch(() => false);
    check("Adjust asks its confirm", asked.length === 1, asked[0]);
    check("declining it sends nothing", posts.length === 0, `${posts.length} POST(s)`);
    check("and leaves the button usable", enabled);
    page.removeAllListeners("dialog");
    page.on("dialog", d => d.accept());
    await page.click(`${adjust} input[type="submit"]`, { timeout: 2000 }).catch(() => {});
    await page.waitForTimeout(1900);
    check("accepting it sends one POST", posts.length === 1, `${posts.length} POST(s)`);
    await context.close();
  }

  // 4. A request that fails is not left dead.
  {
    const { context, page, posts } = await fresh(browser, { postMode: "abort" });
    await page.fill(`${topUp} input[name="amount"]`, "500");
    await page.click(`${topUp} input[type="submit"]`);
    await page.waitForTimeout(800);
    await page.goBack().catch(() => {});
    await page.waitForTimeout(500);
    const onPage = page.url() === PAGE;
    const enabled = onPage && await page.$eval(`${topUp} input[type="submit"]`, b => !b.disabled);
    // Chrome here RELOADS on Back (persisted: false, a second GET), so this
    // holds with or without the guard's re-enable. It proves the failure is
    // recoverable in Chrome, not that the pageshow handler works — block 5 does.
    check("after a failed request and Back, Chrome gives a usable form", onPage && enabled, `url=${page.url()}`);
    await context.close();
  }

  // 5. A page restored from the back-forward cache with its buttons disabled.
  //    The navigation is held back by a listener that runs AFTER the guard's
  //    capture-phase one, so the guard really disables the buttons; then a
  //    real persisted pageshow is fired, as a bfcache restore does.
  {
    const { context, page } = await fresh(browser);
    await page.evaluate(() => document.addEventListener("submit", e => e.preventDefault()));
    await page.fill(`${topUp} input[name="amount"]`, "500");
    const box = await (await page.$(`${topUp} input[type="submit"]`)).boundingBox();
    await page.mouse.click(box.x + 5, box.y + 5);
    await page.waitForTimeout(100);
    const disabledFirst = await page.$eval(`${topUp} input[type="submit"]`, b => b.disabled);
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true })));
    const enabledAfter = await page.$eval(`${topUp} input[type="submit"]`, b => !b.disabled);
    const unlocked = await page.$eval(topUp, f => !f.hasAttribute("data-karwan-submitting"));
    check("a restored page's disabled buttons are enabled again", disabledFirst && enabledAfter && unlocked,
          `disabled first: ${disabledFirst}, enabled after: ${enabledAfter}, form unlocked: ${unlocked}`);
    await context.close();
  }
} finally {
  await browser.close();
}
console.log(failures ? `${failures} FAILED` : "ALL PASS");
process.exit(failures ? 1 : 0);
