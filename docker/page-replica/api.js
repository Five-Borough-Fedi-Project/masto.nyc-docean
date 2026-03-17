const process = require("process");
const express = require("express");
const Sitemapper = require("sitemapper");
const scrap = require("./index").scrap;

// Set the maximum number of listeners to unlimited to prevent warning messages
process.setMaxListeners(0);

// Create an instance of Express
const app = express();
// Define the port for the Express app
const port = 8080;

const BASE_URL = process.env.BASE_URL || "";
const AUTO_SCRAPE_INTERVAL_MS = parseInt(process.env.AUTO_SCRAPE_INTERVAL_MS, 10) || 6 * 60 * 60 * 1000; // default 6h

let autoScrapeRunning = false;

async function autoScrape() {
  if (!BASE_URL || autoScrapeRunning) return;
  autoScrapeRunning = true;
  console.log(`[AUTO] Scraping ${BASE_URL}`);
  try {
    await scrap(BASE_URL);
    console.log(`[AUTO] Scrape successful`);
  } catch (err) {
    console.error(`[AUTO] Scrape failed`, err);
  }
  autoScrapeRunning = false;
}

// Start the Express app and listen on the specified port
app.listen(port, () => {
  console.log(`Listening at http://localhost:${port}`);

  if (BASE_URL) {
    console.log(`[AUTO] Will scrape ${BASE_URL} every ${AUTO_SCRAPE_INTERVAL_MS / 1000}s`);
    setTimeout(autoScrape, 30 * 1000);
    setInterval(autoScrape, AUTO_SCRAPE_INTERVAL_MS);
  }
});

/**
 * Endpoint to scrape a single page.
 * @name GET /page
 * @function
 * @memberof app
 * @param {string} url - The URL of the page to be scraped.
 * @returns {void}
 */
app.get("/page", async (req, res) => {
  const url = req.query.url;
  console.log(`[PAGE] Scrape initiated for URL: ${url}`);
  try {
    await scrap(url);
    console.log(`[PAGE] Scrape successful for URL: ${url}`);
    res.status(200).json({ success: true, url });
  } catch (err) {
    console.error(`[PAGE] Scrape failed for URL: ${url}`, err);
    res.status(500).json({ success: false, url, error: err.message });
  }
});

/**
 * Endpoint to scrape pages from a sitemap.
 * @name GET /sitemap
 * @function
 * @memberof app
 * @param {string} url - The URL of the sitemap to be scraped.
 * @returns {void}
 */
app.get("/sitemap", async (req, res) => {
  const sitemapUrl = req.query.url;
  console.log(`[SITEMAP] Scrape initiated for sitemap: ${sitemapUrl}`);
  const sitemap = new Sitemapper();
  try {
    const { sites: urls } = await sitemap.fetch(sitemapUrl);
    console.log(`[SITEMAP] Sitemap fetched, ${urls.length} URLs found.`);
    let successCount = 0;
    let failCount = 0;
    for (const url of urls) {
      try {
        await scrap(url);
        console.log(`[SITEMAP] Scrape successful for URL: ${url}`);
        successCount++;
      } catch (err) {
        console.error(`[SITEMAP] Scrape failed for URL: ${url}`, err);
        failCount++;
      }
      await new Promise(r => setTimeout(r, 3000));
    }
    console.log(`[SITEMAP] Scraping complete for sitemap: ${sitemapUrl}. Success: ${successCount}, Failed: ${failCount}`);
    res.status(200).json({ success: true, sitemapUrl, successCount, failCount });
  } catch (err) {
    console.error(`[SITEMAP] Error fetching sitemap: ${sitemapUrl}`, err);
    res.status(500).json({ success: false, sitemapUrl, error: err.message });
  }
});
