# Baby Tracker App — Requirements & Decisions

> **Status:** In Progress
> **Last Updated:** June 2026
> **App Name:** TBD (placeholder: `baby_tracker`) — see naming decisions below

---

## 1. Product Overview

A mobile baby/child tracking app inspired by competitor, helping parents and caregivers log and monitor a baby's daily activities with smart sleep prediction and AI-powered guidance.

---

## 2. Target Platforms

| Platform | Support | Notes |
|---|---|---|
| iOS | ✅ Required | iPhone + iPad |
| Android | ✅ Required | OS 9.0+ |
| Apple Watch | 🔜 Future | Native Swift required — not in MVP |
| Web | 🔜 Future | Possible via Flutter Web |

---

## 3. Core Features

### MVP v1 (Launch Minimum)
**Goal:** Focus on core tracking.

**In v1:**
- Sleep (timer + manual entry, history view)
- Feeding (timer + manual entry for bottle/breastfeeding, no side tracking)
- Diaper changes (quick-tap log)
- Single child profile
- Multi-caregiver invite/sync (basic, realtime)
- Manual activity reminders
- Simple sleep summaries and history

**Out of v1:**
- Growth tracking
- Medicine/temperature logging
- Potty training
- Sleep prediction/insights
- AI features

### v1.1
- Growth tracking (weight, length)
- Medicine & temperature logging
- Multiple child profiles
- Smart reminder scheduling (recommended feeding times)

### v1.2
- Sleep prediction (heuristic-based, age rules)
- Enhanced trend reports and charts
- Age-appropriate sleep schedule suggestions

### v2
- AI chat with expert guidance
- Custom sleep plans with progress tracking
- AI logging (text, voice, photo parsing)
- Advanced data-driven insights

### Full Feature Set
- One-touch tracking for:
  - Sleep (start/stop timer, manual entry, history)
  - Feeding (timer + manual, bottle/breastfeeding)
  - Diaper changes
  - Growth (weight, height)
  - Medicine & temperature
  - Activities & notes
  - Potty training
- Sleep summaries, history, and prediction
- Multiple child profiles
- Smart reminder scheduling
- Multi-caregiver sync across devices
- Unlimited data history
- Charts, trends, and insights
- AI-powered guidance (v2+)

---


## 5. Technical Decisions

### 5.1 Mobile Framework
**Decision: Flutter**

Rationale:
- Single codebase for iOS and Android
- Near-native performance (own rendering engine via Skia/Impeller)
- Excellent UI consistency across platforms — critical for sleep-deprived parents using one hand at 3am
- Strong animation support for timers and charts
- Official `supabase_flutter` package available

### 5.2 Backend
**Decision: Supabase (local-first, cloud when ready)**

Rationale:
- Open source (MIT license) — no vendor lock-in
- Built on PostgreSQL — industry standard, fully portable
- Self-hostable if needed
- Official Flutter SDK (`supabase_flutter`)
- Generous free tier (2 projects, 500MB DB, 50k users)
- Simple, predictable pricing vs AWS complexity

Supabase components used:
| Component | Purpose |
|---|---|
| PostgreSQL | All tracking data, child profiles, user accounts |
| Auth | Login, social auth, session management |
| Realtime | Multi-caregiver sync across devices |
| Storage | Profile photos, voice memos, AI logging images |
| Edge Functions | AI/LLM API calls, sleep prediction logic |

### 5.3 Authentication
**Decision: Supabase Auth with social login**

Providers:
- Sign in with Apple (**mandatory** for iOS App Store if any social login offered)
- Sign in with Google (most used)
- Email/Password (fallback)

**Multi-Caregiver Model:**
- Primary caregiver creates account + baby profile
- Primary can invite secondary caregivers via email/link
- Secondary caregivers create their own account, then join baby's profile
- All caregivers see same data in real-time (Supabase Realtime)
- **Permissions:** All caregivers have read+write access to all tracking data (v1); role-based access (admin/viewer) in v2

---

### 5.4 Multi-Caregiver Sync & Conflict Resolution

**Architecture:**
- Each caregiver has a device with local cache (Hive/Isar)
- All writes go to Supabase first (cloud source of truth)
- Reads are served from local cache, then synced via Realtime
- No device-to-device syncing; everything flows through Supabase

**Conflict Resolution Strategy: Last-Write-Wins (LWW)**

Example: Both parents log sleep at the same time (3:00pm and 3:01pm)

```
Mom's phone:  "Sleep: 2:00pm–3:30pm" (logged at 3:00pm, server_timestamp=3:00pm)
Dad's phone:  "Sleep: 2:00pm–3:25pm" (logged at 3:01pm, server_timestamp=3:01pm)

Database keeps both initially (insert succeeds on both)
App logic: Show the later timestamp entry, or both with timestamps + merge hint
  → "Two sleep logs: 3:30pm and 3:25pm. Both logged."
```

**Recommended approach for v1:**
- Allow duplicate logs but surface them to parent with timestamps
- Show: "Hey, we see 2 sleep entries for this time. Tap to merge or delete."
- Simple UI: "Which one is accurate?" → delete the other
- No automatic merging in v1; explicit user choice

**For v2:**
- Implement server-side merge conflict detection
- Auto-merge if both entries are within 5 minutes + overlap by 80%+
- Otherwise prompt user for merge

---

### 5.5 State Management

**Decision: Riverpod**

**Rationale:**
- Compile-time safety (code-generated providers) vs Provider's runtime issues
- Better testability (providers are injectable)
- Cleaner separation between local state (UI) and server state (Supabase)
- Strong community adoption in Flutter ecosystem
- Works well with async operations (`.future`, `.stream` variants)

**Architecture:**

```
Riverpod State Layers:
├── App State (auth user, selected child profile)
├── Server State (sleep logs, feeding logs from Supabase)
│   └── Each entity has a notifier: SleepLogsNotifier, FeedingLogsNotifier
│   └── Queries + mutations (create, update, delete)
├── UI State (expanded sections, form inputs, loading spinner state)
│   └── Simple StateNotifiers for UI-only state
└── Local Cache State (Hive/Isar)
    └── Synced with server state via `.future` providers
```

**Implementation Outline:**

```dart
// Server state provider
final sleepLogsProvider = StateNotifierProvider<SleepLogsNotifier, AsyncValue<List<SleepLog>>>((ref) {
  return SleepLogsNotifier(ref.watch(supabaseProvider));
});

// UI state provider
final sleepFormStateProvider = StateNotifierProvider<SleepFormNotifier, SleepFormState>((ref) {
  return SleepFormNotifier();
});

// Watch both in widget
@override
Widget build(BuildContext context, WidgetRef ref) {
  final sleepLogs = ref.watch(sleepLogsProvider);  // AsyncValue<List>
  final formState = ref.watch(sleepFormStateProvider);

  return sleepLogs.when(
    loading: () => LoadingSpinner(),
    error: (err, st) => ErrorWidget(),
    data: (logs) => SleepHistoryList(logs: logs),
  );
}
```

---

### 5.6 Offline-First Strategy

**Goal:** App remains fully functional without internet. Syncs when connection returns.

**Architecture:**

```
┌─────────────────────────────────────────────────────────┐
│ Riverpod State (in memory)                              │
├─────────────────────────────────────────────────────────┤
│ ↓ read/write (optimistic)                               │
├─────────────────────────────────────────────────────────┤
│ Hive/Isar Local Cache (on disk)                         │
├─────────────────────────────────────────────────────────┤
│ ↓ sync when online (background)                         │
├─────────────────────────────────────────────────────────┤
│ Supabase (cloud source of truth)                        │
└─────────────────────────────────────────────────────────┘
```

**Write Flow (Offline-Optimistic):**

1. User logs "Sleep: 2:00pm–3:00pm"
2. App writes to Hive immediately (instant UI update)
3. Assign temporary ID (e.g., `temp-uuid-123`)
4. Show checkmark (not synced yet)
5. App attempts Supabase insert in background
6. On success: replace `temp-uuid-123` with real DB ID
7. On failure: show "Offline" badge + retry button

**Read Flow:**

1. App loads cached logs from Hive on startup (instant)
2. In background, fetch from Supabase + compare
3. If new logs exist on server → merge into local cache
4. If conflict detected → show merge UI

**Sync Strategy:**

- **Optimistic:** Assume success, revert on failure (used for most operations)
- **Pessimistic:** Wait for server confirmation before updating UI (used for deletions, sensitive updates)

**Implementation Tools:**

| Component | Purpose |
|---|---|
| `hive` or `isar` | Local key-value + relational cache |
| `connectivity_plus` | Detect when online/offline |
| `flutter_background_service` | Background sync daemon (wake every 5 min if offline) |
| `uuid` | Generate temp IDs for offline-created logs |

**Offline Sync Job (runs when online or every 5 min if offline):**

```
1. Check device connectivity
2. If offline: queue and exit
3. If online:
   a. Get all "pending sync" entries from Hive (marked with sync_pending=true)
   b. For each: POST to Supabase
   c. If success: update ID, mark sync_pending=false
   d. If 4xx error (validation failure): show user error, mark for manual review
   e. If 5xx error (server error): keep queued, retry in 5 min
   f. Fetch latest logs from server, merge with local cache
```

**Data Freshness Guarantee:**

- **Online:** Data is always within 5 seconds of Supabase (Realtime syncs near-instantly)
- **Offline:** Data is stale; shows "Last synced: 3 hours ago"
- User can manually pull-to-refresh to force sync

---

### 5.7 Development Approach
**Decision: Local-first development, push to cloud when ready**

```
Local (Docker + Supabase CLI) → Cloud (Supabase free tier)
```

- No Supabase account needed to start
- Use `supabase start` locally
- Use `supabase db push` to sync schema to cloud when ready
- Test offline mode locally by toggling `connectivity_plus` mock

---

### 5.8 AI Features
- Sleep prediction: server-side heuristic (v1) → ML model (v2) via Edge Functions
- AI chat: LLM API calls via Edge Functions (API keys never in mobile app)
- AI logging: multimodal input (text, voice, photo) parsed server-side

---

## 6. App Naming

### Current Status
- **Display name:** TBD
- **Project folder:** `baby_tracker` (placeholder)
- **Bundle ID:** `com.yourdomain.babytracker` ⚠️ *Decide before first App Store submission*

### Naming Constraints
- "FlutterBaby" flagged — "Flutter" is a Google trademark, may cause App Store rejection
- "Flutter Care: Pregnancy" already exists on App Store
- Final name must be unique on App Store and Google Play

### Naming Evaluation Framework
Candidates evaluated on:
| Criterion | Weight | Goal |
|---|---|---|
| **Memorability** | 25% | Parents remember at recommendation; easy to spell/pronounce |
| **Differentiation** | 25% | Stands out in App Store search results |
| **Domain Alignment** | 20% | Name reflects core value (tracking, sleep, nurturing) |
| **Longevity** | 15% | Works for 0–5+ year age range (not "baby"-specific if expanding) |
| **Brand Safety** | 15% | No trademark conflicts; no negative connotations |

### Candidate Scoring

| Name | Memorable | Different | Domain | Longevity | Safe | **Score** | **Recommendation** |
|---|---|---|---|---|---|---|---|
| **TinyLog** | 8/10 | 7/10 | 9/10 | 6/10 | 9/10 | **7.8** | ✅ **RECOMMENDED** |
| **BabyNest** | 9/10 | 6/10 | 8/10 | 4/10 | 8/10 | 7.0 | Consider |
| **LittleLog** | 7/10 | 8/10 | 8/10 | 7/10 | 9/10 | 7.8 | ✅ **RECOMMENDED** |
| **NestNote** | 7/10 | 8/10 | 7/10 | 5/10 | 8/10 | 7.0 | Consider |
| **PeaPod** | 9/10 | 7/10 | 6/10 | 3/10 | 8/10 | 6.6 | Hold |
| **SproutLog** | 8/10 | 7/10 | 8/10 | 8/10 | 8/10 | 7.8 | ✅ **RECOMMENDED** |
| **BabyBloom** | 8/10 | 7/10 | 8/10 | 5/10 | 7/10 | 7.2 | Consider |
| **NapNest** | 8/10 | 6/10 | 8/10 | 4/10 | 8/10 | 6.8 | Hold |

**Top 3 Finalists:** TinyLog, LittleLog, SproutLog

### Vetting Checklist (Complete before v1 launch)
- [ ] App Store search (all top 3 names)
- [ ] Google Play search (all top 3 names)
- [ ] Domain availability (`.app`, `.io`, `.co` TLDs)
- [ ] USPTO trademark search
- [ ] International trademark conflicts (if planning EU launch)
- [ ] Social media handle availability (@tinylog, etc.)
- [ ] Trademark registration filed (after final selection)

### Final Decision Timeline
- **By end of this month:** Select final name from top 3
- **Before v1 beta:** Trademark registration filed
- **Before App Store submission:** All vetting complete, domain + socials registered

### What's Easy vs Hard to Change Later
| Item | Difficulty | Notes |
|---|---|---|
| Display name | ✅ Easy | Change anytime; no impact on app |
| App Store listing name | ✅ Easy | Edit in App Store Connect |
| Google Play listing name | ✅ Easy | Edit in Play Console |
| Bundle ID / Package name | ❌ Hard | Set once, never change after publish |
| Domain name | ⚠️ Medium | Can redirect, but branding impact |
| Logo / branding | ✅ Easy | Update via app update |

---

## 7. Open Source Reference Projects

| Project | Stack | Use |
|---|---|---|
| BabyBuddy | Python/Django | Feature reference, schema inspiration |
| SimpleBaby | React Native/Expo | Mobile app structure reference |
| simplest-baby-tracker | Vanilla JS | Minimal implementation reference |

---

## 8. Compliance & Privacy

> ⚠️ This app collects data about children under 13 in the US (and minors in EU). Compliance is mandatory before launch, not optional.

### 8.1 COPPA Compliance (US — Mandatory if available in US)

**Scope:** If available to anyone in the US, COPPA applies to data collection about children under 13.

**Our Data Collection:**
- Sleep logs, feeding logs, diaper changes, growth metrics, photos, voice memos = **personally identifiable information about children**

**Required Implementation:**

| Requirement | Implementation |
|---|---|
| **Parental Consent** | Parent/guardian provides email; verify ownership via email confirmation link before data collection begins |
| **Transparent Privacy Policy** | Plain language, not legal jargon. Explain: what data we collect, why, how long we keep it, who sees it |
| **No Contextual Ads** | No ads targeted based on child's data; no third-party tracking |
| **Limit Data Collection** | Only collect: name, DOB, photos, activity logs. No location beyond zip code. No unique device IDs. |
| **Parental Access & Control** | Parent can review all data about their child; delete data with one action |
| **Data Retention** | Auto-delete all child data 30 days after account deletion (implement reminder in code) |
| **Third-Party Processors** | Supabase, any analytics, any AI API must have Data Processing Agreements (DPAs) in place |
| **No Disclosure** | Never sell or disclose child data to third parties except as required by law |
| **Breach Notification** | If hacked, notify FTC + parents within 30 days |

**Verification Steps (pre-launch checklist):**
- [ ] Privacy Policy drafted and reviewed by privacy attorney
- [ ] Email verification flow implemented and tested
- [ ] Parental access UI built and tested
- [ ] Data deletion automation written + tested
- [ ] Supabase (and any third-party vendors) DPA signed
- [ ] No analytics, Mixpanel, Firebase, or third-party trackers in app
- [ ] Test account created with child under 13; verify all compliance features work

---

### 8.2 GDPR Compliance (EU — Optional if not targeting EU initially)

**Decision:** If targeting EU in v2+, GDPR applies to **all** users (not just under 13).

**Key GDPR Obligations:**

| Obligation | For Our App |
|---|---|
| **Lawful Basis** | Parental consent (article 8). For adults: consent to process their own data. |
| **Privacy Policy** | Must be transparent, specific about data processing. Offer policy in user's language. |
| **Data Subject Rights** | User can request: data access, correction, deletion, portability, objection to processing |
| **Data Protection Impact Assessment (DPIA)** | Required before launch. Assess risks of data processing. |
| **Data Processing Agreement (DPA)** | Supabase acts as Data Processor; we need a signed DPA with Supabase. |
| **Data Retention** | Delete data automatically after user-specified period (default: 24 months post-deletion request) |
| **Data Transfers** | If any data leaves EU (e.g., to US Supabase servers), must use Standard Contractual Clauses (SCCs). |
| **Privacy by Design** | Encryption in transit + at rest. Minimal data collection. Regular security audits. |

**MVP Decision:** Skip EU targeting for v1; add GDPR in v2 if expanding to EU.

---

### 8.3 HIPAA Compliance

**Decision:** This app does **NOT** qualify as a HIPAA-covered entity or Business Associate.

**Reasoning:**
- We are not a healthcare provider, health plan, or healthcare clearinghouse
- Activity logs (sleep, feeding, diaper) are not "protected health information" (PHI) under HIPAA
- Even though this helps parents track infant health, it's a personal diary, not a medical record

**What would trigger HIPAA:**
- Storing medical diagnoses (e.g., "baby has reflux")
- Storing prescriptions or medication dosages
- Sharing data with pediatrician's EHR
- Claiming to diagnose or treat medical conditions

**Our Approach:** Don't collect PHI. If adding medical features (e.g., medication logging), treat as regular health data, not PHI, and continue COPPA/GDPR compliance.

---

### 8.4 App Store & Google Play Privacy Labels

**iOS Privacy Label (required for App Store submission):**

Data Collected:
- [ ] Name
- [ ] Date of Birth
- [ ] Photos
- [ ] Activity Logs (sleep, feeding, diaper)
- [ ] Device ID (for multi-caregiver sync)

Tracking domains: **None** (no analytics, no ads, no behavioral tracking)

Practices:
- [ ] Data linked to user identity: **Yes** (caregiver's account)
- [ ] Data not linked to user: **No**
- [ ] Data used for tracking: **No**

**Google Play Data Safety (required for Android Play Store):**

Same as iOS + declare:
- [ ] App collects data from children under 13
- [ ] Parental consent verified (email confirmation)
- [ ] Data encrypted in transit and at rest
- [ ] No data sharing with third parties
- [ ] Users can request deletion

---

### 8.5 Privacy by Design Checklist

Before any release (v1, v1.1, etc.):

- [ ] **Encryption in Transit:** All API calls use HTTPS + TLS 1.3 minimum
- [ ] **Encryption at Rest:** Supabase has database encryption enabled; user photos encrypted in Storage
- [ ] **Minimal Collection:** Only ask for data we use. No "just in case" collection.
- [ ] **Retention Policy:** Documented and implemented. Tested with real deletion.
- [ ] **No Third-Party Trackers:** Audit dependencies for hidden analytics/tracking libraries
- [ ] **Supabase Security:** Enable RLS (Row-Level Security) on all tables; verify auth tokens expire
- [ ] **API Key Security:** Never embed API keys in app; use Supabase client library's built-in key management
- [ ] **Audit Logging:** Log sensitive actions (data deletion, shared access, etc.) server-side for compliance audit trail

---

### 8.6 Compliance Implementation Roadmap

| Phase | Deadline | Deliverable |
|---|---|---|
| **Phase 1 (v1 MVP)** | Before beta | COPPA + GDPR (if US-only: COPPA only) + Privacy Labels ready |
| **Phase 2 (v1.1)** | Week after launch | Legal review of Privacy Policy completed |
| **Phase 3 (v2)** | If EU expansion decided | Full GDPR compliance + SCCs for data transfers |

---

### 8.7 Who's Responsible

- **CEO/Product:** Decide if targeting EU in v1 or later
- **Engineering:** Implement parental consent flow, data deletion, encryption
- **Legal:** Draft Privacy Policy, COPPA checklist, sign DPAs with Supabase
- **QA:** Test all compliance features (email verification, data deletion, parental access, etc.)

---

### 8.8 Open Questions for Legal/Privacy Review

- [ ] Should we require explicit parental consent via email, or accept Apple Sign In + assume Apple verified the account owner?
- [ ] What's our data retention default? (1 year? 2 years? Until account deletion?)
- [ ] Do we need a separate "admin" account for parents managing multiple children, or is one parent account enough?
- [ ] Should we support caregivers (e.g., grandparents, nannies) without full parental consent?

---

## 9. Local Development Stack

| Tool | Purpose | Status |
|---|---|---|
| Homebrew | Mac package manager | ✅ Install |
| Git | Version control | ✅ Install |
| VS Code | Code editor + Flutter extension | ✅ Install |
| Flutter | Mobile framework | ✅ Install |
| Xcode | iOS builds + simulator | ✅ Install |
| CocoaPods | iOS dependency manager | ✅ Install |
| Android Studio | Android builds + emulator | ✅ Install |
| Node.js (via nvm) | JS runtime + tooling | ✅ Install |
| Supabase CLI | Local backend management | ✅ Install |
| Docker Desktop | Run Supabase locally | ✅ Install |
| Postman | API testing | ✅ Install |
| Claude Code | AI coding assistant (requires Pro+) | ✅ Install |

---

## 10. Key Flutter Packages (Planned)

| Package | Purpose | Justification |
|---|---|---|
| `supabase_flutter` | Backend (auth, DB, realtime, storage) | Official Supabase SDK, well-maintained |
| `riverpod` | State management | Compile-time safety, async handling, testability |
| `hive` / `isar` | Local offline storage | Fast, reliable, supports encrypted boxes |
| `connectivity_plus` | Detect online/offline status | Required for offline-first sync logic |
| `uuid` | Generate temp IDs for offline entries | Standard UUID library |
| `google_sign_in` | Google OAuth | iOS App Store requirement if offering social login |
| `sign_in_with_apple` | Apple OAuth | Required for Apple sign-in on iOS |
| `flutter_background_service` | Background sync daemon | Enables offline sync while app backgrounded |
| `workmanager` | Scheduled background tasks | iOS/Android background task scheduling |
| `fl_chart` | Charts and graphs | For trend reports and analytics |
| `firebase_messaging` | Push notifications | Medication/feeding reminders |
| `intl` | Localization & date formatting | Handle timezones, date display |
| `speech_to_text` | Local voice-to-text (v1.2+) | On-device speech recognition for voice entry, no internet required |
| `camera` | Photo capture (v2+) | For AI logging feature |
| `record` | Audio recording (v2+) | For voice memo logging |

**Excluded Packages:**
- ❌ `provider` → Using Riverpod instead (better safety)
- ❌ `firebase_analytics` → COPPA prevents analytics tracking of child data
- ❌ `sentry` → COPPA prevents error tracking that includes child data (use server-side only)
- ❌ `revenue_cat` → No monetization needed

---

## 11. Open Questions & Decisions Needed

### Product Decisions
- [ ] **App Name:** Choose from TinyLog, LittleLog, SproutLog (§6)
- [ ] **Bundle ID:** Finalize before first build (e.g., `com.tinylog.babytracker`)
- [ ] **Target Regions (v1):** US-only or include EU? (impacts GDPR scope; see §8.2)
- [ ] **Expert Partnership:** Will we partner with pediatricians for content? If so, who? When?
- [ ] **Caregiver Permissions (v2):** Should secondary caregivers have read-only or write access? (currently all have write)
- [ ] **Data Retention Default:** Auto-delete data after 1 year? 2 years? (see §8.1 & §8.2)
- [ ] **Offline Conflict Resolution:** Accept duplicates + manual merge (v1) or auto-merge on server (v2)? (§5.4)

### Technical Decisions
- [ ] **Sleep Prediction v1:** Heuristic rules (age-based) or simple ML? (§5.8)
- [ ] **Local Cache Strategy:** Use Hive (simpler) or Isar (faster, relational)? (§5.6)
- [ ] **Push Notifications:** Firebase Messaging or custom solution? (§10)
- [ ] **Voice Memo Storage:** Compress + store in Supabase Storage or send to transcription API? (v2 decision)

### Legal/Compliance
- [ ] **Parental Consent Verification:** Email confirmation only, or require Apple/Google account verification? (§8.1)
- [ ] **Privacy Policy Review:** Schedule legal review before beta (see §8.6)
- [ ] **Third-Party DPAs:** Collect DPAs from Supabase, any AI API, analytics tool before launch (§8.1)
- [ ] **Trademark Registration:** File provisional trademark after name finalized (§6)

### Research/Discovery
- [ ] **User Interviews:** Talk to 10+ parents about pain points, what they want
- [ ] **competitor Feedback Research:** Read Reddit (r/beyondthebump, r/parenting) + App Store reviews (iOS/Android) for pain points, feature gaps, complaints about pricing/UX. See `memory/project_competitive_research.md` for research checklist.
- [ ] **Competitive Analysis:** Study BabyConnect, Babysparks, Glow features + pricing (same pattern as competitor research)
- [ ] **Sleep Prediction Validation:** How accurate should our sleep window be? (±30 min? ±1 hour?)
- [ ] **AI Chat Vendors:** Compare OpenAI vs Claude vs Google Vertex AI for cost/quality/compliance

---

## 12. Development Roadmap

### Pre-v1 (Foundation) — Weeks 1–4
- [ ] Finalize app name & bundle ID
- [ ] Draft Privacy Policy (legal review pending)
- [ ] Set up Supabase locally (Docker + Supabase CLI)
- [ ] Design database schema (sleep_logs, feeding_logs, diaper_logs, user_profiles, etc.)
- [ ] Create Flutter project skeleton + Riverpod structure
- [ ] Implement Supabase Auth (Email + Google + Apple sign-in)

### v1 MVP (Core Tracking) — Weeks 5–12
- [ ] Build Sleep tracking UI (timer + manual entry)
- [ ] Build Feeding tracking UI (timer + manual entry)
- [ ] Build Diaper changes UI (quick-tap log)
- [ ] Implement single child profile
- [ ] Implement basic multi-caregiver invite/sync (no conflict resolution yet, just LWW)
- [ ] Implement Hive local caching + offline-first writes
- [ ] Implement Riverpod state management for all features
- [ ] Basic reminder functionality (manual scheduling)
- [ ] Comprehensive COPPA compliance testing (email verification, data deletion, etc.)
- [ ] Privacy label setup (iOS & Google Play)
- [ ] Beta testing with 20–30 parents

### v1 Launch — Week 13
- [ ] Internal QA final pass
- [ ] Submit to App Store + Google Play
- [ ] Prepare launch announcements
- [ ] Set up support email + feedback channel

### v1.1 (Extended Tracking & UX Improvements) — Weeks 14–16 (Post-launch)
- [ ] Growth tracking (weight, height)
- [ ] Medicine & temperature logging
- [ ] Multiple child profiles
- [ ] Smart reminder scheduling
- [ ] Enhanced activity history view
- [ ] **Improved time picker UX** (no scrolling: quick buttons for "now", "5 min ago", "15 min ago" + text input field)

### v1.2 (Analytics, Insights & Voice Entry) — Weeks 17–20
- [ ] Implement sleep prediction (heuristic-based, age rules)
- [ ] Build trend reports + charts (fl_chart)
- [ ] Sleep schedule suggestions (age-appropriate)
- [ ] Pattern detection in baby's data (early wake-ups, etc.)
- [ ] **Voice-to-text entry** (local on-device speech recognition via `speech_to_text` package; no internet required)

### v2 (AI Features & Voice Assistants) — Q1 2027
- [ ] Implement AI chat via Edge Functions (LLM API integration)
- [ ] Build custom sleep plan feature
- [ ] Implement AI logging (camera + voice input, server-side parsing)
- [ ] **Siri Shortcuts integration** (iOS) — quick entry via "Hey Siri, log baby sleep"
- [ ] **Google Assistant / Gemini integration** (Android) — similar shortcuts
- [ ] Expand to EU if GDPR compliance signed off

---

### Success Metrics (v1 Launch)
- ✅ Zero compliance violations (COPPA audit pass)
- ✅ < 2 sec app cold-start time
- ✅ 99% successful offline sync within 5 min of coming online
- ✅ 95% user retention after 1 week
- ✅ 4.5+ star rating on both app stores
