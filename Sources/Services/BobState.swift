import SwiftUI
import AppKit
import Combine

/// The app's one source of truth, refreshed from HiBob (the *real* source of
/// truth) every minute, on wake, and after every action. Decisions are
/// delegated to AttendanceLogic; this class polls, executes, and publishes.
@MainActor
final class BobState: ObservableObject {
    static let shared = BobState()

    @Published private(set) var entries: [AttendanceEntry] = []
    @Published private(set) var clockState: ClockState = .clockedOut
    @Published private(set) var signedIn = false
    @Published private(set) var accountEmail: String?
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var reasonOptions: [ReasonOption] = []
    @Published private(set) var cycle: CycleInfo?
    @Published private(set) var cycleSummary: CycleSummary?
    @Published private(set) var activity: [ActivityEvent] = []
    @Published private(set) var timeOffBalances: [TimeOffBalance] = []
    @Published private(set) var timeOffRequests: [TimeOffRequest] = []
    @Published private(set) var timeOffPolicyTypes: [TimeOffPolicyType] = []
    @Published private(set) var cancellingRequests: Set<String> = []
    @Published private(set) var monthDays: [DayEntries] = []
    /// The employee's display name / role / site for the dashboard header.
    @Published private(set) var profile: (name: String, role: String, site: String)?

    private let client = BobClient()
    private var employeeID: String?
    private var pollTimer: Timer?
    private var eventTimer: Timer?
    private var queueTimer: Timer?

    /// HiBob rejects two punches less than a minute apart. We enforce the same
    /// gap client-side: punches sit in `queue` and fire one minute apart. The
    /// user can queue several ahead of time and remove any before it fires.
    static let punchCooldown: TimeInterval = 60
    @Published private(set) var queue: [QueuedPunch] = []
    /// A punch whose optimistic state we're holding until the server reflects it.
    private var expectedAfterPunch: PunchAction?
    /// Server-ids of entries currently being deleted (drives a per-row spinner).
    @Published private(set) var deletingEntries: Set<String> = []
    /// False until the first reconcile after signing in has fully settled, so
    /// the UI can show a loading placeholder instead of a half-loaded day.
    @Published private(set) var ready = false
    /// True while a headless auto re-login is running (drives its loading state).
    @Published private(set) var autoLoginInProgress = false
    /// A user-friendly line describing the current auto sign-in step.
    @Published var autoLoginStatus = ""
    private var lastPunchAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "lastPunchAt")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "lastPunchAt") }
    }

    /// Set only when *this app* started the currently-open break — a manual
    /// break stays nil and is never auto-ended. Persisted so a relaunch
    /// mid-auto-break still ends it on schedule.
    private var autoBreakStartedAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "autoBreakStartedAt")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0,
                                      forKey: "autoBreakStartedAt")
        }
    }

    /// Backoff so a broken write doesn't get hammered every poll: the same
    /// action is retried at most once per 15 minutes.
    private var lastActionKey: String?
    private var lastActionAt: Date?

    /// "Now" for engine decisions. The system clock — HiBob's
    /// `currentLocalTime` turned out to be UTC-labelled and unreliable, while
    /// entry times parse to correct absolute instants via the employee tz.
    private var now: Date { Date() }

    // MARK: - Lifecycle

    func start() {
        Notifier.requestAuthorization()
        // Reading the Wi-Fi SSID needs Location authorization on modern macOS.
        if Prefs.shared.wifiAutoReasonEnabled { WiFiMonitor.shared.requestAccess() }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.reconcile() }
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.reconcile() }
        }

        if usedSSO {
            Task { await connect() }
        }
    }

    /// True once the user has signed in through the embedded browser; the app
    /// then relies on the captured session cookies (the tenant uses Okta, so
    /// there is no password to re-login with).
    var usedSSO: Bool { UserDefaults.standard.bool(forKey: "signedInViaSSO") }

    // MARK: - Account

    /// SSO sign-in: open the embedded browser; on success adopt the session.
    func startSSOSignIn() {
        SSOSignInController.shared.present { [weak self] in
            Task { await self?.completeSSOSignIn() }
        }
    }

    /// True when a headless re-login is possible (autofill on + a password saved).
    var canAutoSignIn: Bool { Prefs.shared.autofillEnabled && Keychain.has(.password) }

    /// Headless re-login using the stored credentials; drives a loading state.
    func startAutoSignIn() {
        guard canAutoSignIn, !autoLoginInProgress else { return }
        autoLoginInProgress = true
        autoLoginStatus = "Opening HiBob…"
        lastError = nil
        SSOSignInController.shared.presentHeadless { [weak self] success in
            guard let self else { return }
            self.autoLoginInProgress = false
            self.autoLoginStatus = ""
            if success {
                Task { await self.completeSSOSignIn() }
            } else {
                self.lastError = "Automatic sign-in didn't complete — try signing in manually."
                Notifier.failure("Automatic sign-in didn't complete.")
            }
        }
    }

    /// First-run onboarding: save the auto-login credentials, turn on autofill +
    /// auto-relogin, and kick off a headless sign-in straight away.
    func setupAutoLogin(email: String, password: String, secret: String) {
        UserDefaults.standard.set(email, forKey: "lastAccountEmail")
        Keychain.set(password, for: .password)
        // Accept a pasted otpauth:// URL, storing just the base32 secret.
        let totp = TOTP.base32Secret(from: secret)
        Keychain.set(totp.isEmpty ? nil : totp, for: .totpSecret)
        Prefs.shared.autofillEnabled = true
        Prefs.shared.autoReloginOnExpiry = true
        startAutoSignIn()
    }

    /// Cookie-only session check — also how the SSO window knows it's done.
    func probeSession() async -> Bool {
        do {
            let user = try await client.currentUser()
            employeeID = user.id
            accountEmail = user.email
            if let email = user.email, !email.isEmpty {
                UserDefaults.standard.set(email, forKey: "lastAccountEmail")
            }
            if !user.name.isEmpty {
                profile = (user.name, user.role, user.site)
            }
            return true
        } catch {
            NSLog("BetterBob: probeSession failed — \(error)")
            return false
        }
    }

    private func completeSSOSignIn() async {
        UserDefaults.standard.set(true, forKey: "signedInViaSSO")
        signedIn = true
        lastError = nil
        reasonOptions = (try? await client.fetchReasonOptions()) ?? []
        await reconcile()
    }

    func signOut() {
        UserDefaults.standard.set(false, forKey: "signedInViaSSO")
        HTTPCookieStorage.shared.cookies?.forEach(HTTPCookieStorage.shared.deleteCookie)
        SSOSignInController.clearWebCookies()
        signedIn = false
        ready = false
        accountEmail = nil
        employeeID = nil
        entries = []
        recomputeDerived()
    }

    private func connect() async {
        do {
            busy = true
            defer { busy = false }
            // Pull the persisted web-view session into the API cookie store first
            // — otherwise a still-valid session reads as signed out on launch.
            await SSOSignInController.syncWebCookies()
            guard await probeSession() else { throw BobError.sessionExpired }
            signedIn = true
            lastError = nil
            reasonOptions = (try? await client.fetchReasonOptions()) ?? []
            await reconcile()
        } catch {
            signedIn = false
            lastError = BobError.sessionExpired.localizedDescription
            if Prefs.shared.autoReloginOnExpiry, canAutoSignIn { startAutoSignIn() }
        }
    }

    // MARK: - User actions

    func clockIn()          { enqueuePunch(.clockIn) }
    func clockOut()         { enqueuePunch(.clockOut) }
    func startManualBreak() { enqueuePunch(.startBreak) }
    func endBreak()         { enqueuePunch(.endBreak) }

    /// The clock state you'd be in once every queued punch has fired — what the
    /// action buttons offer, so queuing several ahead of time makes sense.
    var projectedClockState: ClockState {
        queue.reduce(clockState) { $1.action.applied(to: $0, at: $1.fireAt) }
    }

    /// Add a punch to the queue. It fires as soon as the 1-minute gap since the
    /// previous punch/queued item allows (immediately if already clear).
    private func enqueuePunch(_ action: PunchAction) {
        guard employeeID != nil else { return }
        queue.append(QueuedPunch(action: action, fireAt: .distantFuture))
        recomputeQueueTimes()
        scheduleQueue()
    }

    /// Remove a still-pending punch before it fires.
    func removeQueued(_ id: UUID) {
        queue.removeAll { $0.id == id }
        recomputeQueueTimes()
        scheduleQueue()
    }

    /// Space the queue one cooldown apart, the first no earlier than the gap
    /// since the last real punch.
    private func recomputeQueueTimes() {
        var t = max(now, (lastPunchAt ?? .distantPast).addingTimeInterval(Self.punchCooldown))
        for i in queue.indices {
            queue[i].fireAt = t
            t = t.addingTimeInterval(Self.punchCooldown)
        }
    }

    private func scheduleQueue() {
        queueTimer?.invalidate()
        guard let head = queue.first else { busy = false; return }
        busy = true
        let delay = max(0, head.fireAt.timeIntervalSinceNow)
        queueTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { await self?.fireQueueHead() }
        }
    }

    private func fireQueueHead() async {
        guard let head = queue.first, let id = employeeID else { busy = false; return }
        queue.removeFirst()
        // Update the timeline optimistically so it reflects the punch instantly
        // and never blanks while the server catches up.
        expectedAfterPunch = head.action
        applyOptimistic(head.action)
        do {
            try await client.punch(head.action, employeeID: id)
            lastPunchAt = Date()
            if head.action == .endBreak { autoBreakStartedAt = nil }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Notifier.failure(error.localizedDescription)
        }
        // clockStatus can lag a beat behind the punch. reconcile() holds the
        // optimistic state until the server reflects it (clearing the flag),
        // so keep reconciling a few times, then give up and sync reality.
        await reconcile()
        var tries = 0
        while tries < 6, expectedAfterPunch != nil {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await reconcile()
            tries += 1
        }
        if expectedAfterPunch != nil { expectedAfterPunch = nil; await reconcile() }
        recomputeQueueTimes()
        scheduleQueue()   // next item, or clears `busy` when empty
    }

    /// Apply the expected result of a punch to `entries` right away, so the UI
    /// updates without waiting for (or flickering through) the server round-trip.
    private func applyOptimistic(_ action: PunchAction) {
        let t = now
        switch action {
        case .clockIn:
            entries.append(AttendanceEntry(kind: .work, start: t, end: nil, id: nil, reason: currentAutoReason))
        case .clockOut:
            if let i = entries.lastIndex(where: { $0.end == nil }) { entries[i].end = t }
        case .startBreak:
            if let i = entries.lastIndex(where: { $0.kind == .work && $0.end == nil }) { entries[i].end = t }
            entries.append(AttendanceEntry(kind: .breakTime, start: t, end: nil))
        case .endBreak:
            if let i = entries.lastIndex(where: { $0.kind == .breakTime && $0.end == nil }) { entries[i].end = t }
            entries.append(AttendanceEntry(kind: .work, start: t, end: nil, id: nil, reason: currentAutoReason))
        }
        entries.sort { $0.start < $1.start }
        recomputeDerived()
    }

    /// Whether `es` yields the clock state `action` should have produced.
    private func clockStateReflects(_ action: PunchAction, in es: [AttendanceEntry]) -> Bool {
        let st = AttendanceLogic.state(entries: es, now: now)
        switch action {
        case .clockIn:    if case .clockedOut = st { return false }; return true
        case .clockOut:   if case .clockedOut = st { return true }; return false
        case .startBreak: if case .onBreak = st { return true }; return false
        case .endBreak:   if case .working = st { return true }; return false
        }
    }

    /// Today's date at midnight (employee tz) — the `forDate` for today's edits.
    private var today: Date { Calendar.current.startOfDay(for: now) }

    /// Local today's `yyyy-MM-dd` key, matching the per-day timesheet dateKeys.
    private var todayKey: String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = client.timeZone
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: now)
    }

    /// Keep only entries that belong to today (employee tz). An open entry that
    /// began earlier but hasn't ended is kept — that's a live, still-running
    /// stretch, not a stale prior day.
    private func entriesForToday(_ es: [AttendanceEntry]) -> [AttendanceEntry] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = client.timeZone
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return es }
        return es.filter { ($0.start >= start && $0.start < end) || $0.end == nil }
    }

    // Today convenience wrappers (popover + Today table).
    func setReason(for entry: AttendanceEntry, to option: ReasonOption) {
        setReason(for: entry, in: entries, on: today, to: option)
    }
    func deleteEntry(_ entry: AttendanceEntry) {
        deleteEntry(entry, in: entries, on: today)
    }
    func updateEntryTimes(_ entry: AttendanceEntry, start: Date, end: Date?) {
        updateEntryTimes(entry, in: entries, on: today, start: start, end: end)
    }

    /// Change one entry's reason within a specific day (whole-day resave).
    func setReason(for entry: AttendanceEntry, in day: [AttendanceEntry], on date: Date, to option: ReasonOption) {
        guard entry.id != nil else { return }
        saveDay(day.map { e in var e = e; if e.id == entry.id { e.reason = option.name }; return e }, on: date)
    }

    /// Delete one entry from a specific day. Keeps the row visible with a
    /// spinner (via `deletingEntries`) until the server confirms, rather than
    /// optimistically yanking it, so the deletion has a clear loading state.
    func deleteEntry(_ entry: AttendanceEntry, in day: [AttendanceEntry], on date: Date) {
        guard let entryID = entry.id, let empID = employeeID else { return }
        deletingEntries.insert(entryID)
        let kept = day.filter { $0.id != entry.id }
        // Closing the gap the deletion leaves keeps the day contiguous (opt-in).
        let remaining = Prefs.shared.autoFixGapsOverlaps
            ? AttendanceLogic.normalized(kept)
            : kept.sorted { $0.start < $1.start }
        let payload = writePayload(for: remaining)
        Task {
            defer { deletingEntries.remove(entryID) }
            do {
                try await client.writeEntries(payload, employeeID: empID, forDate: date)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                Notifier.failure(error.localizedDescription)
            }
            await reconcile()
            await loadMonthDays()
        }
    }

    /// Adjust one entry's start/end within a specific day.
    func updateEntryTimes(_ entry: AttendanceEntry, in day: [AttendanceEntry], on date: Date,
                          start: Date, end: Date?) {
        guard entry.id != nil else { return }
        saveDay(day.map { e in var e = e; if e.id == entry.id { e.start = start; e.end = end }; return e },
                on: date, anchor: entry.id)
    }

    /// True when the day has enough work to owe a break but none is logged.
    /// The reason that will be auto-applied to work right now — a matching
    /// Wi-Fi rule for the current network, else the default. nil if neither.
    var currentAutoReason: String? {
        let prefs = Prefs.shared
        if prefs.wifiAutoReasonEnabled, let reason = matchingWiFiReason() {
            return reason
        }
        return prefs.defaultReasonName.isEmpty ? nil : prefs.defaultReasonName
    }

    /// Reason for a Wi-Fi rule matching the current SSID (trimmed,
    /// case-insensitive), or nil.
    private func matchingWiFiReason() -> String? {
        guard let ssid = WiFiMonitor.shared.currentSSID()?
            .trimmingCharacters(in: .whitespaces), !ssid.isEmpty else { return nil }
        return Prefs.shared.wifiRules.first {
            !$0.reasonName.isEmpty
                && $0.ssid.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(ssid) == .orderedSame
        }?.reasonName
    }

    /// Length of the current uninterrupted work stretch (0 unless working).
    var uninterruptedWork: TimeInterval {
        guard case .working(let since) = clockState else { return 0 }
        return max(0, now.timeIntervalSince(since))
    }

    /// Whether a day's entries contain any uninterrupted work run past the max
    /// — so the "add a break" wand can offer to fix it (on any day, not just
    /// today, and even when other breaks already exist).
    func hasOverLongStretch(_ dayEntries: [AttendanceEntry]) -> Bool {
        AttendanceLogic.overLongStretch(entries: dayEntries,
                                        threshold: Prefs.shared.threshold, now: now) != nil
    }

    /// True when today has an uninterrupted run past the max non-break time.
    var overMaxNonBreak: Bool { hasOverLongStretch(entries) }

    /// Whether a day's total worked time is past the daily max (default 10h).
    func isOverDailyMax(_ dayEntries: [AttendanceEntry]) -> Bool {
        AttendanceLogic.overDailyMax(entries: dayEntries,
                                     max: Prefs.shared.maxDayLimit, now: now)
    }

    /// True when today's total worked time is past the daily max.
    var overDailyMax: Bool { isOverDailyMax(entries) }

    /// Magic-wand fix for a too-long stretch on `date`: carve a break out of the
    /// middle of the offending run. Clock-in/out stay put, so this *reduces*
    /// worked time by the break length rather than extending the day.
    func addMissingBreak() { addMissingBreak(in: entries, on: today) }

    func addMissingBreak(in dayEntries: [AttendanceEntry], on date: Date) {
        guard let rebuilt = AttendanceLogic.insertingAllBreaks(
                into: dayEntries, threshold: Prefs.shared.threshold,
                breakLength: Prefs.shared.breakLength, now: now) else { return }
        saveDay(rebuilt, on: date)
    }

    /// HiBob's "Break not taken or doesn't meet guidelines" for a day: worked
    /// past the threshold with too little qualifying pause (only pauses of
    /// 15 min or more count). Returns the missing pause time.
    func breakShortfall(_ dayEntries: [AttendanceEntry]) -> TimeInterval? {
        AttendanceLogic.breakShortfall(entries: dayEntries, threshold: Prefs.shared.threshold,
                                       required: Prefs.shared.breakLength, now: now)
    }
    /// Today's break-guideline shortfall, if any.
    var breakGuidelineShortfall: TimeInterval? { breakShortfall(entries) }

    /// Wand fix for a break-guideline shortfall: grow the day's longest break
    /// (or insert one) so the required pause is met.
    func fixBreakGuideline() { fixBreakGuideline(in: entries, on: today) }
    func fixBreakGuideline(in dayEntries: [AttendanceEntry], on date: Date) {
        guard let rebuilt = AttendanceLogic.meetingBreakGuideline(
                entries: dayEntries, threshold: Prefs.shared.threshold,
                required: Prefs.shared.breakLength, now: now) else { return }
        saveDay(rebuilt, on: date)
    }

    /// Resave a whole day's entries for `date` (the write API is whole-day).
    /// `anchor` is the id of the entry the user just edited; when the
    /// auto-fix-gaps-and-overlaps preference is on, the day is normalised so it
    /// stays contiguous, keeping the anchor's times and moving its neighbours.
    func saveDay(_ entries: [AttendanceEntry], on date: Date, anchor: String? = nil) {
        guard let id = employeeID else { return }
        let sorted = Prefs.shared.autoFixGapsOverlaps
            ? AttendanceLogic.normalized(entries, anchor: anchor)
            : entries.sorted { $0.start < $1.start }

        // Optimistic update so the UI reflects the edit instantly, before the
        // server round-trip + reload confirms it.
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian); df.timeZone = client.timeZone
        df.dateFormat = "yyyy-MM-dd"
        let key = df.string(from: date)
        if let idx = monthDays.firstIndex(where: { $0.dateKey == key }) {
            monthDays[idx].entries = sorted
        }
        if key == df.string(from: today) { self.entries = sorted }

        let payload = writePayload(for: sorted)
        busy = true
        Task {
            defer { busy = false }
            do {
                try await client.writeEntries(payload, employeeID: id, forDate: date)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                Notifier.failure(error.localizedDescription)
            }
            await reconcile()
            await loadMonthDays()
        }
    }

    func loadMonthDays() async {
        guard let id = employeeID else { return }
        if let m = try? await client.fetchMonthDays(employeeID: id, cycleId: cycle?.id ?? 0,
                                                    reasonOptions: reasonOptions) {
            monthDays = m
        }
    }

    // MARK: - Time off

    func loadTimeOff() async {
        guard let id = employeeID else { return }
        if let b = try? await client.fetchTimeOffBalances(employeeID: id) { timeOffBalances = b }
        if let r = try? await client.fetchTimeOffRequests(employeeID: id) { timeOffRequests = r }
        if let p = try? await client.fetchTimeOffPolicyTypes(employeeID: id) { timeOffPolicyTypes = p }
    }

    /// Body shared by calculate and submit.
    private func timeOffBody(policyType: String, start: Date, end: Date) -> [String: Any] {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian); df.timeZone = client.timeZone
        df.dateFormat = "yyyy-MM-dd"
        return [
            "policyType": policyType,
            "requestRangeType": "days",
            "startDate": df.string(from: start),
            "endDate": df.string(from: end),
            "startDatePortion": "all_day",
            "endDatePortion": "all_day",
            "hours": NSNull(), "minutes": NSNull(),
            "skipManagerApproval": false,
        ]
    }

    func previewTimeOff(policyType: String, start: Date, end: Date) async throws -> TimeOffCalc? {
        guard let id = employeeID else { return nil }
        return try await client.calculateTimeOff(employeeID: id,
                                                 body: timeOffBody(policyType: policyType, start: start, end: end))
    }

    /// Submit a request; returns an error string or nil on success.
    func submitTimeOff(policyType: String, start: Date, end: Date) async -> String? {
        guard let id = employeeID else { return "Not signed in." }
        do {
            try await client.submitTimeOff(employeeID: id,
                                           body: timeOffBody(policyType: policyType, start: start, end: end))
            await loadTimeOff()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func cancelTimeOff(_ request: TimeOffRequest) {
        guard let id = employeeID else { return }
        cancellingRequests.insert(request.id)
        Task {
            try? await client.cancelTimeOff(employeeID: id, request: request.id)
            await loadTimeOff()
            cancellingRequests.remove(request.id)
        }
    }

    // MARK: - Reconciliation (the heartbeat)

    func reconcile() async {
        guard signedIn, let id = employeeID else {
            // Logged out: keep retrying the silent re-login on each wake/poll (not
            // just the one that first noticed the expiry), so waking on Monday
            // signs you back in on its own when auto-relogin is enabled.
            if !signedIn, Prefs.shared.autoReloginOnExpiry, canAutoSignIn, !autoLoginInProgress {
                startAutoSignIn()
            }
            return
        }
        do {
            var status = try await client.fetchDayStatus()

            // The auto-break flag only means something while our break is open.
            if autoBreakStartedAt != nil,
               !status.entries.contains(where: { $0.kind == .breakTime && $0.end == nil }) {
                autoBreakStartedAt = nil
            }

            // Auto-break + Wi-Fi tagging are best-effort: a failure here must not
            // abort the dashboard refresh or the entries resolution below.
            do {
                // Act on auto-break once we're past the punch cooldown. (We don't
                // gate on HiBob's `disabled` flag — it proved unreliable.)
                let cooledDown = (lastPunchAt ?? .distantPast)
                    .addingTimeInterval(Self.punchCooldown) <= now
                if Prefs.shared.autoBreakEnabled, cooledDown,
                   let action = AttendanceLogic.action(entries: status.entries,
                                                       autoBreakStartedAt: autoBreakStartedAt,
                                                       threshold: Prefs.shared.threshold,
                                                       breakLength: Prefs.shared.breakLength,
                                                       now: now),
                   shouldAttempt(action) {
                    try await apply(action, employeeID: id, entries: status.entries)
                    status = try await client.fetchDayStatus()
                }

                // Wi-Fi rule: on the office network, tag the open work entry.
                if let rebuilt = wifiReasonUpdate(for: status.entries) {
                    try await client.writeEntries(writePayload(for: rebuilt),
                                                  employeeID: id, forDate: now)
                    status = try await client.fetchDayStatus()
                }
            } catch {
                lastError = error.localizedDescription
            }

            // Dashboard figures (cycle + per-day summary) — also feed the
            // midnight fallback below, so load them before resolving entries.
            if let (c, s) = try? await client.fetchCycleSummary(employeeID: id) {
                cycle = c
                cycleSummary = s
            }
            await loadMonthDays()

            // Resolve today's entries ONCE and assign only when they actually
            // change, so a refresh never blanks the timeline. Prefer clockStatus;
            // near midnight it reports the UTC day (empty for the local today),
            // so fall back to the per-day timesheet the web uses.
            var resolved = entriesForToday(status.entries)
            if resolved.isEmpty, let md = monthDays.first(where: { $0.dateKey == todayKey }) {
                resolved = md.entries
            }
            // Hold the optimistic post-punch state until the server reflects it,
            // rather than briefly reverting to stale data.
            if let expected = expectedAfterPunch {
                if clockStateReflects(expected, in: resolved) {
                    if entries != resolved { entries = resolved }
                    expectedAfterPunch = nil
                }
            } else if entries != resolved {
                entries = resolved
            }

            lastSync = Date()
            lastError = nil
            maybeNotifyReminders()
            if let acts = try? await client.fetchActivity(employeeID: id, date: Date()) {
                activity = acts
            }
            await loadTimeOff()
        } catch BobError.sessionExpired {
            // Okta session gone — flip to signed-out so the popover offers
            // the sign-in button instead of erroring forever.
            signedIn = false
            lastError = BobError.sessionExpired.localizedDescription
            // Silently re-login in the background if the user opted in.
            if Prefs.shared.autoReloginOnExpiry, canAutoSignIn {
                startAutoSignIn()
            } else {
                Notifier.failure(BobError.sessionExpired.localizedDescription)
            }
        } catch {
            lastError = error.localizedDescription
            Notifier.failure(error.localizedDescription)
        }

        recomputeDerived()
        armEventTimer()
        // The day is fully settled now (entries + clock state consistent).
        if signedIn { ready = true }
    }

    private func apply(_ action: AutoBreakAction, employeeID id: String,
                       entries: [AttendanceEntry]) async throws {
        switch action {
        case .insertBreak(let start, let end):
            // Place the break at its due moment (retroactively) by rewriting the
            // day — never a "start break now" punch, so the max is respected.
            guard let rebuilt = AttendanceLogic.insertingBreak(into: entries,
                                                               start: start, end: end) else {
                lastError = "Couldn't place the break — no matching work entry."
                return
            }
            try await client.writeEntries(writePayload(for: rebuilt), employeeID: id, forDate: now)
            if let end {
                Notifier.insertedPastBreak(start: start, end: end)   // whole window already passed
            } else {
                autoBreakStartedAt = start                            // ongoing from `start`
                Notifier.autoBreakStarted(length: Prefs.shared.breakLength)
            }
        case .endBreak(let at):
            guard let rebuilt = AttendanceLogic.closingBreak(into: entries, at: at,
                                                             reason: currentAutoReason) else { return }
            try await client.writeEntries(writePayload(for: rebuilt), employeeID: id, forDate: now)
            autoBreakStartedAt = nil
            Notifier.autoBreakEnded()
        }
    }

    /// If the Wi-Fi rule is on and we're on the configured office SSID, and
    /// the currently-open work entry has no reason yet, return the day's
    /// entries with that one entry's reason set. Returns nil if there's
    /// nothing to change — so we only write when it actually matters, and we
    /// never override a reason the user set themselves.
    private func wifiReasonUpdate(for entries: [AttendanceEntry]) -> [AttendanceEntry]? {
        let prefs = Prefs.shared

        // A matching Wi-Fi rule wins (when that feature is on); otherwise the
        // general default applies on its own — independent of the Wi-Fi toggle.
        var reason: String?
        if prefs.wifiAutoReasonEnabled { reason = matchingWiFiReason() }
        if reason == nil, !prefs.defaultReasonName.isEmpty {
            reason = prefs.defaultReasonName
        }

        guard let reason, reasonOptions.contains(where: { $0.name == reason }),
              let idx = entries.firstIndex(where: {
                  $0.kind == .work && $0.end == nil && ($0.reason ?? "").isEmpty
              })
        else { return nil }
        var updated = entries
        updated[idx].reason = reason
        return updated
    }

    // MARK: - Write payload

    /// Serialize entries into the array shape the edit endpoint expects:
    /// local wall-clock start/end, reason as its serverId, and the tz offset
    /// in minutes (HiBob/JS convention: minutes *west* of UTC, so Vienna
    /// CEST = -120).
    private func writePayload(for entries: [AttendanceEntry]) -> [[String: Any]] {
        let tz = client.timeZone
        let offsetMinutes = -tz.secondsFromGMT(for: now) / 60
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = tz
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let reasonID: (String?) -> Any = { name in
            guard let name, let opt = self.reasonOptions.first(where: { $0.name == name })
            else { return NSNull() }
            return opt.id ?? NSNull()
        }
        return entries.map { e in
            var row: [String: Any] = [
                "start": df.string(from: e.start),
                "end": e.end.map { df.string(from: $0) } ?? NSNull(),
                "reason": reasonID(e.reason),
                "comment": NSNull(),
                "entryType": e.kind == .breakTime ? "break" : "work",
                "reportingMethod": "startEnd",
                "offset": offsetMinutes,
            ]
            if let id = e.id, let n = Int(id) { row["id"] = n }
            else if let id = e.id { row["id"] = id }
            return row
        }
    }

    /// True unless this exact action already ran in the last 15 minutes —
    /// which would mean the write isn't sticking, and repeating it every poll
    /// would hammer HiBob.
    private func shouldAttempt(_ action: AutoBreakAction) -> Bool {
        let key = String(describing: action)
        if key == lastActionKey, let at = lastActionAt,
           Date().timeIntervalSince(at) < 15 * 60 {
            lastError = "An auto-break action didn't stick — check Docs/endpoints.md. Retrying every 15 minutes."
            return false
        }
        lastActionKey = key
        lastActionAt = Date()
        return true
    }

    /// Fire the target-reached (once/day) and deadline (once/cycle) reminders.
    private func maybeNotifyReminders() {
        let today = DayFmt.iso.string(from: now)

        // Daily target reached.
        if let target = cycleSummary?.days.first(where: { $0.date == today })?.target, target > 0,
           workedToday >= target * 3600,
           UserDefaults.standard.string(forKey: "targetNotifiedDay") != today {
            UserDefaults.standard.set(today, forKey: "targetNotifiedDay")
            Notifier.targetReached(Fmt.hm(target * 3600))
        }

        // Crossed the daily max while the clock is still running, once per day.
        if case .working = clockState, workedToday > Prefs.shared.maxDayLimit,
           UserDefaults.standard.string(forKey: "overMaxNotifiedDay") != today {
            UserDefaults.standard.set(today, forKey: "overMaxNotifiedDay")
            Notifier.overDailyMax(Fmt.hm(Prefs.shared.maxDayLimit))
        }

        // Timesheet deadline approaching (within 3 days), once per cycle.
        if let cycle, let lock = cycle.lockAt {
            let days = Calendar.current.dateComponents([.day], from: now, to: lock).day ?? 99
            if days <= 3, days >= 0,
               UserDefaults.standard.string(forKey: "deadlineNotifiedCycle") != cycle.start {
                UserDefaults.standard.set(cycle.start, forKey: "deadlineNotifiedCycle")
                Notifier.deadlineApproaching(days: days)
            }
        }
    }

    private func recomputeDerived() {
        clockState = AttendanceLogic.state(entries: entries, now: now)
        NotificationCenter.default.post(name: .updateStatusItem, object: nil)
    }

    /// Arm a precise one-shot timer for the next auto-break start/end, so
    /// transitions land on the second instead of up to a poll late.
    private func armEventTimer() {
        eventTimer?.invalidate()
        guard Prefs.shared.autoBreakEnabled,
              let due = AttendanceLogic.nextEvent(entries: entries,
                                                  autoBreakStartedAt: autoBreakStartedAt,
                                                  threshold: Prefs.shared.threshold,
                                                  breakLength: Prefs.shared.breakLength,
                                                  now: now)
        else { return }
        let delay = max(1, due.timeIntervalSinceNow + 1)
        eventTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { await self?.reconcile() }
        }
    }

    // MARK: - Popover helpers

    /// Time worked today, computed live so an in-progress entry keeps
    /// counting up to now — HiBob's `minutesWorkedToday` is a snapshot frozen
    /// at the last punch, which reads low while you're still clocked in.
    var workedToday: TimeInterval {
        AttendanceLogic.workedToday(entries: entries, now: Date())
    }

    /// Date the auto-break will start, for the countdown chip.
    var autoBreakDue: Date? {
        guard Prefs.shared.autoBreakEnabled else { return nil }
        guard case .working(let since) = clockState else { return nil }
        return since.addingTimeInterval(Prefs.shared.threshold)
    }

    /// The label to show next to the menu-bar icon — each clock state has its
    /// own choice of what (if anything) to show.
    func menuBarText() -> String? {
        let prefs = Prefs.shared
        switch clockState {
        case .working:
            switch prefs.menuBarTextWorking {
            case .none: return nil
            case .workedTime: return Fmt.hm(workedToday)
            case .untilBreak:
                guard let due = autoBreakDue else {
                    // No countdown (auto-break off) — fall back to the day's
                    // total so the slot still shows something useful.
                    return workedToday > 0 ? Fmt.hm(workedToday) : nil
                }
                let r = due.timeIntervalSinceNow
                return r > 0 ? Fmt.hm(r) : "break"
            case .status: return "Working"
            }
        case .onBreak(let since):
            switch prefs.menuBarTextBreak {
            case .none: return nil
            case .breakElapsed: return Fmt.hm(now.timeIntervalSince(since))
            case .breakRemaining:
                // Only an auto-break has a known end — a manual break falls
                // back to how long it has run.
                if let ends = autoBreakEnds, ends > now { return Fmt.hm(ends.timeIntervalSince(now)) }
                return Fmt.hm(now.timeIntervalSince(since))
            case .workedTime: return Fmt.hm(workedToday)
            case .status: return "Break"
            }
        case .clockedOut:
            switch prefs.menuBarTextOut {
            case .none: return nil
            case .workedTime: return Fmt.hm(workedToday)
            case .status: return "Out"
            }
        }
    }

    /// End of the currently running auto-break, if one is running.
    var autoBreakEnds: Date? {
        guard case .onBreak = clockState, let started = autoBreakStartedAt else { return nil }
        return started.addingTimeInterval(Prefs.shared.breakLength)
    }
}
