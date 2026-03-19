import type { EventResult, AdapterResult } from "./ticketmaster";
import type { WorkerConfig } from "../lib/config";
import type { Metro } from "../lib/supabase";
import { normalizeToken, normalizeStateToken } from "../lib/normalize";

export interface NightlifeVenue {
  id: string;
  source: "discotech" | "clubbable" | "hwood";
  name: string;
  city?: string;
  state?: string;
  postalCode?: string;
  addressLine1?: string;
  latitude?: number;
  longitude?: number;
  imageURL?: string;
  galleryImages: string[];
  reservationURL?: string;
  reservationProvider?: string;
  openingHoursText?: string;
  ageMinimum?: number;
  doorPolicyText?: string;
  dressCodeText?: string;
  guestListAvailable: boolean;
  bottleServiceAvailable: boolean;
  tableMinPrice?: number;
  coverPrice?: number;
  entryPolicySummary?: string;
  womenEntryPolicyText?: string;
  menEntryPolicyText?: string;
  exclusivityTierLabel?: string;
  nightlifeSignalScore: number;
  prestigeDemandScore: number;
  sourceConfidence: number;
  rawPayload: Record<string, unknown>;
}

interface MarketDiscoveryResult {
  source: "discotech" | "clubbable" | "hwood";
  venues: NightlifeVenue[];
  requestCount: number;
  successCount: number;
  failureCount: number;
  notes: string[];
}

const DESKTOP_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

const DISCOTECH_MARKETS: Record<string, string[]> = {
  ca: ["los-angeles", "san-francisco", "san-diego", "sacramento"],
  ny: ["new-york"],
  fl: ["miami", "orlando", "tampa"],
  nv: ["las-vegas"],
  il: ["chicago"],
  tx: ["dallas", "houston", "austin", "san-antonio"],
  ga: ["atlanta"],
  tn: ["nashville"],
  co: ["denver"],
  az: ["scottsdale", "phoenix"],
  ma: ["boston"],
  pa: ["philadelphia"],
  wa: ["seattle"],
  la: ["new-orleans"],
  dc: ["washington-dc"],
};

const LA_METRO_TOKENS = new Set([
  "los angeles", "west hollywood", "hollywood", "beverly hills",
  "santa monica", "culver city", "silverlake", "silver lake",
  "echo park", "koreatown", "dtla", "downtown la",
]);

const CLUBBABLE_MARKETS: Record<string, string[]> = {
  ca: ["los-angeles", "san-francisco"],
  ny: ["new-york"],
  fl: ["miami"],
  nv: ["las-vegas"],
  il: ["chicago"],
  tx: ["dallas", "houston"],
  ga: ["atlanta"],
  tn: ["nashville"],
};

export async function enrichEventsWithNightlife(
  events: EventResult[],
  metro: Metro,
  _config: WorkerConfig
): Promise<{
  events: EventResult[];
  venueCount: number;
  notes: string[];
}> {
  const state = normalizeStateToken(metro.state);
  const city = normalizeToken(metro.city);
  const notes: string[] = [];

  const discotechMarkets = resolveDiscotechMarkets(state, city);
  const clubbableMarkets = resolveClubbableMarkets(state, city);

  const discoveryResults: MarketDiscoveryResult[] = [];

  const discoveryPromises: Promise<MarketDiscoveryResult>[] = [];

  for (const market of discotechMarkets) {
    discoveryPromises.push(discoverDiscotechMarket(market));
  }
  for (const market of clubbableMarkets) {
    discoveryPromises.push(discoverClubbableMarket(market));
  }
  if (state === "ca" && LA_METRO_TOKENS.has(city)) {
    discoveryPromises.push(discoverHWoodVenues());
  }

  const settled = await Promise.allSettled(discoveryPromises);
  for (const result of settled) {
    if (result.status === "fulfilled") {
      discoveryResults.push(result.value);
      notes.push(...result.value.notes);
    } else {
      notes.push(`Nightlife discovery error: ${result.reason}`);
    }
  }

  const allVenues: NightlifeVenue[] = [];
  for (const result of discoveryResults) {
    allVenues.push(...result.venues);
  }

  const deduped = dedupeNightlifeVenues(allVenues);
  const enriched = enrichEventsFromVenues(events, deduped);

  const venueNightEvents = createVenueNightEvents(deduped, metro);
  const combined = [...enriched, ...venueNightEvents];

  return {
    events: combined,
    venueCount: deduped.length,
    notes,
  };
}

function resolveDiscotechMarkets(state: string, city: string): string[] {
  const markets: string[] = [];
  const stateMarkets = DISCOTECH_MARKETS[state];
  if (!stateMarkets) return markets;

  if (state === "ca" && LA_METRO_TOKENS.has(city)) {
    markets.push("los-angeles");
  } else if (state === "ny" && ["new york", "new york city", "brooklyn", "manhattan", "queens"].includes(city)) {
    markets.push("new-york");
  } else if (state === "fl" && ["miami", "miami beach", "south beach"].includes(city)) {
    markets.push("miami");
  } else if (state === "nv" && ["las vegas", "paradise"].includes(city)) {
    markets.push("las-vegas");
  } else {
    const citySlug = slugify(city);
    if (stateMarkets.includes(citySlug)) {
      markets.push(citySlug);
    }
  }

  return markets.length > 0 ? markets : stateMarkets.slice(0, 1);
}

function resolveClubbableMarkets(state: string, city: string): string[] {
  const markets: string[] = [];
  const stateMarkets = CLUBBABLE_MARKETS[state];
  if (!stateMarkets) return markets;

  if (state === "ca" && LA_METRO_TOKENS.has(city)) {
    markets.push("los-angeles");
  } else if (state === "ny") {
    markets.push("new-york");
  } else if (state === "fl" && ["miami", "miami beach"].includes(city)) {
    markets.push("miami");
  } else if (state === "nv") {
    markets.push("las-vegas");
  } else {
    const citySlug = slugify(city);
    if (stateMarkets.includes(citySlug)) {
      markets.push(citySlug);
    }
  }

  return markets;
}

async function discoverDiscotechMarket(market: string): Promise<MarketDiscoveryResult> {
  const result: MarketDiscoveryResult = {
    source: "discotech",
    venues: [],
    requestCount: 0,
    successCount: 0,
    failureCount: 0,
    notes: [],
  };

  const marketURL = `https://discotech.me/${market}/`;
  result.requestCount++;

  try {
    const marketHTML = await fetchHTML(marketURL);
    if (!marketHTML) {
      result.failureCount++;
      result.notes.push(`Discotech market ${market}: failed to fetch`);
      return result;
    }
    result.successCount++;

    const celebrityMentions = extractMentionList(marketHTML, "find celebrities at");
    const hotListMentions = extractMentionList(marketHTML, "The hottest clubs in");

    for (const mention of uniqueStrings([...celebrityMentions, ...hotListMentions])) {
      const name = sanitizedNightlifeMentionName(mention);
      if (!name) continue;

      result.venues.push({
        id: `discotech-mention:${market}:${slugify(name)}`,
        source: "discotech",
        name,
        nightlifeSignalScore: celebrityMentions.includes(mention) ? 9.2 : 8.4,
        prestigeDemandScore: celebrityMentions.includes(mention) ? 10.0 : 9.0,
        sourceConfidence: 0.58,
        guestListAvailable: false,
        bottleServiceAvailable: false,
        galleryImages: [],
        rawPayload: {
          discotech_market_mention: true,
          discotech_market: market,
          discotech_celebrity_mention: celebrityMentions.includes(mention),
        },
      });
    }

    const venueURLs = extractDiscotechVenueURLs(marketHTML, market);
    const venuePageLimit = Math.min(venueURLs.length, 18);

    const pageFetches = await Promise.allSettled(
      venueURLs.slice(0, venuePageLimit).map(async (url) => {
        result.requestCount++;
        const html = await fetchHTML(url);
        if (!html) {
          result.failureCount++;
          return null;
        }
        result.successCount++;
        return parseDiscotechVenuePage(html, url, market);
      })
    );

    for (const fetch of pageFetches) {
      if (fetch.status === "fulfilled" && fetch.value) {
        result.venues.push(fetch.value);
      }
    }
  } catch (err) {
    result.failureCount++;
    result.notes.push(`Discotech market ${market}: ${String(err)}`);
  }

  return result;
}

async function discoverClubbableMarket(market: string): Promise<MarketDiscoveryResult> {
  const result: MarketDiscoveryResult = {
    source: "clubbable",
    venues: [],
    requestCount: 0,
    successCount: 0,
    failureCount: 0,
    notes: [],
  };

  const marketURL = `https://www.clubbable.com/${market}`;
  result.requestCount++;

  try {
    const marketHTML = await fetchHTML(marketURL);
    if (!marketHTML) {
      result.failureCount++;
      result.notes.push(`Clubbable market ${market}: failed to fetch`);
      return result;
    }
    result.successCount++;

    const venueURLs = extractClubbableVenueURLs(marketHTML, market);
    const venuePageLimit = Math.min(venueURLs.length, 16);

    const pageFetches = await Promise.allSettled(
      venueURLs.slice(0, venuePageLimit).map(async (url) => {
        result.requestCount++;
        const html = await fetchHTML(url);
        if (!html) {
          result.failureCount++;
          return null;
        }
        result.successCount++;
        return parseClubbableVenuePage(html, url, market);
      })
    );

    for (const fetch of pageFetches) {
      if (fetch.status === "fulfilled" && fetch.value) {
        result.venues.push(fetch.value);
      }
    }
  } catch (err) {
    result.failureCount++;
    result.notes.push(`Clubbable market ${market}: ${String(err)}`);
  }

  return result;
}

async function discoverHWoodVenues(): Promise<MarketDiscoveryResult> {
  const result: MarketDiscoveryResult = {
    source: "hwood",
    venues: [],
    requestCount: 0,
    successCount: 0,
    failureCount: 0,
    notes: [],
  };

  const url = "https://rolodex.hwoodgroup.com/";
  result.requestCount++;

  try {
    const html = await fetchHTML(url);
    if (!html) {
      result.failureCount++;
      result.notes.push("HWood Rolodex: failed to fetch");
      return result;
    }
    result.successCount++;

    const plainText = stripHTML(html);
    const guestListVenues = extractVenueList(
      plainText,
      "Guest list access to",
      ["10 off table bookings", "monthly", "access to", "apply"]
    );
    const tableBookingVenues = extractVenueList(
      plainText,
      "10 off table bookings at",
      ["when you book", "monthly", "access to", "apply"]
    );
    const hotspotVenues = extractVenueList(
      plainText,
      "Los Angeles Hotspots",
      ["global ouposts", "locations", "cities", "discover unmatched luxury"]
    );

    const allKeys = new Set([...guestListVenues, ...tableBookingVenues, ...hotspotVenues]);

    for (const venueKey of allKeys) {
      const displayName = humanizedVenueName(venueKey.replace(/ /g, "-"));
      const listedForGuestList = guestListVenues.includes(venueKey);
      const listedForTables = tableBookingVenues.includes(venueKey);
      const listedAsHotspot = hotspotVenues.includes(venueKey);

      let doorPolicyText: string | undefined;
      if (listedForGuestList && listedForTables) {
        doorPolicyText = "Guest list access and table bookings are offered through h.wood Rolodex.";
      } else if (listedForGuestList) {
        doorPolicyText = "Guest list access is offered through h.wood Rolodex.";
      } else if (listedForTables) {
        doorPolicyText = "Table bookings are offered through h.wood Rolodex.";
      }

      result.venues.push({
        id: `hwood:${slugify(displayName)}`,
        source: "hwood",
        name: displayName,
        guestListAvailable: listedForGuestList,
        bottleServiceAvailable: listedForTables,
        doorPolicyText,
        nightlifeSignalScore:
          3.5 + (listedForGuestList ? 1.8 : 0) + (listedForTables ? 2.4 : 0) + (listedAsHotspot ? 1.4 : 0),
        prestigeDemandScore:
          3.8 + (listedAsHotspot ? 2.2 : 0) + (listedForGuestList ? 0.8 : 0),
        sourceConfidence: 0.42,
        galleryImages: [],
        rawPayload: {
          hwood_guest_list: listedForGuestList,
          hwood_table_booking: listedForTables,
          hwood_hotspot: listedAsHotspot,
          hwood_summary: listedAsHotspot
            ? "Recognized by h.wood Rolodex as a nightlife hotspot."
            : "Listed by h.wood Rolodex.",
        },
      });
    }
  } catch (err) {
    result.failureCount++;
    result.notes.push(`HWood Rolodex: ${String(err)}`);
  }

  return result;
}

async function fetchHTML(url: string): Promise<string | null> {
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        "User-Agent": DESKTOP_USER_AGENT,
        "Accept-Language": "en-US,en;q=0.9",
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) return null;
    return await response.text();
  } catch {
    return null;
  }
}

function extractDiscotechVenueURLs(html: string, market: string): string[] {
  const escapedMarket = market.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const regex = new RegExp(
    `https://discotech\\.me/${escapedMarket}/([A-Za-z0-9%\\-]+)/?`,
    "gi"
  );
  const seen = new Set<string>();
  const urls: string[] = [];

  for (const match of html.matchAll(regex)) {
    const slug = match[1]?.replace(/\/$/, "");
    if (!slug || !isLikelyNightlifeVenueSlug(slug)) continue;
    const url = `https://discotech.me/${market}/${slug}/`;
    if (seen.has(url)) continue;
    seen.add(url);
    urls.push(url);
  }

  return urls;
}

function extractClubbableVenueURLs(html: string, market: string): string[] {
  const escapedMarket = market.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const regex = new RegExp(
    `/${escapedMarket}/([A-Za-z0-9\\-]+)`,
    "gi"
  );
  const seen = new Set<string>();
  const urls: string[] = [];

  for (const match of html.matchAll(regex)) {
    const slug = match[1]?.replace(/\/$/, "");
    if (!slug || !isLikelyNightlifeVenueSlug(slug)) continue;
    const url = `https://www.clubbable.com/${market}/${slug}`;
    if (seen.has(url)) continue;
    seen.add(url);
    urls.push(url);
  }

  return urls;
}

function parseDiscotechVenuePage(
  html: string,
  url: string,
  market: string
): NightlifeVenue | null {
  const normalizedHTML = normalizeToken(html);
  const slug = new URL(url).pathname.split("/").filter(Boolean).pop() ?? "";
  const name = extractFirstRegexGroup(html, /<h1[^>]*>(.*?)<\/h1>/is) ?? humanizedVenueName(slug);

  if (!name || !isLikelyNightlifeVenueName(name)) return null;

  const metaDescription = extractFirstRegexGroup(
    html,
    /<meta[^>]+name="description"[^>]+content="([^"]+)"/i
  );
  const ogImage = extractFirstRegexGroup(
    html,
    /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/i
  );

  const galleryImages = extractDiscotechGalleryImages(html);

  const insiderTips = extractDiscotechListSection(html, "Insider Tips");
  const qaPairs = extractDiscotechQAPairs(html);

  const coverAnswer = findQAAnswer(qaPairs, "cover charge");
  const openAnswer = findQAAnswer(qaPairs, "open");
  const dressCodeAnswer = findQAAnswer(qaPairs, "dress code");
  const drinksAnswer = findQAAnswer(qaPairs, "drinks cost");
  const waitAnswer = findQAAnswer(qaPairs, "wait");
  const musicAnswer = findQAAnswer(qaPairs, "kind of music");
  const bestNightsAnswer = findQAAnswer(qaPairs, "best nights");

  const womenEntry = extractEntrySnippet(html, ["women", "ladies", "girls", "female"]);
  const menEntry = extractEntrySnippet(html, ["men", "guys", "gentlemen", "male"]);

  const guestListAvailable = normalizedHTML.includes("guest list");
  const bottleServiceAvailable = normalizedHTML.includes("bottle service");

  const coverPrice = parseCoverPrice(coverAnswer);
  const tableMinPrice = Math.max(
    parseTableMinimum(drinksAnswer) ?? 0,
    parseTableMinimum(coverAnswer) ?? 0,
    parseTableMinimum(metaDescription) ?? 0
  ) || undefined;

  const reservationURL =
    extractFirstRegexGroup(html, new RegExp(`https://discotech\\.me/[^"'\\s<]+/(?:guestlist|bottle-service|tickets)/`, "i")) ??
    extractFirstRegexGroup(html, /https:\/\/(?:app|link)\.discotech\.me\/[^"'\s<]+/i) ??
    url;

  const nightlifeScore = computeNightlifeSignalScore(
    normalizedHTML, tableMinPrice, coverPrice, guestListAvailable, bottleServiceAvailable
  );
  const prestigeScore = computePrestigeScore(
    normalizedHTML,
    [metaDescription, insiderTips.join(". "), drinksAnswer].filter(Boolean).join(" ")
  );

  return {
    id: `discotech:${market}:${slug}`,
    source: "discotech",
    name: stripHTML(name).trim(),
    imageURL: ogImage ?? galleryImages[0],
    galleryImages,
    reservationURL,
    reservationProvider: "Discotech",
    openingHoursText: openAnswer ?? undefined,
    doorPolicyText: [coverAnswer, waitAnswer].filter(Boolean).join(" ") || undefined,
    dressCodeText: dressCodeAnswer ?? undefined,
    guestListAvailable,
    bottleServiceAvailable,
    tableMinPrice,
    coverPrice,
    entryPolicySummary: buildEntryPolicySummary(guestListAvailable, bottleServiceAvailable, tableMinPrice, coverPrice),
    womenEntryPolicyText: womenEntry ?? undefined,
    menEntryPolicyText: menEntry ?? undefined,
    nightlifeSignalScore: nightlifeScore,
    prestigeDemandScore: prestigeScore,
    sourceConfidence: 0.84,
    rawPayload: {
      discotech_url: url,
      discotech_description: metaDescription,
      discotech_image: ogImage,
      discotech_image_gallery: galleryImages,
      discotech_insider_tips: insiderTips,
      discotech_cover_answer: coverAnswer,
      discotech_open_answer: openAnswer,
      discotech_dress_code: dressCodeAnswer,
      discotech_drinks_answer: drinksAnswer,
      discotech_music_answer: musicAnswer,
      discotech_best_nights: bestNightsAnswer,
      discotech_wait_answer: waitAnswer,
      discotech_women_entry: womenEntry,
      discotech_men_entry: menEntry,
    },
  };
}

function parseClubbableVenuePage(
  html: string,
  url: string,
  market: string
): NightlifeVenue | null {
  const rawTitle = extractFirstRegexGroup(html, /<title>([^<]+)<\/title>/i);
  const slug = new URL(url).pathname.split("/").filter(Boolean).pop() ?? "";
  const name = normalizedClubbableTitle(rawTitle, slug) ?? humanizedVenueName(slug);

  if (!name || !isLikelyNightlifeVenueName(name)) return null;

  const normalizedDesc = normalizeToken(html);
  const blockedGenericTokens = [
    "all the best vip nightclubs in london",
    "all the promoters",
    "club managers owners",
    "create a group in the app",
    "get many offers of everything for free",
  ];
  if (blockedGenericTokens.some((t) => normalizedDesc.includes(t))) return null;

  const metaDescription = extractFirstRegexGroup(
    html,
    /<meta[^>]+(?:name|property)="description"[^>]+content="([^"]+)"/i
  );
  const ogImage = extractFirstRegexGroup(
    html,
    /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/i
  );
  const longDescription = extractFirstRegexGroup(
    html,
    /<div[^>]+long-description[^>]*><span>(.*?)<\/span><\/div>/is
  );

  const galleryImages = extractClubbableGalleryImages(html);

  const timeRange = extractFirstRegexGroup(
    html,
    /(\d{1,2}:\d{2}\s*[AP]M\s*-\s*\d{2}:\d{2}\s*[AP]M)/i
  );
  const minimumAge = (() => {
    const match = extractFirstRegexGroup(html, /Minimum Age:\s*(\d+)/i);
    return match ? parseInt(match, 10) : undefined;
  })();
  const tableMinPrice = (() => {
    const match = extractFirstRegexGroup(html, /Table prices from\s*\$([0-9,]+)/i);
    return match ? parseInt(match.replace(/,/g, ""), 10) : undefined;
  })();

  const bookTablePath = extractFirstRegexGroup(
    html,
    /<a[^>]+href="([^"]*tableBooking[^"]*)"[^>]*>Book Table<\/a>/i
  );
  const guestListPath = extractFirstRegexGroup(
    html,
    /<a[^>]+href="([^"]*guestList[^"]*)"[^>]*>Request Guest List<\/a>/i
  );

  const guestListAvailable = guestListPath !== null;
  const bottleServiceAvailable = bookTablePath !== null;

  const womenEntry = extractEntrySnippet(html, ["women", "ladies", "girls", "female"]);
  const menEntry = extractEntrySnippet(html, ["men", "guys", "gentlemen", "male"]);

  const addressLine1 = extractFirstRegexGroup(html, /itemprop="streetAddress"[^>]*>([^<]+)/i);
  const city = extractFirstRegexGroup(html, /itemprop="addressLocality"[^>]*>([^<]+)/i);
  const state = extractFirstRegexGroup(html, /itemprop="addressRegion"[^>]*>([^<]+)/i);
  const postalCode = extractFirstRegexGroup(html, /itemprop="postalCode"[^>]*>([^<]+)/i);

  const descNormalized = normalizeToken(
    [metaDescription, longDescription].filter(Boolean).join(" ")
  );

  const nightlifeScore = computeNightlifeSignalScore(
    descNormalized, tableMinPrice, undefined, guestListAvailable, bottleServiceAvailable
  );
  const prestigeScore = computePrestigeScore(
    descNormalized,
    [metaDescription, longDescription].filter(Boolean).join(" ")
  );

  const reservationURL = bookTablePath
    ? absoluteURL(bookTablePath, url)
    : guestListPath
    ? absoluteURL(guestListPath, url)
    : undefined;

  return {
    id: `clubbable:${market}:${slug}`,
    source: "clubbable",
    name: stripHTML(name).trim(),
    city: city?.trim(),
    state: state?.trim(),
    postalCode: postalCode?.trim(),
    addressLine1: addressLine1?.trim(),
    imageURL: ogImage ?? galleryImages[0],
    galleryImages,
    reservationURL,
    reservationProvider: "Clubbable",
    openingHoursText: timeRange ?? undefined,
    ageMinimum: minimumAge,
    doorPolicyText: buildClubbableDoorPolicy(guestListAvailable, bottleServiceAvailable, tableMinPrice),
    guestListAvailable,
    bottleServiceAvailable,
    tableMinPrice,
    entryPolicySummary: buildEntryPolicySummary(guestListAvailable, bottleServiceAvailable, tableMinPrice, undefined),
    womenEntryPolicyText: womenEntry ?? undefined,
    menEntryPolicyText: menEntry ?? undefined,
    nightlifeSignalScore: nightlifeScore,
    prestigeDemandScore: prestigeScore,
    sourceConfidence: 0.83,
    rawPayload: {
      clubbable_url: url,
      clubbable_description: stripHTML(longDescription ?? metaDescription ?? ""),
      clubbable_image: ogImage,
      clubbable_image_gallery: galleryImages,
      clubbable_time_range: timeRange,
      clubbable_schedule_display: timeRange,
      clubbable_address_line_1: addressLine1,
      clubbable_city: city,
      clubbable_state: state,
      clubbable_postal_code: postalCode,
      clubbable_table_min: tableMinPrice,
      clubbable_minimum_age: minimumAge,
      clubbable_guest_list: guestListPath,
      clubbable_table_link: bookTablePath,
      clubbable_women_entry: womenEntry,
      clubbable_men_entry: menEntry,
    },
  };
}

function dedupeNightlifeVenues(venues: NightlifeVenue[]): NightlifeVenue[] {
  const byName = new Map<string, NightlifeVenue>();

  for (const venue of venues) {
    const key = normalizeToken(venue.name);
    if (!key) continue;

    const existing = byName.get(key);
    if (!existing) {
      byName.set(key, venue);
      continue;
    }

    byName.set(key, mergeNightlifeVenues(existing, venue));
  }

  return Array.from(byName.values());
}

function mergeNightlifeVenues(a: NightlifeVenue, b: NightlifeVenue): NightlifeVenue {
  const primary = a.sourceConfidence >= b.sourceConfidence ? a : b;
  const secondary = primary === a ? b : a;

  return {
    ...primary,
    imageURL: primary.imageURL ?? secondary.imageURL,
    galleryImages: uniqueStrings([...primary.galleryImages, ...secondary.galleryImages]),
    reservationURL: primary.reservationURL ?? secondary.reservationURL,
    reservationProvider: primary.reservationProvider ?? secondary.reservationProvider,
    openingHoursText: primary.openingHoursText ?? secondary.openingHoursText,
    ageMinimum: primary.ageMinimum ?? secondary.ageMinimum,
    doorPolicyText: longerText(primary.doorPolicyText, secondary.doorPolicyText),
    dressCodeText: primary.dressCodeText ?? secondary.dressCodeText,
    guestListAvailable: primary.guestListAvailable || secondary.guestListAvailable,
    bottleServiceAvailable: primary.bottleServiceAvailable || secondary.bottleServiceAvailable,
    tableMinPrice: Math.max(primary.tableMinPrice ?? 0, secondary.tableMinPrice ?? 0) || undefined,
    coverPrice: primary.coverPrice ?? secondary.coverPrice,
    entryPolicySummary: longerText(primary.entryPolicySummary, secondary.entryPolicySummary),
    womenEntryPolicyText: longerText(primary.womenEntryPolicyText, secondary.womenEntryPolicyText),
    menEntryPolicyText: longerText(primary.menEntryPolicyText, secondary.menEntryPolicyText),
    exclusivityTierLabel: primary.exclusivityTierLabel ?? secondary.exclusivityTierLabel,
    nightlifeSignalScore: Math.max(primary.nightlifeSignalScore, secondary.nightlifeSignalScore),
    prestigeDemandScore: Math.max(primary.prestigeDemandScore, secondary.prestigeDemandScore),
    sourceConfidence: Math.max(primary.sourceConfidence, secondary.sourceConfidence),
    rawPayload: { ...secondary.rawPayload, ...primary.rawPayload },
    city: primary.city ?? secondary.city,
    state: primary.state ?? secondary.state,
    postalCode: primary.postalCode ?? secondary.postalCode,
    addressLine1: primary.addressLine1 ?? secondary.addressLine1,
    latitude: primary.latitude ?? secondary.latitude,
    longitude: primary.longitude ?? secondary.longitude,
  };
}

function enrichEventsFromVenues(
  events: EventResult[],
  venues: NightlifeVenue[]
): EventResult[] {
  if (venues.length === 0) return events;

  const venueByName = new Map<string, NightlifeVenue>();
  for (const venue of venues) {
    venueByName.set(normalizeToken(venue.name), venue);
  }

  return events.map((event) => {
    const eventType = (event.eventType || "").toLowerCase();
    if (eventType !== "party / nightlife" && eventType !== "party_nightlife") return event;

    const venueKey = normalizeToken(event.venueName ?? "");
    const venue = venueByName.get(venueKey);
    if (!venue) return event;

    return {
      ...event,
      rawSourcePayload: {
        ...event.rawSourcePayload,
        ...venue.rawPayload,
      },
    };
  });
}

function createVenueNightEvents(
  venues: NightlifeVenue[],
  metro: Metro
): EventResult[] {
  return venues
    .filter((v) =>
      v.sourceConfidence >= 0.5 &&
      (v.reservationURL || v.guestListAvailable || v.bottleServiceAvailable ||
       v.tableMinPrice || v.coverPrice || v.doorPolicyText || v.openingHoursText)
    )
    .sort((a, b) => {
      const aScore = a.nightlifeSignalScore + a.prestigeDemandScore;
      const bScore = b.nightlifeSignalScore + b.prestigeDemandScore;
      return bScore - aScore;
    })
    .slice(0, 72)
    .map((venue): EventResult => {
      const tags: string[] = [];
      if (venue.guestListAvailable) tags.push("guest list");
      if (venue.bottleServiceAvailable) tags.push("bottle service");
      if (venue.dressCodeText) tags.push("dress code");
      if (venue.ageMinimum === 21) tags.push("21+");

      return {
        id: `${venue.source}:venue-night:${venue.id}`,
        source: venue.source,
        sourceEventId: `venue-night:${venue.id}`,
        sourceUrl: venue.reservationURL,
        title: venue.name,
        shortDescription: venue.doorPolicyText,
        eventType: "party / nightlife",
        venueName: venue.name,
        addressLine1: venue.addressLine1,
        city: venue.city ?? metro.city,
        state: venue.state ?? metro.state,
        postalCode: venue.postalCode ?? metro.postal_code ?? undefined,
        latitude: venue.latitude ?? metro.latitude,
        longitude: venue.longitude ?? metro.longitude,
        imageUrl: venue.imageURL,
        status: "scheduled",
        tags,
        rawSourcePayload: {
          ...venue.rawPayload,
          record_kind: "venue_night",
          nightlife_signal_score: venue.nightlifeSignalScore,
          prestige_demand_score: venue.prestigeDemandScore,
          source_confidence: venue.sourceConfidence,
          guest_list_available: venue.guestListAvailable,
          bottle_service_available: venue.bottleServiceAvailable,
          table_min_price: venue.tableMinPrice,
          cover_price: venue.coverPrice,
          door_policy_text: venue.doorPolicyText,
          dress_code_text: venue.dressCodeText,
          opening_hours_text: venue.openingHoursText,
          entry_policy_summary: venue.entryPolicySummary,
          women_entry_policy_text: venue.womenEntryPolicyText,
          men_entry_policy_text: venue.menEntryPolicyText,
          exclusivity_tier_label: venue.exclusivityTierLabel,
          reservation_url: venue.reservationURL,
          reservation_provider: venue.reservationProvider,
        },
      };
    });
}

function extractMentionList(html: string, prefix: string): string[] {
  const plainText = stripHTML(html);
  const normalized = plainText.toLowerCase();
  const index = normalized.indexOf(prefix.toLowerCase());
  if (index < 0) return [];

  const afterPrefix = plainText.substring(index + prefix.length);
  const periodIndex = afterPrefix.indexOf(".");
  const segment = periodIndex >= 0 ? afterPrefix.substring(0, periodIndex) : afterPrefix.substring(0, 300);

  return segment
    .split(/[,;&]|\band\b/)
    .map((s) => s.trim())
    .filter((s) => s.length > 1 && s.length < 60);
}

function extractVenueList(
  text: string,
  prefix: string,
  stopTokens: string[]
): string[] {
  const lower = text.toLowerCase();
  const index = lower.indexOf(prefix.toLowerCase());
  if (index < 0) return [];

  const afterPrefix = text.substring(index + prefix.length);
  let endIndex = afterPrefix.length;
  for (const stop of stopTokens) {
    const stopIdx = afterPrefix.toLowerCase().indexOf(stop.toLowerCase());
    if (stopIdx >= 0 && stopIdx < endIndex) {
      endIndex = stopIdx;
    }
  }

  const segment = afterPrefix.substring(0, endIndex);
  return segment
    .split(/[,;&]|\band\b/)
    .map((s) => normalizeToken(s))
    .filter((s) => s.length > 1);
}

function extractDiscotechListSection(html: string, title: string): string[] {
  const regex = new RegExp(
    `<h[2-4][^>]*>[^<]*${title}[^<]*</h[2-4]>\\s*<(?:ul|ol)[^>]*>(.*?)</(?:ul|ol)>`,
    "is"
  );
  const match = html.match(regex);
  if (!match?.[1]) return [];

  return Array.from(match[1].matchAll(/<li[^>]*>(.*?)<\/li>/gis))
    .map((m) => stripHTML(m[1]).trim())
    .filter((s) => s.length > 3 && s.length < 300);
}

function extractDiscotechQAPairs(html: string): Array<{ question: string; answer: string }> {
  const pairs: Array<{ question: string; answer: string }> = [];

  const qaRegex = /<(?:h[2-5]|div|dt|strong)[^>]*class="[^"]*(?:question|faq|qa)[^"]*"[^>]*>(.*?)<\/(?:h[2-5]|div|dt|strong)>\s*<(?:div|dd|p)[^>]*>(.*?)<\/(?:div|dd|p)>/gis;
  for (const match of html.matchAll(qaRegex)) {
    pairs.push({
      question: stripHTML(match[1]).trim().toLowerCase(),
      answer: stripHTML(match[2]).trim(),
    });
  }

  const toggleRegex = /<(?:button|summary|span)[^>]*>(.*?\?)<\/(?:button|summary|span)>\s*(?:<[^>]+>\s*)*<(?:div|p|span)[^>]*>(.*?)<\/(?:div|p|span)>/gis;
  for (const match of html.matchAll(toggleRegex)) {
    const question = stripHTML(match[1]).trim().toLowerCase();
    const answer = stripHTML(match[2]).trim();
    if (question.length > 5 && answer.length > 5) {
      pairs.push({ question, answer });
    }
  }

  return pairs;
}

function findQAAnswer(pairs: Array<{ question: string; answer: string }>, keyword: string): string | null {
  for (const pair of pairs) {
    if (pair.question.includes(keyword)) {
      return pair.answer || null;
    }
  }
  return null;
}

function extractEntrySnippet(
  html: string,
  keywords: string[]
): string | null {
  const plainText = stripHTML(html);
  const sentences = plainText.split(/[.!?\n]+/).map((s) => s.trim()).filter(Boolean);

  const matches = sentences.filter((s) => {
    const lower = s.toLowerCase();
    return keywords.some((k) => lower.includes(k)) &&
      (lower.includes("entry") || lower.includes("free") || lower.includes("cover") ||
       lower.includes("door") || lower.includes("admission") || lower.includes("list"));
  });

  return matches.length > 0 ? matches.slice(0, 2).join(". ") : null;
}

function extractDiscotechGalleryImages(html: string): string[] {
  const regex = /<img[^>]+src="([^"]+wp-content\/uploads\/[^"]+\.(?:jpe?g|png|webp)[^"]*)"/gi;
  const images: string[] = [];
  const seen = new Set<string>();
  const blocked = ["logo", "structured-data-logo", "newsfeed", "resize=36", "resize=80", "resize=180"];

  for (const match of html.matchAll(regex)) {
    const url = match[1];
    if (!url || seen.has(url)) continue;
    if (blocked.some((b) => url.toLowerCase().includes(b))) continue;
    seen.add(url);
    images.push(url);
    if (images.length >= 8) break;
  }
  return images;
}

function extractClubbableGalleryImages(html: string): string[] {
  const regex = /(?:data-src|data-thumb|content)="([^"]+clubbable\.blob\.core\.windows\.net\/medias\/[^"]+)"/gi;
  const images: string[] = [];
  const seen = new Set<string>();
  const blocked = ["placeholder", "logo", "youtube", "_200"];

  for (const match of html.matchAll(regex)) {
    const url = match[1];
    if (!url || seen.has(url)) continue;
    if (blocked.some((b) => url.toLowerCase().includes(b))) continue;
    seen.add(url);
    images.push(url);
    if (images.length >= 8) break;
  }
  return images;
}

function computeNightlifeSignalScore(
  normalizedHTML: string,
  tableMinPrice?: number,
  coverPrice?: number,
  guestListAvailable?: boolean,
  bottleServiceAvailable?: boolean
): number {
  let score = 4.0;
  if (normalizedHTML.includes("guest list")) score += 2.0;
  if (normalizedHTML.includes("bottle service")) score += 2.5;
  if (normalizedHTML.includes("vip")) score += 1.5;
  if (normalizedHTML.includes("dress code")) score += 1.0;
  if (normalizedHTML.includes("velvet rope") || normalizedHTML.includes("door policy")) score += 1.5;
  if (tableMinPrice && tableMinPrice >= 500) score += 2.0;
  else if (tableMinPrice && tableMinPrice >= 200) score += 1.0;
  if (coverPrice && coverPrice >= 30) score += 1.0;
  if (guestListAvailable) score += 1.5;
  if (bottleServiceAvailable) score += 2.0;
  return score;
}

function computePrestigeScore(normalizedHTML: string, contextText: string): number {
  let score = 3.0;
  const lower = normalizedHTML + " " + normalizeToken(contextText);
  if (lower.includes("celebrity") || lower.includes("celebrities")) score += 2.5;
  if (lower.includes("exclusive")) score += 1.5;
  if (lower.includes("a-list") || lower.includes("alist")) score += 2.0;
  if (lower.includes("vip")) score += 1.0;
  if (lower.includes("high end") || lower.includes("highend") || lower.includes("upscale")) score += 1.0;
  if (lower.includes("red carpet")) score += 1.5;
  return score;
}

function buildEntryPolicySummary(
  guestListAvailable: boolean,
  bottleServiceAvailable: boolean,
  tableMinPrice?: number,
  coverPrice?: number
): string | undefined {
  const parts: string[] = [];
  if (guestListAvailable && bottleServiceAvailable) {
    parts.push("Guest list and table service available.");
  } else if (bottleServiceAvailable) {
    parts.push("Table service strongly favored.");
  } else if (guestListAvailable) {
    parts.push("Guest list available.");
  }
  if (tableMinPrice) {
    parts.push(`Tables from $${tableMinPrice.toLocaleString()}.`);
  }
  if (coverPrice) {
    parts.push(`Cover from $${coverPrice}.`);
  }
  return parts.length > 0 ? parts.join(" ") : undefined;
}

function buildClubbableDoorPolicy(
  guestListAvailable: boolean,
  bottleServiceAvailable: boolean,
  tableMinPrice?: number
): string | undefined {
  const parts: string[] = [];
  if (guestListAvailable && bottleServiceAvailable) {
    parts.push("Guest list and table booking structure.");
  } else if (bottleServiceAvailable) {
    parts.push("Table booking strongly favored.");
  }
  if (tableMinPrice) {
    parts.push(`Tables from $${tableMinPrice.toLocaleString()}.`);
  }
  return parts.length > 0 ? parts.join(" ") : undefined;
}

function parseCoverPrice(text: string | null): number | undefined {
  if (!text) return undefined;
  const match = text.match(/\$(\d+)/);
  return match ? parseInt(match[1], 10) : undefined;
}

function parseTableMinimum(text: string | null): number | undefined {
  if (!text) return undefined;
  const match = text.match(/(?:table|bottle|minimum)[^$]*\$([0-9,]+)/i);
  if (!match) return undefined;
  return parseInt(match[1].replace(/,/g, ""), 10) || undefined;
}

function normalizedClubbableTitle(rawTitle: string | null, slug: string): string | null {
  if (!rawTitle) return humanizedVenueName(slug);
  const cleaned = stripHTML(rawTitle).replace(/&amp;/g, "&").trim();
  const lower = cleaned.toLowerCase();
  if (lower.includes("guest list") || lower.includes("table bookings") || lower.includes("vip table")) {
    return humanizedVenueName(slug);
  }
  return cleaned || humanizedVenueName(slug);
}

function isLikelyNightlifeVenueSlug(slug: string): boolean {
  if (slug.length < 2 || slug.length > 80) return false;
  const blocked = [
    "search", "feed", "rss", "newsfeed", "tag", "category",
    "promo-code", "promo-codes", "about", "contact", "privacy",
    "terms", "blog", "news", "faq",
  ];
  return !blocked.includes(slug.toLowerCase());
}

function isLikelyNightlifeVenueName(name: string): boolean {
  const lower = normalizeToken(name);
  if (lower.length < 2) return false;
  const blockedPhrases = [
    "promo code", "discount", "coupon", "free entry for",
    "how to", "guide to", "best clubs in", "top nightclubs",
  ];
  return !blockedPhrases.some((p) => lower.includes(p));
}

function sanitizedNightlifeMentionName(mention: string): string | null {
  const trimmed = mention.trim();
  if (trimmed.length < 2 || trimmed.length > 60) return null;
  const lower = normalizeToken(trimmed);
  if (lower.includes("promo") || lower.includes("discount") || lower.includes("free entry")) return null;
  return trimmed;
}

function slugify(text: string): string {
  return normalizeToken(text)
    .replace(/\s+/g, "-")
    .replace(/[^a-z0-9-]/g, "")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

function humanizedVenueName(slug: string): string {
  return slug
    .replace(/-/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .trim();
}

function stripHTML(html: string): string {
  return html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
}

function extractFirstRegexGroup(text: string, regex: RegExp): string | null {
  const match = text.match(regex);
  return match?.[1] ?? null;
}

function longerText(a?: string, b?: string): string | undefined {
  if (!a) return b;
  if (!b) return a;
  return a.length >= b.length ? a : b;
}

function absoluteURL(path: string, baseURL: string): string | undefined {
  if (path.startsWith("http")) return path;
  try {
    return new URL(path, baseURL).toString();
  } catch {
    return undefined;
  }
}

function uniqueStrings(arr: string[]): string[] {
  return [...new Set(arr)];
}
