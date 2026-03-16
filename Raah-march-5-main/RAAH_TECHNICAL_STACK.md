# RAAH — Complete Technical Stack Report
### For Investor & Technical Due Diligence

---

## Table of Contents

1. [What RAAH Is](#1-what-raah-is)
2. [Platform & Language Choices](#2-platform--language-choices)
3. [Architecture — How the App is Structured](#3-architecture--how-the-app-is-structured)
4. [The AI Voice Engine](#4-the-ai-voice-engine)
5. [Location & Spatial Intelligence](#5-location--spatial-intelligence)
6. [Points of Interest (POI) Pipeline](#6-points-of-interest-poi-pipeline)
7. [Context Pipeline — The Brain](#7-context-pipeline--the-brain)
8. [Navigation](#8-navigation)
9. [Memory System](#9-memory-system)
10. [Weather Intelligence](#10-weather-intelligence)
11. [Safety System](#11-safety-system)
12. [Snap & Ask — Vision Feature](#12-snap--ask--vision-feature)
13. [Apple Music Integration](#13-apple-music-integration)
14. [Calendar Awareness](#14-calendar-awareness)
15. [Health & Heart Rate](#15-health--heart-rate)
16. [Affiliate & Ticket Discovery](#16-affiliate--ticket-discovery)
17. [India-Specific Layer](#17-india-specific-layer)
18. [Design System](#18-design-system)
19. [Data Persistence & Storage](#19-data-persistence--storage)
20. [Analytics & Usage Tracking](#20-analytics--usage-tracking)
21. [Lock Screen Widget](#21-lock-screen-widget)
22. [Permissions & Privacy](#22-permissions--privacy)
23. [Dependency Philosophy — Zero Third-Party Libraries](#23-dependency-philosophy--zero-third-party-libraries)
24. [Complete API Surface](#24-complete-api-surface)
25. [What Was Rejected and Why](#25-what-was-rejected-and-why)
26. [Performance Architecture](#26-performance-architecture)
27. [Monetization Architecture](#27-monetization-architecture)
28. [Full Technology Comparison Table](#28-full-technology-comparison-table)

---

## 1. What RAAH Is

RAAH is a **voice-first AI travel companion for iOS**. The user walks around any city in the world, taps an Earth-like orb, and speaks naturally with an AI assistant that has real-time spatial awareness — it knows what buildings are nearby, what restaurants are open right now, what the weather is, how safe the area is, and remembers your preferences from previous conversations.

The core experience: **you walk, you talk, you explore — RAAH handles everything else.**

Unlike Google Maps (navigation tool), TripAdvisor (review browser), or a generic ChatGPT voice interface (no location awareness), RAAH is designed as an ambient intelligent companion that sits in your ear and knows exactly where you are, what time it is, and what you care about.

---

## 2. Platform & Language Choices

### Swift 5.9 + SwiftUI on iOS 17+

**What it is:** Swift is Apple's native programming language for iOS. SwiftUI is Apple's declarative UI framework introduced in 2019. iOS 17 introduced the `@Observable` macro, a modern state management system.

**Why we chose it:**
- Voice processing (AVAudioEngine, AVAudioSession) requires deep native API access — not achievable reliably in cross-platform frameworks
- Real-time audio at 24kHz PCM16 with sub-100ms latency requires direct hardware access
- CoreLocation's precise GPS callbacks, HealthKit heart rate streaming, and MapKit annotation rendering all require native integration
- The app forces dark mode and has a design language that only renders correctly with native SwiftUI rendering (frosted glass materials, spring physics animations)

**What was rejected:**
- **React Native**: WebView-based audio has 200-400ms additional latency, no direct AVAudioEngine access. Unacceptable for a real-time voice product.
- **Flutter**: Dart's audio libraries (just_audio, etc.) are wrappers over native APIs with additional overhead. Deep AVAudioSession configuration (voiceChat mode, Bluetooth routing, echo cancellation) is not reliably exposed.
- **Capacitor/Ionic**: Web audio APIs on mobile are throttled by the browser engine. Not viable for a real-time PCM16 audio pipeline.

**The `@Observable` Macro (iOS 17 Observation Framework):**

Before iOS 17, SwiftUI state management used `ObservableObject` + `@Published` + `@StateObject`. Every `@Published` property change triggered a full view re-render of every subscriber. This caused performance problems as state grew.

iOS 17's `@Observable` uses granular dependency tracking — views re-render only when the exact property they read changes. For RAAH, `AppState` has 40+ properties. Without `@Observable`, a GPS coordinate update would trigger the settings screen to re-render. With `@Observable`, only views reading `locationManager.currentLocation` respond.

---

## 3. Architecture — How the App is Structured

### The Single Source of Truth Pattern

RAAH uses a single `AppState` class that owns every service, every piece of shared state, and every user preference. This object is created once at app launch (`RAAHApp.swift`) and injected into the entire view hierarchy via `.environment(appState)`.

```
RAAHApp
└── AppState (injected via @Environment)
    ├── OpenAIRealtimeService    ← voice WebSocket
    ├── LocationManager          ← GPS
    ├── ContextPipeline          ← context orchestration
    │   ├── GooglePlacesService  ← nearby places
    │   ├── OverpassService      ← OpenStreetMap data
    │   ├── WikipediaService     ← place descriptions
    │   ├── WeatherService       ← weather
    │   ├── SafetyScoreService   ← safety scoring
    │   └── SpatialCache         ← L1 data cache
    ├── DirectionsService        ← turn-by-turn walking
    ├── ShortTermMemory          ← 25 recent interactions
    ├── LongTermMemoryManager    ← learned preferences
    ├── HealthKitManager         ← heart rate
    ├── AudioSessionManager      ← audio hardware
    ├── CalendarService          ← schedule awareness
    ├── MusicService             ← Apple Music
    ├── ExplorationLogger        ← journey journaling
    ├── AnalyticsLogger          ← local analytics
    ├── UsageTracker             ← free tier limits
    └── AffiliateService         ← ticket & tour offers
```

**Why one object owns everything:**
- Services need to talk to each other. The voice service needs to know the current POIs. The context pipeline needs to push updates into the voice prompt. Having one owner means no circular dependencies, no notification buses, no shared singletons.
- Singletons (like `Singleton.shared`) are dangerous because they hold state across app restarts and test runs, and they can't be injected for testing. AppState is created fresh every launch.

### View Layer Structure

```
ContentView
├── OnboardingView (first run only)
└── TabView
    ├── HomeView (Tab 1 — voice interface)
    ├── ExploreMapView (Tab 2 — MapKit map)
    └── SettingsView (Tab 3 — preferences)

Overlays (shown on top of TabView):
├── NavigationMapView (full-screen during turn-by-turn)
├── SnapAndAskView (camera sheet)
├── SafetyOverlaySheet (safety alert)
└── PaywallView (upgrade prompt)
```

---

## 4. The AI Voice Engine

This is the most technically sophisticated component in RAAH. Understanding it requires understanding three layers: the API, the audio pipeline, and the tool system.

### 4a. OpenAI Realtime API

**What it is:** OpenAI's Realtime API (`gpt-4o-mini-realtime-preview`) is a WebSocket-based bidirectional streaming API that handles simultaneous audio input, speech recognition, language model inference, and voice synthesis in a single persistent connection. Unlike the standard Chat Completions API (which is HTTP request/response), the Realtime API is always-on — the connection stays open for the entire voice session.

**The WebSocket endpoint:**
```
wss://api.openai.com/v1/realtime?model=gpt-4o-mini-realtime-preview
```

**Why the Realtime API over alternatives:**

| Option | Latency | Voice Quality | Tool Calls | Always-On |
|--------|---------|---------------|-----------|-----------|
| OpenAI Realtime API | ~400ms | Native TTS | Yes (structured) | Yes |
| STT → LLM → TTS pipeline | 2-4 seconds | Separate TTS model | Manual | No |
| ElevenLabs Conversational | ~600ms | High quality | Limited | Yes |
| Hume AI | ~500ms | Emotion-aware | No | Yes |
| Whisper + GPT-4 + TTS | 2-3 seconds | Good | Yes | No |

The 3-layer pipeline (Whisper → GPT-4 → TTS) was the standard approach before mid-2024. It has 2-3 seconds of latency because each step is a separate HTTP request. The Realtime API collapses all three into a single streaming WebSocket, achieving ~400ms end-to-end latency — the threshold for a conversation feeling "natural."

**How the audio pipeline works:**

```
iPhone Microphone
     ↓
AVAudioEngine (capture graph)
     ↓
AVAudioConverter (hardware format → PCM16 mono 24kHz)
     ↓
input_audio_buffer.append (WebSocket JSON + base64 PCM chunk)
     ↓
OpenAI Realtime API (VAD + Whisper + GPT-4o-mini + TTS)
     ↓
response.audio.delta (base64 PCM16 chunks, streamed back)
     ↓
AVAudioPCMBuffer reconstruction
     ↓
AVAudioPlayerNode (playback graph)
     ↓
AVAudioUnitEQ (6dB gain boost)
     ↓
iPhone Speaker / AirPods
```

**PCM16 at 24kHz:** Audio is encoded as 16-bit Pulse Code Modulation at 24,000 samples per second. This is the exact format the Realtime API expects and returns. Converting to/from compressed formats (AAC, MP3) would add latency and quality loss.

**Server-side VAD (Voice Activity Detection):**
Rather than RAAH deciding when the user has finished speaking, the OpenAI server monitors the audio stream and detects speech boundaries automatically. Key parameters:
- `silence_duration_ms: 1200` — waits 1.2 seconds of silence before assuming the user has finished. Set lower (e.g. 300ms) and the AI interrupts mid-sentence; set higher and it feels unresponsive.
- `threshold: 0.5` — sensitivity of voice detection vs background noise.
- `prefix_padding_ms: 300` — includes 300ms of audio before detected speech starts, capturing cut-off consonants.

**The echo problem:**
When the AI speaks through the speaker, the microphone picks up that audio and sends it back to the API — causing the AI to hear its own voice and respond to it. Solution:
1. `suppressMicInput = true` when AI starts speaking — mute the mic input buffer
2. On `response.done`, play a 100ms chime at 880Hz through the speaker
3. After 120ms (chime covers the echo window), set `suppressMicInput = false`
4. Send `input_audio_buffer.clear` to flush any captured echo from the buffer

**The listening chime:**
A sine wave tone generated programmatically:
```
frequency: 880 Hz (musical A5)
duration: 100ms
amplitude: 0.18 (subtle, not jarring)
attack: 5ms, release: 25ms (prevents click artifacts)
```
This gives users instant feedback that the mic is now live — solving the "did it hear me?" friction of voice interfaces.

**Reconnection strategy:**
If the WebSocket disconnects unexpectedly (network drop, background timeout), RAAH attempts reconnection with exponential backoff:
- Attempt 1: wait 1 second
- Attempt 2: wait 2 seconds
- Attempt 3: wait 4 seconds
- ...up to 5 attempts
Each reconnection rebuilds the full session state (system prompt, tools, VAD configuration).

### 4b. The System Prompt — How the AI Knows Where You Are

The AI's spatial awareness comes entirely from the system prompt, which is rebuilt and re-injected into the active session every time the context updates (user moves 100m, or the app comes to foreground).

A real system prompt fragment looks like:
```
USER LOCATION: Panaji, Goa, India (timezone: Asia/Kolkata). Local time: 3:45 PM, Thursday
CURRENT WEATHER: 31°C, clear sky, humidity 72%, wind 12 km/h NNE
EMERGENCY NUMBERS: Police: 100, Ambulance: 102, Fire: 101

NEARBY POINTS OF INTEREST (sorted: open now first, then closest):
- Cafe Bhonsle (restaurant) [4.6★ (312), ₹₹] [OPEN NOW — closes 10:30 PM] 3 min walk
  "A heritage Goan cafe serving traditional sorpotel and sannas in a Portuguese-era building..."
- Old Secretariat (heritage) [OPEN NOW — closes 5:00 PM] 5 min walk
  "Built in 1615, formerly the Adil Shah's summer palace, now houses the Goa Legislative Assembly..."
- ATM - State Bank of India [UTILITY — silent unless asked] 2 min walk
...

LANGUAGE: Always respond in English.
DIETARY RULES: User is vegetarian — hard block: never recommend non-vegetarian food.
BUDGET: User prefers budget/cheap options.
```

The AI never has to "look things up" — everything is pre-injected. This means:
- **No hallucinations about place names** — it can only reference what's in the list
- **Real-time accuracy** — open/closed status is computed live, not from stale cache
- **Sub-second responses** — the AI doesn't need to make additional API calls

### 4c. The Tool System

The AI can trigger actions in the app through "tool calls" — structured function calls embedded in the response stream. RAAH defines 12 tools:

| Tool | What It Does | When the AI Uses It |
|------|-------------|---------------------|
| `get_directions` | Fetch walking directions to a POI | "Take me to that cafe" |
| `search_nearby` | Search Google Places for a specific query | "Find a McDonald's nearby" |
| `check_safety_score` | Get real-time safety rating for a coordinate | "Is this area safe at night?" |
| `find_tickets` | Search GetYourGuide for skip-the-line tickets | "Can I book the fort tour?" |
| `get_current_context` | Return current location, time, and top POIs | Context recall |
| `set_music_vibe` | Play Apple Music matching a mood | "Play something chill" |
| `pause_audio` / `resume_audio` | Control music playback | "Stop the music" |
| `trigger_sos` | Initiate SOS countdown | "Help, emergency" |
| `walk_me_home` | Activate Walk Me Home safety mode | "Walk me home safely" |
| `stop_navigation` | Cancel active turn-by-turn | "Stop directions" |

When the AI calls a tool, `AppState.handleToolCall(name:callId:args:)` handles it, performs the action, and returns a structured result back to the API within milliseconds. The AI then narrates the result in natural language.

**The pre-arrival briefing pattern:**
When `get_directions` is called, RAAH doesn't just return the route. It also looks up the destination POI in the nearby list, extracts its editorial summary, rating, opening hours, and closing time, and injects all of that into the tool result. The AI then gives a 3-sentence briefing about the destination before reading the first direction — "Cafe Bhonsle is a 4.6-star Goan heritage spot, highly reviewed for their sorpotel. They close at 10:30 PM so you have plenty of time. Starting route: Head north on 18th June Road for 200 meters..."

---

## 5. Location & Spatial Intelligence

### LocationManager (CoreLocation)

**What it does:** Wraps `CLLocationManager` to provide GPS coordinates, heading (compass direction), and movement detection.

**How it works:**
- `desiredAccuracy: kCLLocationAccuracyBest` — requests the highest GPS precision (3-5 meter accuracy)
- `distanceFilter: 10` — only fires an update if the device has moved 10+ meters (prevents battery drain from micro-jitter)
- `pausesLocationUpdatesAutomatically: false` — iOS has a "smart" feature that pauses GPS when it thinks you're stationary. We disable this because a user standing still in front of a restaurant still needs live context.
- `activityType: .fitness` — tells CoreLocation this is a walking app, enabling pedestrian path optimization

**The movement threshold:**
A `PassthroughSubject<CLLocation, Never>` called `significantMovementPublisher` fires when the user moves 100 meters from the last context-fetch point. This is what triggers a context refresh. 100 meters was chosen because:
- Smaller (50m): Too frequent, hits API rate limits and wastes battery
- Larger (200m): User could walk past an entire block of POIs without getting updated context

**Location filtering:**
Raw GPS from phones is noisy. Every update is validated:
- `horizontalAccuracy >= 0` — negative accuracy means invalid fix
- `horizontalAccuracy < 500` — reject fixes with >500m uncertainty (GPS just acquired)
- `abs(timestamp.timeIntervalSinceNow) < 30` — reject locations older than 30 seconds (stale cached fix)

**Battery management:**
- Active voice session: `kCLLocationAccuracyBest`, 10m filter (full GPS)
- Navigation: `kCLLocationAccuracyBestForNavigation`, 5m filter (maximum precision)
- Backgrounded/idle: `kCLLocationAccuracyHundredMeters`, 50m filter (battery saver)

**The India geofence:**
`checkIfInIndia(_:)` checks if the coordinate falls within `lat: 6.0–37.0, lon: 68.0–97.5`. This enables India-specific features: DigiPin addresses, Mappls road alerts, India emergency numbers (100/102/101), and India-specific safety context.

---

## 6. Points of Interest (POI) Pipeline

RAAH uses a **two-source POI system**: Google Places for quality/ratings/hours, and OpenStreetMap (via Overpass API) for hyperlocal geographic coverage. These are merged and deduplicated.

### 6a. Google Places API (New) — Primary Source

**What it is:** Google's commercial POI database, covering 250M+ businesses worldwide with ratings, opening hours, editorial summaries, price levels, and phone numbers.

**Why Google Places:**
- Best coverage globally, including India
- Real-time opening hours with `currentOpeningHours.openNow` boolean
- `editorialSummary` — a short paragraph describing the place, perfect for AI narration
- `priceLevel` (₹, ₹₹, ₹₹₹, ₹₹₹₹) for budget matching
- `rating` + `userRatingCount` for quality filtering

**The 2-bucket fetch strategy:**
One Google Places API call has a maximum of 20 results. To get a richer context, RAAH makes two simultaneous calls:
- Bucket 1: Food types (24 categories: restaurant, cafe, bar, bakery, etc.) — 20 results
- Bucket 2: Attraction types (31 categories: museum, park, monument, pharmacy, ATM, etc.) — 20 results

Both run in parallel (`async let`), giving up to 40 POIs per context refresh.

**The `is_open_now` staleness problem (and how we solve it):**
Google returns `openNow` as a boolean at fetch time — but RAAH caches POIs for up to 4 hours. A restaurant fetched at 10 AM with `is_open_now = true` still has that tag at 5 PM when it may be closed.

Solution: `effectiveIsOpenNow(poi:now:timeZone:)` — a runtime function that parses the stored `opens_at`/`closes_at` time strings (e.g., "9:00 AM" / "10:00 PM") and computes the actual current open/closed status against the live clock, handling midnight crossover (e.g., a bar open until 2 AM). This is used for:
1. The OPEN/CLOSED label displayed to the AI
2. The POI sort order (open-first)
3. The `closesBeforeArrival()` check (will it close before I walk there?)

### 6b. OpenStreetMap / Overpass API — Secondary Source

**What it is:** A community-maintained, open-source global map database. The Overpass API is a read query engine for OSM.

**Why Overpass alongside Google:**
- Free, no API key required
- Better for hyperlocal data: street furniture, heritage markers, historic buildings, small temples, informal food stalls — things Google often doesn't index
- OSM `opening_hours` format is more expressive: `"Mo-Fr 09:00-17:00; Sa 10:00-15:00"` vs Google's simple open/close times
- Better coverage in South Asia for heritage/architectural POIs

**The merge strategy:**
Google Places data is `primary` — richer metadata, trusted ratings. Overpass is `secondary` — fills gaps. Deduplication: if an Overpass POI exists within 50 meters of a Google POI with a similar name (fuzzy match), the Google version is kept and the Overpass duplicate is dropped.

### 6c. Wikipedia Enrichment — Two-Pass Architecture

After fetching POIs, RAAH enriches the top 5 closest/highest-ranked POIs with Wikipedia summaries. These summaries become the "editorial narration" material the AI uses when describing a landmark.

**The old (blocking) approach:** Await all 5 Wikipedia fetches before pushing context to the AI. This took 2-5 seconds, during which the AI knew nothing about nearby POIs.

**The new two-pass approach:**
1. **Pass 1 (immediate):** Push the full context to the AI with no Wikipedia data — user can start talking instantly
2. **Pass 2 (background Task):** Fetch Wikipedia summaries for top 5 POIs in parallel, update `currentContext.pois`, re-inject system prompt silently

The AI narration quality improves ~3 seconds after session start, but the session is responsive immediately.

**Wikipedia lookup chain:**
1. Check SpatialCache (7-day TTL for Wikipedia data)
2. If POI has a `wikidata_id` tag (from OSM): fetch entity data → resolve to Wikipedia article title → fetch summary
3. Else: search Wikipedia by POI name → fetch first result summary
4. Trim to 3 sentences maximum (prompt size constraint)

### 6d. POI Data Model

Every POI is stored as a `POI` struct with a flexible `tags: [String: String]` dictionary. This mirrors how OpenStreetMap stores data and allows arbitrary metadata without schema migrations.

Key tags:
```
rating: "4.6"
user_ratings_total: "312"
price_level: "₹₹"
is_open_now: "true"           ← cached at fetch time
opens_at: "9:00 AM"           ← parsed from Google hours
closes_at: "10:30 PM"         ← parsed from Google hours
today_hours: "9:00 AM–10:30 PM"
editorial_summary: "A heritage..."
primary_type: "restaurant"
source: "google"              ← or "overpass"
cuisine: "Indian, Goan"
phone: "+91 832 222 xxxx"
```

---

## 7. Context Pipeline — The Brain

`ContextPipeline` is the orchestration layer that takes a GPS coordinate and produces a fully-formed `SpatialContext` ready to inject into the AI's system prompt.

### The Full Pipeline (annotated)

```
User moves 100m
      ↓
LocationManager.significantMovementPublisher fires
      ↓
ContextPipeline.fetchContext(coordinate:) called
      ↓
[SpatialCache check] ←— Cache TTL:
  POIs: 4 hours           If hit: skip API call
  Weather: 30 min         If miss: fetch live
  Forecast: 6 hours
  Geocode: 24 hours
  Wikipedia: 7 days
      ↓
[Parallel fetch — all 7 run simultaneously via async let]
  ├── GooglePlacesService.fetchNearbyPlaces()    ← 2 bucket calls
  ├── OverpassService.fetchNearbyPOIs()
  ├── WeatherService.fetchCurrentWeatherSummary()
  ├── WeatherService.fetchWeeklyForecast()
  ├── WeatherService.fetchTimezone()
  ├── SafetyScoreService.evaluateSafety()
  └── MapplsService.fetchIndiaData() (if in India)
      ↓
[Merge & deduplicate Google + Overpass POIs]
      ↓
[Sort by distance, push to nearbyPOIs]
      ↓
[Build SpatialContext — assemble weather, safety, geocode, POIs]
      ↓
[Push to currentContext immediately → onContextRefreshed() fires]
      ↓
[AppState.pushSystemPrompt() → inject into OpenAI session if connected]
      ↓
[Background Task: Wikipedia enrichment for top 5 POIs]
      ↓
[Update pois in currentContext, re-inject system prompt]
```

**Why parallel fetch matters:**
Each API call takes 300-800ms. Sequential fetching would take 3-5 seconds. Parallel async lets run all 7 fetches simultaneously, completing in the time of the slowest single call (~800ms).

**The 2-second debounce:**
Between a location update and `fetchContext()` being called, there is a 2-second debounce timer. This prevents a brief GPS jitter (the device briefly reporting a position 110m away, then snapping back) from triggering a full context refresh. The Overpass API has rate limits — unnecessary calls burn quota.

**SpatialContext → System Prompt:**
`SpatialContext.systemPromptFragment(now:timeZone:)` assembles the full context block injected into the AI prompt. Key design decisions:
- **Live time re-computation:** The current time is computed fresh from `Date()` every time the fragment is generated — not cached. This ensures the AI always knows the exact current minute, even if context was fetched 20 minutes ago.
- **Open/closed sorting:** POIs are sorted open-first using `effectiveIsOpenNow()` (live clock), then opening-soon-within-60-minutes, then closed — so the AI naturally recommends accessible places.
- **Rating threshold:** POIs below 3.5★ are tagged — the system prompt instructs the AI to never lead with low-rated options if better alternatives exist.
- **Utility silencing:** ATMs, pharmacies, supermarkets are tagged `[UTILITY — silent unless asked]` — the AI is instructed not to proactively mention these, only surface them when the user shows explicit intent.
- **Closes before arrival:** If a POI is open now but would close before the user could walk there (calculated from walking minutes), it gets `[⚠️ CLOSES BEFORE ARRIVAL]` tag.
- **Hidden gem:** POIs with rating ≥ 4.5★ AND fewer than 80 reviews get `[💎 HIDDEN GEM]` — the AI is instructed to proactively mention these.
- **Top 20 POIs:** The system prompt includes the 20 nearest open/accessible POIs with full metadata. The AI sees these as its sole source of truth for location-specific questions.

---

## 8. Navigation

### DirectionsService

RAAH provides turn-by-turn walking directions without Apple Maps or Google Maps.

**Primary: OSRM (Open Source Routing Machine)**
- Endpoint: `https://router.project-osrm.org/route/v1/foot/{lon1},{lat1};{lon2},{lat2}?steps=true&annotations=true&geometries=geojson`
- Free, open-source, OpenStreetMap-based routing engine
- Returns: step-by-step instructions, polyline coordinates, distances, maneuver types
- `profile: /foot/` — pedestrian routing, uses sidewalks and pedestrian paths not available to driving routing

**Fallback: MKDirections (Apple Maps)**
If OSRM fails (network error, server unavailable), MapKit's built-in directions API is used as fallback. Less detailed step instructions but always available on-device.

**How navigation works in the app:**
1. User asks "take me to [place]" or taps a POI on the map
2. AI calls `get_directions` tool with destination name + coordinates
3. `DirectionsService.getDirectionsWithSteps()` fetches from OSRM
4. Steps are stored in `AppState.navigationSteps`
5. `NavigationMapView` opens full-screen with route polyline
6. Every GPS update: `checkNavigationProgress()` calculates distance from current position to the next waypoint
7. Within 25 meters of a waypoint: auto-advance to next step, announce via AI voice
8. Within 25 meters of final destination: announce arrival, end navigation

**OSRM instruction generation:**
OSRM returns machine-readable maneuver types (`turn-right`, `continue`, `merge`, `roundabout`). `DirectionsService.buildOSRMInstruction()` converts these to human-readable text: "Turn right onto MG Road", "Continue straight for 200 meters", "At the roundabout, take the second exit".

**Pre-arrival briefing:**
When directions start, RAAH looks up the destination in `nearbyPOIs`, extracts its editorial summary, rating, and hours, and injects this into the tool result. The AI narrates this before the first direction. Example: "Luna Rossa is a 4.7-star Italian place, known for their wood-fired pizza. They close at 11 PM tonight, so you have plenty of time. Let's go — head south on Calçada Street for 150 meters..."

---

## 9. Memory System

RAAH has two memory layers: short-term (within session) and long-term (across sessions).

### ShortTermMemory

A rolling buffer of the last 25 user-AI interaction pairs. Each interaction includes:
- The user's spoken message (transcribed text)
- The AI's response text
- Timestamp
- Current GPS location at time of interaction
- Names of the top 3 nearby POIs at the time

This buffer is injected into the system prompt as conversation history context, helping the AI remember what was said earlier in the session. Interactions older than 24 hours are pruned on load.

### LongTermMemory (LongTermMemoryManager)

When a voice session ends, RAAH runs a preference extraction pass:
1. The last 25 interactions are sent to `gpt-4o-mini` with a structured prompt: "Extract user preferences about food, travel style, interests, and dislikes from this conversation"
2. The model returns structured `UserPreference` objects with `category`, `value`, and `confidence` score
3. Preferences are stored locally (UserDefaults) and synced to Supabase (PostgreSQL with pgvector extension)
4. On future sessions, top preferences by confidence are injected into the system prompt

Example extracted preferences:
```
{ category: "cuisine", value: "loves Goan seafood, specifically crab xec xec", confidence: 0.92 }
{ category: "travel_style", value: "prefers off-the-beaten-path over tourist spots", confidence: 0.87 }
{ category: "budget", value: "mid-range budget, avoids luxury restaurants", confidence: 0.84 }
```

**Supabase + pgvector:**
Supabase is a PostgreSQL-based cloud database with a pgvector extension for vector similarity search. Long-term preferences are stored as text embeddings, enabling semantic search: "find preferences relevant to food in Goa" retrieves the most semantically similar stored preferences, not just keyword matches. This allows the memory to scale beyond simple key-value storage.

### Dwell & Feedback Tracking

RAAH tracks how long the user spends near each POI (dwell time). After 10 minutes within 150m of a POI, and once the user moves 300m away, RAAH asks the AI to solicit feedback: "How was the coffee at Cafe Bhonsle?" The response is processed to extract a preference update.

---

## 10. Weather Intelligence

### WeatherService (Open-Meteo)

**What it is:** Open-Meteo is a free, open-source weather API with no API key required. It uses ECMWF (European Centre for Medium-Range Weather Forecasts) data, the same models used by professional meteorologists.

**Why Open-Meteo over alternatives:**

| Service | Cost | API Key | Accuracy | Coverage |
|---------|------|---------|----------|---------|
| Open-Meteo | Free | None | ECMWF (world-class) | Global |
| OpenWeatherMap | Freemium ($0 / limited) | Required | Good | Global |
| WeatherAPI | Freemium | Required | Good | Global |
| Apple WeatherKit | Free (with Apple dev account) | Entitlement required | Good | Global |
| Dark Sky (acquired by Apple) | Discontinued | — | — | — |

No API key means no configuration required from the user, no key rotation, no billing surprises.

**What RAAH fetches:**
- **Current conditions:** Temperature (°C), "feels like" temperature, humidity, wind speed + direction, visibility, UV index, sunrise/sunset times, precipitation (mm), WMO weather code
- **7-day forecast:** Daily min/max temperatures, dominant weather condition, sunrise/sunset, precipitation probability per day

**WMO weather code mapping:**
The World Meteorological Organization standardizes weather conditions as integer codes (0 = clear sky, 45 = foggy, 61 = light rain, 95 = thunderstorm, etc.). `WeatherService.conditionFromCode()` maps these to human-readable descriptions for the AI prompt.

**Timezone detection:**
The same Open-Meteo call returns the timezone string for the user's coordinate (e.g., "Asia/Kolkata"). This is used to correctly format all time-related display (opening hours, local time in prompt, etc.) without relying on the device's timezone setting (which may be wrong if the user has a SIM from another country).

---

## 11. Safety System

### SafetyScoreService

RAAH provides real-time area safety scoring using two layers:

**Primary: GeoSure API**
GeoSure is a commercial safety intelligence platform that scores neighborhoods globally on dimensions including:
- Physical harm risk
- Theft & petty crime risk
- Women's safety index
- LGBTQ+ safety
- Medical risk
- Political climate

GeoSure returns a 0-100 score per coordinate. RAAH maps this to four safety levels: `safe` (75+), `moderate` (50-74), `caution` (25-49), `danger` (<25).

**Fallback: Heuristic scoring**
If GeoSure is unconfigured or unavailable, RAAH computes a heuristic score from:
- Time of day (late night → lower score)
- Whether it's a weekday or weekend
- Coordinate-based population density approximation

**How safety integrates with the experience:**
- Safety level is injected into the system prompt ("SAFETY LEVEL: moderate — isolated area, stay aware")
- If the user enters a `caution` or `danger` zone, a banner appears at the top of the home screen
- The `SafetyOverlaySheet` shows specific alerts (e.g., "High bag-snatching incidents reported in this area")
- The AI can call `check_safety_score` to assess any coordinate the user asks about

**SOS System:**
Triple-tapping the orb triggers a 3-second countdown. If not cancelled, RAAH:
1. Sends an SMS to the stored emergency contact with current GPS coordinates
2. The `AnalyticsLogger` records the event
3. The AI announces the SOS in voice

**Walk Me Home:**
Activated by voice command ("walk me home safely"). RAAH continuously monitors if the user is moving toward their registered home location, sends periodic location pings to the emergency contact, and cancels when the user arrives home.

---

## 12. Snap & Ask — Vision Feature

**What it is:** Point the iPhone camera at anything — a restaurant menu in another language, a historical plaque, an architectural detail — and ask the AI about it.

**How it works:**
1. `SnapAndAskView` captures a photo using `AVCaptureSession`
2. Image is JPEG-compressed and base64-encoded
3. Sent to `OpenAIVisionService` which calls `gpt-4o-mini` with vision capabilities
4. The response is injected into the active voice conversation as context: "The user just took a photo of: [description]"
5. User can then ask follow-up questions verbally

**Why GPT-4o-mini for vision:**
`gpt-4o-mini` with vision is the most cost-efficient vision model from OpenAI. For a travel companion use case (identifying signs, menus, buildings), it has sufficient capability. `gpt-4o` would be more accurate but 10x the cost per image.

---

## 13. Apple Music Integration

**Framework used:** MusicKit (Apple's first-party framework for Apple Music)

**How it works:**
1. User grants Apple Music permission in Settings
2. `MusicService` maintains authorization state
3. AI tool `set_music_vibe(vibe_name)` receives a natural language description ("chill", "upbeat", "jazz", "bollywood")
4. MusicKit's recommendation API finds a playlist matching the description
5. Playback starts through the system music player

**Why not Spotify:** Spotify's iOS SDK requires a third-party library (violates RAAH's zero-dependency rule) and uses OAuth, which requires a webview-based auth flow — adding friction and a dependency on Spotify's app being installed.

**Why not custom audio player:** Apple Music's 100M+ track catalog and algorithmic playlists would require replication. MusicKit gives access to all of this for free with a single API.

---

## 14. Calendar Awareness

**Framework used:** EventKit

**What it does:** With permission, RAAH reads today's calendar events (title + time only — no sensitive data). These are injected into the system prompt as a "TODAY" block:
```
TODAY'S SCHEDULE:
- 2:00 PM: Lunch with Priya
- 6:00 PM: Flight to Bangalore
```

The AI uses this to avoid suggesting activities that conflict with the schedule ("you have a flight at 6 PM, so we have about 3 hours — I'd skip anything more than 20 min away").

**Why local only (no server sync):** Calendar data is personal and sensitive. It never leaves the device — it's only ever included in the system prompt payload sent to OpenAI, which is governed by their API data terms (not stored for training).

---

## 15. Health & Heart Rate

**Framework used:** HealthKit

**What it does:** `HealthKitManager` uses `HKAnchoredObjectQuery` to stream live heart rate data from an Apple Watch or paired health device. The current heart rate (in BPM) is passed to the Orb animations.

**How the orb uses heart rate:**
The Earth orb breathes (scales in/out) at a rate tied to the user's heart rate:
```swift
breatheInterval = 60.0 / heartRate  // seconds per beat
// Resting (70 BPM) = 0.86s per breath
// Active (120 BPM) = 0.5s per breath — faster, more energetic
```

This makes the orb feel biologically connected to the user — a subtle but distinctive design detail.

---

## 16. Affiliate & Ticket Discovery

### AffiliateService (GetYourGuide)

**What it is:** GetYourGuide is a global marketplace for tours, experiences, and skip-the-line tickets to major attractions. RAAH integrates their partner API to surface ticket offers when the user is near a museum or landmark.

**How it works:**
1. After each context refresh, RAAH checks the top 2 museums/monuments in the POI list
2. `AffiliateService.searchOffers()` queries the GetYourGuide API for tours near each
3. Matching offers (price, skip-the-line availability, rating) are stored in `SpatialContext.nearbyOffers`
4. The AI prompt includes `SKIP-THE-LINE TICKETS` section when offers exist
5. When the user asks about visiting, the AI mentions the ticket option and price

**Purchase intent detection:**
`AffiliateService.detectsPurchaseIntent(in:)` scans the user's message for phrases like "how much", "can I book", "ticket", "entrance fee", "reserve". When detected, the AI proactively offers the affiliate ticket even if not explicitly asked.

**Revenue model:** GetYourGuide pays a commission (typically 8-12%) on bookings referred through partner apps.

---

## 17. India-Specific Layer

### MapplsService (Mappls / MapMyIndia)

India's largest digital maps company, now the official partner of the Indian government's NAVIC satellite navigation system.

**What RAAH uses it for:**
- **DigiPin:** India's national addressing system — every 4m×4m area in India has a unique alphanumeric code. RAAH fetches the user's DigiPin for hyper-precise location sharing (useful for SOS: "Send help to DigiPin XY7-MK9-QR2")
- **Road alerts:** Real-time alerts about road blocks, construction, flooding, and traffic incidents near the user's coordinates

**Why Mappls specifically for India:**
- Google Maps has gaps in rural India and incorrect road data in many Tier 2/3 cities
- Mappls has the most accurate street-level data in India, built over 25 years of ground surveys
- DigiPin is an official Indian government initiative — having it in the app demonstrates India-market seriousness to investors

---

## 18. Design System

RAAH uses a custom design system (`RAAHTheme`) that enforces consistency across the entire app. No raw numbers are ever used in layout code.

### Design Tokens

**Spacing (8-point grid):**
```
xxxs: 2px    xxs: 4px    xs: 8px    sm: 12px
md: 16px    lg: 24px    xl: 32px    xxl: 48px    xxxl: 64px
```

**Corner Radii:**
```
sm: 12    md: 16    lg: 24    xl: 32    pill: 100
```

**Typography:** 9 semantic text styles (largeTitle, title, title2, headline, subheadline, body, callout, footnote, caption) each with weight variants (.regular, .medium, .semibold, .bold). Uses system font (San Francisco) with `.rounded` design for approachability.

**Motion:**
```
snappy: spring(response: 0.35, damping: 0.8)   ← UI interactions
smooth: spring(response: 0.60, damping: 0.82)  ← page transitions
gentle: spring(response: 0.80, damping: 0.78)  ← background elements
breathe: easeInOut(3.0s)                        ← orb idle state
pulse: easeInOut(1.0s)                          ← status indicators
```

**Accent Color (Grayscale Palette):**
Since the Earth orb is the visual centerpiece, the UI accent uses a clean grayscale palette: White, Silver (0.78), Stone (0.55), Slate (0.36), Charcoal (0.20). These accent the glass components without competing with the orb.

### Glass Design Language

All UI components use `ultraThinMaterial` — iOS's system frosted glass effect. `GlassCard`, `GlassIconButton`, `GlassPillButton`, `GlassToggleRow`, `GlassNavRow` are RAAH's component library, all built on Apple's native material system.

**Why frosted glass:**
- Dark mode native: `.ultraThinMaterial` automatically adjusts opacity and blur intensity based on the content beneath
- No fixed colors needed — works over the black home screen, over maps, over camera feeds
- Matches iOS system aesthetic, making the app feel "at home" on iPhone

### The Earth Orb

The central UI element — a procedurally animated orb that resembles Earth.

**Visual layers (all rendered in SwiftUI):**
1. Atmospheric corona: two blurred circles (outer 1.85x size, inner 1.3x), color reactive to voice state
2. Ocean base: `RadialGradient` from `midOcean` (#0D2E70) to `deepOcean` (#0819FF) to near-black
3. Rotating continent layer (24-second rotation): 3 large `RadialGradient` blobs with 13-20px blur
   - Old World (Africa + Eurasia): 68% sphere size, blur 20px
   - Americas: 48% sphere size, blur 16px
   - Pacific/SE Asia: 34% sphere size, blur 13px
4. Ice caps: top and bottom `RadialGradient` white blobs, blur 14-16px
5. Specular highlight: white radial gradient, top-left, fixed (non-rotating light source)
6. Atmosphere rim: `strokeBorder` with blue gradient, 2px blur
7. Speaking ring: expanding blue ring when AI is talking

**Color reactions:**
- Idle: soft blue atmosphere glow
- Listening: green glow (life, acknowledgment)
- Thinking: blue-white glow
- Speaking: bright atmosphere glow + expanding ring

---

## 19. Data Persistence & Storage

RAAH uses three persistence layers:

### UserDefaults (Primary Local Storage)
All user preferences are stored in `UserDefaults` under profile-scoped keys:
```
raah_{profileId8chars}_user_name
raah_{profileId8chars}_accent_theme
raah_{profileId8chars}_dietary_restrictions
raah_{profileId8chars}_budget_preference
... etc.
```

**Why profile scoping:** RAAH supports multiple user profiles (family members sharing a device). Each profile's preferences are isolated under a unique prefix derived from a UUID.

### Documents Directory (JSON Files)
- `exploration_logs.json`: Complete history of all exploration sessions (date, duration, location, POIs visited, interaction count)
- Loaded on app start, written on session end

### Supabase (Cloud Persistence)
- Long-term learned preferences stored as text + vector embeddings
- Enables cross-device sync (user upgrades phone — preferences migrate)
- pgvector enables semantic similarity search for preference retrieval

### SpatialCache (In-Memory)
- L1 cache keyed by coordinate
- Prevents redundant API calls within TTL windows
- Hit rate tracked and logged for performance monitoring

---

## 20. Analytics & Usage Tracking

### AnalyticsLogger

RAAH uses local-first analytics — all events are stored on-device and only aggregated for reporting. No third-party analytics SDK (no Firebase, no Mixpanel, no Amplitude).

**Tracked events:**
`sessionStart`, `sessionEnd`, `poiViewed`, `snapUsed`, `proactiveNarration`, `feedbackGiven`, `walkMeHomeActivated`, `sosTriggered`, `paywallShown`, `directionRequested`, and more.

**Why local-first:**
- Privacy: no user data leaves the device to a third-party analytics server
- GDPR/PDPA compliance: no consent banner needed
- Offline: works without internet

**Computed stats:** Sessions this week, total POIs discovered, total minutes explored, average session duration, most viewed POI type. These power the "YOUR STATS" section in Settings.

### UsageTracker

Enforces free tier limits:
- 30 minutes of voice per day
- 5 Snap & Ask uses per day

Currently `isProUser = true` (bypassed for MVP/pilot). Will be tied to StoreKit subscription in production.

---

## 21. Lock Screen Widget

RAAH includes a WidgetKit lock screen widget (`RAHHWidgetExtension`).

**What it shows:** A small circular orb (matching the main app aesthetic) with an orange radial gradient.

**What tapping it does:** Opens a deeplink `raah://start` which launches the main app and immediately starts the voice session (`pendingVoiceStart = true`). This is the "Action Button" use case — assign this widget to the iPhone's Action Button for one-press voice assistant launch from anywhere, including lock screen.

**AppIntent integration:** RAAH also supports iOS App Intents, enabling Siri voice activation: "Hey Siri, start RAAH" triggers the same `raah_auto_start_voice` UserDefaults flag.

---

## 22. Permissions & Privacy

| Permission | Framework | Why Needed | When Requested |
|-----------|-----------|-----------|----------------|
| Location (When in Use) | CoreLocation | POI context, navigation, safety | Onboarding page 4 |
| Location (Always) | CoreLocation | Background safety monitoring | Optional, after first use |
| Microphone | AVFoundation | Voice conversation | Onboarding page 4 |
| Camera | AVFoundation | Snap & Ask feature | When first using camera |
| HealthKit (Heart Rate Read) | HealthKit | Orb breathing animation | Settings toggle |
| Calendar (Full Access) | EventKit | Schedule-aware suggestions | Settings toggle |
| Apple Music | MusicKit | Voice-controlled music playback | Settings toggle |

**Privacy by design:**
- Location data never leaves the device except as coordinates in API requests (Open-Meteo, Google Places, Overpass, OSRM)
- Voice audio is streamed directly to OpenAI via encrypted WebSocket — RAAH never stores audio
- Calendar data is only included in system prompts (event titles + times) — never stored on servers
- Heart rate data is never transmitted anywhere — used only for animation locally

---

## 23. Dependency Philosophy — Zero Third-Party Libraries

RAAH has **zero external Swift Package Manager dependencies, zero CocoaPods, zero Carthage frameworks.**

Every capability is built using Apple's native frameworks. This is a deliberate architectural choice.

**Why zero dependencies:**

1. **Security:** Every third-party library is a potential supply chain attack vector. The XZ Utils incident (2024) showed even well-maintained open-source packages can be compromised. With zero dependencies, RAAH's security surface is limited to Apple's frameworks and RAAH's own code.

2. **App Store review predictability:** Third-party libraries occasionally trigger App Store rejections (private API usage, outdated entitlements, deprecated code). Zero dependencies means zero library-related rejections.

3. **Long-term maintainability:** Libraries break with major iOS/Swift updates. Every September when iOS updates, RAAH needs zero library updates — it just works.

4. **Bundle size:** No third-party code = smaller app download. RAAH is under 15MB without any assets.

5. **Performance:** Native frameworks (AVAudioEngine, CoreLocation, MapKit) have direct hardware access. Third-party wrappers add abstraction layers and overhead.

**What Apple's native frameworks handle that others use libraries for:**

| Common Library Use Case | RAAH's Native Solution |
|------------------------|----------------------|
| Networking (Alamofire) | URLSession async/await |
| Image loading (Kingfisher) | Not needed (no remote images) |
| JSON parsing (SwiftyJSON) | JSONSerialization manual parsing |
| Maps (Google Maps SDK) | MapKit |
| Analytics (Firebase) | AnalyticsLogger (local-first) |
| Crash reporting (Crashlytics) | Not integrated (dev build) |
| In-app purchases (RevenueCat) | StoreKit (native) |
| Push notifications (OneSignal) | Not integrated |
| Database (Realm) | UserDefaults + JSON files |

---

## 24. Complete API Surface

| API | Provider | Authentication | Cost Model | What RAAH Uses It For |
|-----|----------|---------------|-----------|----------------------|
| Realtime API (`gpt-4o-mini-realtime-preview`) | OpenAI | API Key | ~$0.04/min audio input + output | Voice conversation engine |
| Vision API (`gpt-4o-mini`) | OpenAI | API Key | ~$0.0001/image | Snap & Ask feature |
| Preference extraction (`gpt-4o-mini`) | OpenAI | API Key | ~$0.0003/extraction | Long-term memory learning |
| Places (Nearby Search) | Google | API Key | $17/1000 calls | Nearby POI discovery |
| Places (Text Search) | Google | API Key | $17/1000 calls | search_nearby AI tool |
| Overpass API | OpenStreetMap | None | Free | Hyperlocal POI data |
| Forecast API | Open-Meteo | None | Free | Current weather + 7-day forecast |
| Timezone API | Open-Meteo | None | Free | Local time computation |
| Routing API | OSRM | None | Free (public instance) | Turn-by-turn walking directions |
| Wikipedia REST API | Wikimedia | None | Free | POI editorial descriptions |
| Wikivoyage REST API | Wikimedia | None | Free | Travel-specific descriptions |
| Wikidata Entity API | Wikimedia | None | Free | POI wikidata → Wikipedia resolution |
| Safety Score API | GeoSure | API Key | Commercial | Area safety scoring |
| DigiPin + Road Alerts | Mappls | API Key + OAuth | Commercial (India) | India precision addressing |
| Tours & Tickets API | GetYourGuide | Partner ID | Commission (8-12%) | Skip-the-line ticket offers |
| Database + Vector Search | Supabase | API Key | Freemium | Long-term preference storage |
| Search (fallback) | Brave Search | API Key | $3/1000 calls | Web search fallback |

**Total required for core functionality:** Only OpenAI API key. All other APIs either have free tiers, are open-source, or are optional feature enhancements.

---

## 25. What Was Rejected and Why

### Voice: Why Not Whisper → GPT-4 → TTS Pipeline?

The "old way" of building voice assistants was:
1. Record audio → Whisper (speech-to-text) — HTTP request, ~400ms
2. Whisper text → GPT-4 (generate response) — HTTP request, ~800ms to first token
3. GPT-4 text → TTS (text-to-speech) → stream audio — HTTP request, ~300ms buffer

Total: **~1.5-2.5 seconds** before the user hears the first word of a response. In a voice conversation, this feels like a pregnant pause. Conversations feel stilted.

The Realtime API handles all three steps in one persistent WebSocket, achieving **~400ms** end-to-end. This is the difference between a tool and a companion.

### Maps: Why Not Google Maps iOS SDK?

- Requires a third-party CocoaPods/SPM dependency (violates zero-dependency rule)
- Google Maps SDK adds ~15MB to the binary
- MapKit is native, free, has full integration with CoreLocation, and renders Apple Maps which users are familiar with
- MapKit custom annotations are equally capable for RAAH's use case (colored dots with POI icons)

### Database: Why Not Core Data or Realm?

- **Core Data:** Complex setup, requires data model files, significant boilerplate. For RAAH's data (preferences, logs), it's massive overkill.
- **Realm:** Third-party dependency. Adds binary size. RAAH's data volume (hundreds of preferences, dozens of logs) is easily handled by JSON in Documents + UserDefaults.
- **SQLite:** Would require either a third-party wrapper (FMDB, GRDB) or raw C API calls. JSON is sufficient and simpler.

### Analytics: Why Not Firebase / Mixpanel?

- Firebase adds ~4MB to binary, requires Google services plist, tracks data to Google's servers
- Mixpanel / Amplitude send user data to US servers — potential GDPR/PDPA compliance issues
- For a v1 product focused on proving the voice UX, local-first analytics provides all needed metrics (session counts, feature usage) without compliance burden

### Routing: Why Not Google Directions API?

- $5 per 1,000 requests vs OSRM's $0
- Google requires the Maps SDK to display the route (their terms of service)
- OSRM is open-source, pedestrian-optimized, and runs at comparable accuracy for walking routes in urban areas

### State Management: Why Not Redux / TCA (The Composable Architecture)?

- **Redux (via swift-composable-architecture):** Powerful but heavyweight. Requires a third-party dependency (violates zero-dependency rule). Adds significant boilerplate for a single-developer project.
- **The Composable Architecture:** Similarly heavyweight, learning curve, dependency.
- **ObservableObject + @Published (pre-iOS 17):** Works but causes over-rendering. The entire view tree subscribes to `AppState`, and any property change re-renders every subscriber.
- **@Observable (iOS 17):** Granular observation built into the language. No library needed. Views only re-render when properties they actually read change. Perfect for RAAH's architecture.

---

## 26. Performance Architecture

### Audio Latency Budget

The target for voice interaction is < 500ms perceived latency. Here's how RAAH achieves it:

```
User stops speaking
    ↓ ~0ms — Silence detected by server VAD
    ↓ ~200ms — Whisper transcribes audio (server-side)
    ↓ ~150ms — GPT-4o-mini generates first token (server-side)
    ↓ ~50ms — First audio chunk streamed back via WebSocket
    ↓ ~0ms — AVAudioPCMBuffer assembled and queued for playback
Total: ~400ms to first audio output
```

### Cache-First Context

Every API call has a cache TTL. On a typical 1-hour walk:
- POIs: fetched 3-4 times (every 100m movement)
- Weather: fetched once (30 min TTL)
- Geocode: fetched once (24 hour TTL)
- Wikipedia: rarely re-fetched (7 day TTL)

Cache hit rates of 60-80% are typical, reducing API costs and improving response time to under 100ms for cached data.

### Parallel Async Fetching

`async let` in Swift allows true parallel execution of independent async operations. The 7-service context fetch completes in the time of the slowest single call (~800ms) rather than the sum of all calls (~4 seconds sequential).

### Background Task Isolation

Wikipedia enrichment runs in a detached `Task` after context is already pushed to the AI. This means the AI gets context immediately, and Wikipedia data silently enriches the prompt 1-3 seconds later. The user never waits for Wikipedia.

---

## 27. Monetization Architecture

### Freemium Model

| Feature | Free | Pro |
|---------|------|-----|
| Voice conversations | 30 min/day | Unlimited |
| Snap & Ask | 5/day | Unlimited |
| Long-term memory sync | Local only | Cloud (Supabase) |
| Multiple profiles | 1 | Unlimited |
| Exploration journal | Last 10 sessions | All time |

### Revenue Streams

1. **Pro Subscription:** In-app purchase via StoreKit. Monthly/annual pricing.
2. **Affiliate Commissions:** GetYourGuide tickets (8-12% per booking). Viator (secondary). Average booking $40-80 → $3-10 per conversion.
3. **Future:** Premium city guides (curated POI packs), enterprise API for hotels/tour operators.

---

## 28. Full Technology Comparison Table

| Category | RAAH Uses | Alternative A | Alternative B | Why RAAH's Choice Wins |
|---------|-----------|--------------|--------------|----------------------|
| **Language** | Swift 5.9 | React Native | Flutter | Native audio pipeline, no abstraction overhead |
| **UI Framework** | SwiftUI | UIKit | React Native | Declarative, physics animations, material system |
| **State Management** | @Observable (iOS 17) | ObservableObject | The Composable Architecture | Zero library, granular re-rendering |
| **Voice API** | OpenAI Realtime API | Whisper+GPT+TTS | ElevenLabs Conversational | 400ms vs 2s latency, tool calls, single connection |
| **POI Data (Commercial)** | Google Places (New) | Foursquare Places | HERE Places | Best coverage, real open/close status, editorial summaries |
| **POI Data (Open)** | OpenStreetMap/Overpass | Foursquare (freemium) | TomTom | Free, hyperlocal, heritage/architectural coverage |
| **Weather** | Open-Meteo | OpenWeatherMap | WeatherKit | Free, no API key, ECMWF accuracy |
| **Routing** | OSRM | Google Directions | Mapbox Directions | Free, pedestrian-optimized, open-source |
| **Maps Display** | MapKit | Google Maps iOS SDK | Mapbox SDK | Native, zero dependency, free |
| **Safety** | GeoSure API | Manual heuristics | Safer (startup) | Global coverage, granular dimensions |
| **POI Descriptions** | Wikipedia/Wikivoyage | Google POI descriptions | Custom editorial | Free, multilingual, structured summaries |
| **India Maps** | Mappls/MapMyIndia | Google Maps (India) | OpenStreetMap alone | Best India street data, DigiPin, government partnership |
| **Cloud DB** | Supabase (PostgreSQL + pgvector) | Firebase Firestore | AWS DynamoDB | Vector search for semantic memory, open-source PostgreSQL |
| **Local DB** | UserDefaults + JSON | Core Data | Realm | Zero setup, sufficient for data volume, no library |
| **Analytics** | Local-first custom | Firebase Analytics | Mixpanel | No third-party data transmission, privacy-native |
| **Music** | MusicKit | Spotify iOS SDK | AVPlayer (custom) | 100M+ tracks, no third-party library, deep Siri integration |
| **Calendar** | EventKit | Google Calendar API | CalDAV | Native on-device, no server sync needed |
| **Health** | HealthKit | Fitbit SDK | Manual BPM input | Native Apple Watch integration, always available |
| **Tickets** | GetYourGuide API | Viator API | Klook API | Broadest global inventory, established partner program |
| **IAP** | StoreKit | RevenueCat | Qonversion | Native, zero dependency, direct Apple integration |
| **In-App Purchases** | StoreKit | RevenueCat | Superwall | Native, no 1% revenue cut to third party |

---

*This report covers RAAH as of March 2026. Build version 1.0, targeting iOS 17+.*

*Total lines of Swift code: ~12,000. Total dependencies: 0. Total Apple frameworks used: 16.*

---

**Frameworks used:**
`SwiftUI` · `Combine` · `AVFoundation` · `AVAudioEngine` · `CoreLocation` · `MapKit` · `HealthKit` · `EventKit` · `MusicKit` · `StoreKit` · `WidgetKit` · `AppIntents` · `Foundation` · `UIKit` (minimal) · `CoreMotion` (heading) · `Network`
