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

// Start the Express app and listen on the specified port
app.listen(port, () => {
  console.log(`Example app listening at http://localhost:${port}`);
});

/**
 * Endpoint to scrape a single page.
 * @name GET /page
 * @function
 * @memberof app
 * @param {string} url - The URL of the page to be scraped.
 * @returns {void}
 */
app.get("/page", (req, res) => {
  // Extract the URL from the query parameters
  const url = req.query.url;
  console.log(`[PAGE] Requested scrape for URL: ${url}`);
  // Call the scrap function to scrape the specified page
  scrap(url);
  console.log(`[PAGE] Scrape initiated for URL: ${url}`);
  // Send a response without any content
  res.send();
});

/**
 * Endpoint to scrape pages from a sitemap.
 * @name GET /sitemap
 * @function
 * @memberof app
 * @param {string} url - The URL of the sitemap to be scraped.
 * @returns {void}
 */
app.get("/sitemap", (req, res) => {
  // Create a new instance of Sitemapper
  const sitemapUrl = req.query.url;
  console.log(`[SITEMAP] Requested scrape for sitemap: ${sitemapUrl}`);
  const sitemap = new Sitemapper();
  // Fetch the sitemap from the specified URL
  sitemap.fetch(sitemapUrl).then(function ({ sites }) {
    // Extract the list of URLs from the fetched sitemap
    const urls = sites;
    console.log(`[SITEMAP] Sitemap fetched, ${urls.length} URLs found.`);
    // Set an interval to scrape each URL with a delay of 3000 milliseconds (3 seconds)
    const interval = setInterval(() => {
      const url = urls.shift();
      if (!url) {
        // If there are no more URLs, clear the interval
        clearInterval(interval);
        console.log(`[SITEMAP] All URLs scraped for sitemap: ${sitemapUrl}`);
        return;
      }
      console.log(`[SITEMAP] Scraping URL from sitemap: ${url}`);
      // Call the scrap function to scrape the current URL
      scrap(url);
    }, 3000);
  }).catch((err) => {
    console.error(`[SITEMAP] Error fetching sitemap: ${sitemapUrl}`, err);
  });
  // Send a response without any content
  res.send();
});
