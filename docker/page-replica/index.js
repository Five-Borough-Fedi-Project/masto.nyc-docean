const puppeteer = require("puppeteer");
const fs = require("fs");
const path = require("path");

/**
 * Configuration settings for the web scraper.
 * @typedef {Object} Config
 * @property {string} baseUrl - The base URL used for creating absolute URLs.
 * @property {boolean} removeJS - Whether to remove JavaScript code from the scraped HTML.
 * @property {boolean} addBaseURL - Whether to add a base URL to the head of the HTML.
 * @property {string} cacheFolder - The folder for caching scraped HTML content.
 */

/**
 * Configuration object with settings.
 * @type {Config}
 */
const CONFIG = {
  baseUrl: process.env.BASE_URL || "https://example.com",
  removeJS: process.env.REMOVE_JS ? process.env.REMOVE_JS === "true" : true,
  addBaseURL: process.env.ADD_BASE_URL ? process.env.ADD_BASE_URL === "true" : true,
  cacheFolder: process.env.CACHE_FOLDER || "/tmp/page-replica",
  restrictToBaseUrl: process.env.RESTRICT_TO_BASE_URL ? process.env.RESTRICT_TO_BASE_URL === "true" : false,
};

/**
 * Function to create necessary folders based on the provided directory path.
 * @param {string} directory - The directory path to create folders for.
 */
const createFolders = (directory) => {
  const folders = directory.split(path.sep);
  folders.shift();
  let currentPath = CONFIG.cacheFolder;
  folders.forEach((folder) => {
    currentPath = path.join(currentPath, folder);
    if (!fs.existsSync(currentPath)) {
      fs.mkdirSync(currentPath);
    }
  });
};

/**
 * Main scraping function.
 * @param {string} pathUrl - The URL to scrape.
 * @param {string} pathUrl - The URL to scrape.
 */
const scrap = async (pathUrl) => {
  try {
    // Check if restriction is enabled and if the URL matches baseUrl
    if (CONFIG.restrictToBaseUrl) {
      const baseHost = new URL(CONFIG.baseUrl).host;
      const targetHost = new URL(pathUrl).host;
      if (baseHost !== targetHost) {
        console.warn(`[SCRAPE] Skipping: ${pathUrl} does not match baseUrl (${CONFIG.baseUrl})`);
        return;
      }
    }

    console.log(`[SCRAPE] Launching browser for ${pathUrl}`);
    // Launch Puppeteer browser
    const launchOptions = {
      headless: true,
      protocolTimeout: 120000,
      args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-gpu",
        "--disable-dev-shm-usage",
        "--no-zygote",
        "--disable-software-rasterizer",
      ],
    };
    if (process.env.PUPPETEER_EXECUTABLE_PATH) {
      launchOptions.executablePath = process.env.PUPPETEER_EXECUTABLE_PATH;
      console.log(`[SCRAPE] Using executable: ${launchOptions.executablePath}`);
    }
    const browser = await puppeteer.launch(launchOptions);
    console.log(`[SCRAPE] Browser launched`);
    // Create a new page in the browser
    const page = await browser.newPage();
    await page.setUserAgent("Mozilla/5.0 (compatible; PageReplica/1.0)");

    page.on("response", (resp) => {
      console.log(`[SCRAPE] Response: ${resp.status()} ${resp.url()}`);
    });

    console.log(`[SCRAPE] Navigating to ${pathUrl} (timeout: 60s, waitUntil: networkidle2)`);
    // Navigate to the specified URL and wait until the page is fully loaded
    await page.goto(pathUrl, { waitUntil: "networkidle2", timeout: 60000 });
    // Get the outer HTML of the entire document
    let html = await page.evaluate(() => document.documentElement.outerHTML);
    console.log(`[SCRAPE] Page loaded, HTML length: ${html.length}`);

    // Remove JavaScript code from the HTML if configured to do so
    if (CONFIG.removeJS) {
      html = html.replace(
        /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi,
        "",
      );
      console.log(`[SCRAPE] Scripts removed, HTML length: ${html.length}`);
    }

    // Add base URL to the head if configured to do so
    if (CONFIG.addBaseURL) {
      html = html.replace(/<head>/gi, `<head><base href="${CONFIG.baseUrl}">`);
    }

    // Create necessary folders for caching based on the URL
    createFolders(pathUrl);
    // Generate a path for caching by removing the protocol (http/https)
    const cachePath = pathUrl.replace(/(^\w+:|^)\/\//, "");
    const filePath = `${CONFIG.cacheFolder}/${cachePath}/index.html`;
    // Write the HTML content to a file in the cache folder
    fs.writeFileSync(filePath, html);
    console.log(`[SCRAPE] Cached to ${filePath} (${html.length} bytes)`);

    // Close the Puppeteer browser
    await browser.close();
    console.log(`[SCRAPE] Done: ${pathUrl}`);
  } catch (error) {
    // Log any errors that occur during the scraping process
    console.error(`[SCRAPE] Error scraping ${pathUrl}:`, error);
    throw error;
  }
};

// Export the scraping function for external use
exports.scrap = scrap;