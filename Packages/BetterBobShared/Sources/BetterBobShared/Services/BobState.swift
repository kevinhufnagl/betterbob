import SwiftUI
#if os(macOS)
import AppKit
#endif
import Combine

/// The app's one source of truth, refreshed from HiBob (the *real* source of
/// truth) every minute, on wake, and after every action. Decisions are
/// delegated to AttendanceLogic; this class polls, executes, and publishes.
@MainActor
public final class BobState: ObservableObject {
    public static let shared = BobState()

    @Published public private(set) var entries: [AttendanceEntry] = []
    @Published public private(set) var clockState: ClockState = .clockedOut
    @Published public private(set) var signedIn = false
    @Published public private(set) var accountEmail: String?
    @Published public private(set) var busy = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastSync: Date?
    @Published public private(set) var reasonOptions: [ReasonOption] = []
    @Published public private(set) var cycle: CycleInfo?
    @Published public private(set) var cycleSummary: CycleSummary?
    @Published public private(set) var activity: [ActivityEvent] = []
    @Published public private(set) var timeOffBalances: [TimeOffBalance] = []
    @Published public private(set) var timeOffRequests: [TimeOffRequest] = []
    @Published public private(set) var timeOffPolicyTypes: [TimeOffPolicyType] = []
    @Published public private(set) var cancellingRequests: Set<String> = []
    @Published public private(set) var monthDays: [DayEntries] = []
    /// The employee's display name / role / site for the dashboard header.
    @Published public private(set) var profile: (name: String, role: String, site: String)?

    private let client = BobClient()
    private var employeeID: String?
    private var pollTimer: Timer?
    private var eventTimer: Timer?
    private var queueTimer: Timer?

    /// HiBob rejects two punches less than a minute apart. We enforce the same
    /// gap client-side: punches sit in `queue` and fire one minute apart. The
    /// user can queue several ahead of time and remove any before it fires.
    public static let punchCooldown: TimeInterval = 60
    @Published public private(set) var queue: [QueuedPunch] = []
    /// A punch whose optimistic state we're holding until the server reflects it.
    private var expectedAfterPunch: PunchAction?
    /// Server-ids of entries currently being deleted (drives a per-row spinner).
    @Published public private(set) var deletingEntries: Set<String> = []
    /// False until the first reconcile after signing in has fully settled, so
    /// the UI can show a loading placeholder instead of a half-loaded day.
    @Published public private(set) var ready = false
    /// True while a window showing the full dashboard is on screen. The
    /// background poll skips the heavy fetches (month grid, activity feed,
    /// time off, per-poll cycle summary) unless something is actually
    /// displaying them — that's the bulk of the idle request traffic.
    private(set) var dashboardActive = false
    /// When the cycle summary was last fetched, to rate-limit it in the
    /// background (it only feeds notifications + the midnight fallback there).
    private var lastCycleSummaryAt: Date?
    /// True while a headless auto re-login is running (drives its loading state).
    @Published public private(set) var autoLoginInProgress = false
    /// A user-friendly line describing the current auto sign-in step.
    @Published public var autoLoginStatus = ""
    /// True once the hidden sign-in browser is sitting on the authenticator
    /// step and needs the one-time code — the UI shows an inline code field.
    @Published public var awaitingOTP = false
    /// True while an Okta Verify push is out and we're waiting for the user to
    /// approve it on their phone — the UI shows an "approve on your phone" state.
    @Published public var pushPending = false
    /// The factor the in-progress sign-in is using, so the inline UI knows from
    /// the start whether to show a code field or the push-approval state (rather
    /// than briefly flashing the code field before the push screen loads).
    @Published public var signInFactor: SignInFactor?
    /// True from the moment the user submits a code until it's accepted or
    /// rejected — drives the inline field's "Verifying…" state.
    @Published public var otpSubmitting = false
    /// Set when a submitted code was rejected, so the inline field can say so.
    @Published public var otpError: String?
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

    public func start() {
        Notifier.requestAuthorization()
        #if os(macOS)
        // Reading the Wi-Fi SSID needs Location authorization on modern macOS.
        if Prefs.shared.wifiAutoReasonEnabled { WiFiMonitor.shared.requestAccess() }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.reconcile() }
        }
        #endif

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
    public var usedSSO: Bool { UserDefaults.standard.bool(forKey: "signedInViaSSO") }

    // MARK: - Account

    /// True when a re-login can be started from stored credentials (autofill on
    /// + a password saved). Completion still needs the user to type the current
    /// authenticator code into the native prompt.
    public var canAutoSignIn: Bool { Prefs.shared.autofillEnabled && Keychain.has(.password) }

    /// Password AND authenticator secret on file (the Advanced setting):
    /// re-login is hands-free — codes are generated from the stored secret,
    /// so expiry can kick off a sign-in without waiting for a human.
    public var fullyAutomatic: Bool { canAutoSignIn && Keychain.has(.totpSecret) }

    /// Re-login using the stored password: the hidden browser fills email +
    /// password and advances to the authenticator step, where the inline field
    /// collects the one-time code from the user. Drives a loading state.
    ///
    /// Started on demand (when the user opens BetterBob and asks to sign in),
    /// never pre-emptively on expiry — Okta's login transaction expires in a
    /// few minutes, so driving to the code step only when the user is actually
    /// there keeps that transaction fresh when they submit the code.
    public func startAutoSignIn(factor: SignInFactor = .googleAuthenticator) {
        guard canAutoSignIn, !autoLoginInProgress else { return }
        autoLoginInProgress = true
        signInFactor = factor
        autoLoginStatus = "Opening HiBob…"
        lastError = nil
        SSOSignInController.shared.presentAssisted(factor: factor) { [weak self] success in
            guard let self else { return }
            self.autoLoginInProgress = false
            self.awaitingOTP = false
            self.pushPending = false
            self.signInFactor = nil
            self.autoLoginStatus = ""
            if success {
                Task { await self.completeSSOSignIn() }
            } else {
                let reason = SSOSignInController.shared.lastFailureReason
                self.lastError = reason ?? "Sign-in didn't complete — check your details and try again."
                Notifier.failure(reason ?? "Sign-in didn't complete.")
            }
        }
    }

    /// Feed the code the user typed into the inline field to the sign-in browser.
    public func submitOTP(_ code: String) {
        otpError = nil
        otpSubmitting = true
        SSOSignInController.shared.submitCode(code)
    }

    /// Abort an in-progress auto sign-in (inline Cancel).
    public func cancelAutoSignIn() {
        SSOSignInController.shared.cancel()
    }

    /// First-run onboarding: save the auto-login credentials and turn on autofill
    /// + auto-relogin. Only the password is stored — the authenticator code is
    /// always typed (or push-approved) at sign-in. Does NOT start signing in;
    /// the user then picks a method (Google / Okta code / Okta push).
    public func setupAutoLogin(email: String, password: String) {
        UserDefaults.standard.set(email, forKey: "lastAccountEmail")
        Keychain.set(password, for: .password)
        Prefs.shared.autofillEnabled = true
        Prefs.shared.autoReloginOnExpiry = true
    }

    /// Cookie-only session check — also how the SSO window knows it's done.
    public func probeSession() async -> Bool {
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

    public func signOut() {
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
            // Re-login starts on demand (see startAutoSignIn) — just nudge.
            // With a stored authenticator secret there is no one to wait for:
            // start the hands-free sign-in right away.
            if Prefs.shared.autoReloginOnExpiry, fullyAutomatic {
                startAutoSignIn()
            } else if Prefs.shared.autoReloginOnExpiry, canAutoSignIn {
                Notifier.awaitingCode()
            }
        }
    }

    // MARK: - User actions

    public func clockIn()          { enqueuePunch(.clockIn) }
    public func clockOut()         { enqueuePunch(.clockOut) }
    public func startManualBreak() { enqueuePunch(.startBreak) }
    public func endBreak()         { enqueuePunch(.endBreak) }

    /// The clock state you'd be in once every queued punch has fired — what the
    /// action buttons offer, so queuing several ahead of time makes sense.
    public var projectedClockState: ClockState {
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
    public func removeQueued(_ id: UUID) {
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
        var punched = false
        do {
            try await client.punch(head.action, employeeID: id)
            punched = true
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
        // Clocking in after a clocked-out hole: stretch the preceding break to
        // the clock-in (auto-break ended before the user came back), or cover
        // a hole after work with a new break (clocked out at 2, back at 3).
        // Same opt-in as the other gap fixes.
        if punched, head.action == .clockIn, Prefs.shared.autoFixGapsOverlaps,
           let fixed = AttendanceLogic.fillingGapBeforeClockIn(entries: entries) {
            saveDay(fixed, on: today)
        }
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
    public func setReason(for entry: AttendanceEntry, to option: ReasonOption) {
        setReason(for: entry, in: entries, on: today, to: option)
    }
    public func deleteEntry(_ entry: AttendanceEntry) {
        deleteEntry(entry, in: entries, on: today)
    }
    public func updateEntryTimes(_ entry: AttendanceEntry, start: Date, end: Date?) {
        updateEntryTimes(entry, in: entries, on: today, start: start, end: end)
    }

    /// Change one entry's reason within a specific day (whole-day resave).
    public func setReason(for entry: AttendanceEntry, in day: [AttendanceEntry], on date: Date, to option: ReasonOption) {
        guard entry.id != nil else { return }
        saveDay(day.map { e in var e = e; if e.id == entry.id { e.reason = option.name }; return e }, on: date)
    }

    /// Delete one entry from a specific day. Keeps the row visible with a
    /// spinner (via `deletingEntries`) until the server confirms, rather than
    /// optimistically yanking it, so the deletion has a clear loading state.
    public func deleteEntry(_ entry: AttendanceEntry, in day: [AttendanceEntry], on date: Date) {
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
    public func updateEntryTimes(_ entry: AttendanceEntry, in day: [AttendanceEntry], on date: Date,
                          start: Date, end: Date?) {
        guard entry.id != nil else { return }
        saveDay(day.map { e in var e = e; if e.id == entry.id { e.start = start; e.end = end }; return e },
                on: date, anchor: entry.id)
    }

    /// Add a brand-new entry (no server id yet) to a specific day and resave
    /// the whole day. The server assigns the id on the reconcile that follows.
    /// The `date`'s calendar day is combined with the picked wall-clock times
    /// so a manual entry lands on the right day even when edited elsewhere.
    public func addEntry(kind: AttendanceEntry.Kind, start: Date, end: Date?,
                         reason: String?, in day: [AttendanceEntry], on date: Date) {
        let cal = Calendar.current
        func onDay(_ t: Date) -> Date {
            let c = cal.dateComponents([.hour, .minute], from: t)
            return cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0,
                            second: 0, of: date) ?? t
        }
        let new = AttendanceEntry(kind: kind, start: onDay(start),
                                  end: end.map(onDay), id: nil, reason: reason)
        saveDay(day + [new], on: date)
    }

    /// Add an entry to today.
    public func addEntry(kind: AttendanceEntry.Kind, start: Date, end: Date?, reason: String?) {
        addEntry(kind: kind, start: start, end: end, reason: reason, in: entries, on: today)
    }

    /// True when the day has enough work to owe a break but none is logged.
    /// The reason that will be auto-applied to work right now — a matching
    /// Wi-Fi rule for the current network, else the default. nil if neither.
    public var currentAutoReason: String? {
        let prefs = Prefs.shared
        if prefs.wifiAutoReasonEnabled, let reason = matchingWiFiReason() {
            return reason
        }
        return prefs.defaultReasonName.isEmpty ? nil : prefs.defaultReasonName
    }

    /// Reason for a Wi-Fi rule matching the current SSID (trimmed,
    /// case-insensitive), or nil.
    private func matchingWiFiReason() -> String? {
        #if os(macOS)
        guard let ssid = WiFiMonitor.shared.currentSSID()?
            .trimmingCharacters(in: .whitespaces), !ssid.isEmpty else { return nil }
        return Prefs.shared.wifiRules.first {
            !$0.reasonName.isEmpty
                && $0.ssid.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(ssid) == .orderedSame
        }?.reasonName
        #else
        // iOS has no CoreWLAN — reason tagging falls through to the default
        // reason in `currentAutoReason`.
        return nil
        #endif
    }

    /// Length of the current uninterrupted work stretch (0 unless working).
    public var uninterruptedWork: TimeInterval {
        guard case .working(let since) = clockState else { return 0 }
        return max(0, now.timeIntervalSince(since))
    }

    /// Whether a day's entries contain any uninterrupted work run past the max
    /// — so the "add a break" wand can offer to fix it (on any day, not just
    /// today, and even when other breaks already exist).
    public func hasOverLongStretch(_ dayEntries: [AttendanceEntry]) -> Bool {
        AttendanceLogic.overLongStretch(entries: dayEntries,
                                        threshold: Prefs.shared.threshold, now: now) != nil
    }

    /// True when today has an uninterrupted run past the max non-break time.
    public var overMaxNonBreak: Bool { hasOverLongStretch(entries) }

    /// A day where at least one work entry has no reason set — i.e. some
    /// untagged time. Used to flag past days in the month grid.
    public func missingReason(_ dayEntries: [AttendanceEntry]) -> Bool {
        dayEntries.contains { $0.kind == .work && ($0.reason ?? "").isEmpty }
    }

    /// Whether a day's total worked time is past the daily max (default 10h).
    public func isOverDailyMax(_ dayEntries: [AttendanceEntry]) -> Bool {
        AttendanceLogic.overDailyMax(entries: dayEntries,
                                     max: Prefs.shared.maxDayLimit, now: now)
    }

    /// True when today's total worked time is past the daily max.
    public var overDailyMax: Bool { isOverDailyMax(entries) }

    /// The over-limit tint for today, matching the month cells: red past the
    /// daily max, orange for an over-long uninterrupted run or a break
    /// shortfall, nil otherwise. Drives the hero water and the status pill.
    public var heroLimitTint: Color? {
        if overDailyMax { return .bobRed }
        if overMaxNonBreak || breakGuidelineShortfall != nil { return .bobOrange }
        return nil
    }

    /// Magic-wand fix for a too-long stretch on `date`: carve a break out of the
    /// middle of the offending run. Clock-in/out stay put, so this *reduces*
    /// worked time by the break length rather than extending the day.
    public func addMissingBreak() { addMissingBreak(in: entries, on: today) }

    public func addMissingBreak(in dayEntries: [AttendanceEntry], on date: Date) {
        guard let rebuilt = AttendanceLogic.insertingAllBreaks(
                into: dayEntries, threshold: Prefs.shared.threshold,
                breakLength: Prefs.shared.breakLength, now: now) else { return }
        saveDay(rebuilt, on: date)
    }

    /// HiBob's "Break not taken or doesn't meet guidelines" for a day: worked
    /// past the threshold with too little qualifying pause (only pauses of
    /// 15 min or more count). Returns the missing pause time.
    public func breakShortfall(_ dayEntries: [AttendanceEntry]) -> TimeInterval? {
        AttendanceLogic.breakShortfall(entries: dayEntries, threshold: Prefs.shared.threshold,
                                       required: Prefs.shared.breakLength, now: now)
    }
    /// Today's break-guideline shortfall, if any.
    public var breakGuidelineShortfall: TimeInterval? { breakShortfall(entries) }

    /// Wand fix for a break-guideline shortfall: grow the day's longest break
    /// (or insert one) so the required pause is met.
    public func fixBreakGuideline() { fixBreakGuideline(in: entries, on: today) }
    public func fixBreakGuideline(in dayEntries: [AttendanceEntry], on date: Date) {
        guard let rebuilt = AttendanceLogic.meetingBreakGuideline(
                entries: dayEntries, threshold: Prefs.shared.threshold,
                required: Prefs.shared.breakLength, now: now) else { return }
        saveDay(rebuilt, on: date)
    }

    /// Resave a whole day's entries for `date` (the write API is whole-day).
    /// `anchor` is the id of the entry the user just edited; when the
    /// auto-fix-gaps-and-overlaps preference is on, the day is normalised so it
    /// stays contiguous, keeping the anchor's times and moving its neighbours.
    public func saveDay(_ entries: [AttendanceEntry], on date: Date, anchor: String? = nil) {
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

    public func loadMonthDays() async {
        guard let id = employeeID else { return }
        if let m = try? await client.fetchMonthDays(employeeID: id, cycleId: cycle?.id ?? 0,
                                                    reasonOptions: reasonOptions) {
            monthDays = m
        }
    }

    /// Today's clock/edit history for the activity feed.
    public func loadActivity() async {
        guard let id = employeeID else { return }
        if let acts = try? await client.fetchActivity(employeeID: id, date: Date()) {
            activity = acts
        }
    }

    /// Cycle summary + month grid, loaded on demand when the This-month pane
    /// appears (the background poll no longer fetches the grid every minute).
    public func loadCycleData() async {
        guard let id = employeeID else { return }
        if let (c, s) = try? await client.fetchCycleSummary(employeeID: id) {
            cycle = c
            cycleSummary = s
            lastCycleSummaryAt = now
        }
        await loadMonthDays()
    }

    /// Called by the dashboard window as it shows/hides. Turning active kicks a
    /// full reconcile so the panes fill in immediately.
    public func setDashboardActive(_ active: Bool) {
        guard active != dashboardActive else { return }
        dashboardActive = active
        if active { Task { await reconcile() } }
    }

    // MARK: - Time off

    public func loadTimeOff() async {
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

    public func previewTimeOff(policyType: String, start: Date, end: Date) async throws -> TimeOffCalc? {
        guard let id = employeeID else { return nil }
        return try await client.calculateTimeOff(employeeID: id,
                                                 body: timeOffBody(policyType: policyType, start: start, end: end))
    }

    /// Submit a request; returns an error string or nil on success.
    public func submitTimeOff(policyType: String, start: Date, end: Date) async -> String? {
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

    public func cancelTimeOff(_ request: TimeOffRequest) {
        guard let id = employeeID else { return }
        cancellingRequests.insert(request.id)
        Task {
            try? await client.cancelTimeOff(employeeID: id, request: request.id)
            await loadTimeOff()
            cancellingRequests.remove(request.id)
        }
    }

    // MARK: - Reconciliation (the heartbeat)

    public func reconcile() async {
        guard signedIn, let id = employeeID else {
            // Logged out: nothing to poll. Re-login needs the user to type a
            // one-time code, so we don't auto-open the prompt on every poll —
            // it's offered once when the session first expires (see below) and
            // otherwise started from the sign-in button.
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

            // Cycle + per-day summary feed the target/deadline notifications
            // and the near-midnight fallback below. Refresh every poll while
            // the dashboard is open; in the background only every 10 minutes,
            // since nothing on screen depends on it minute-to-minute.
            let cycleStale = lastCycleSummaryAt.map { now.timeIntervalSince($0) > 600 } ?? true
            if dashboardActive || cycleStale,
               let (c, s) = try? await client.fetchCycleSummary(employeeID: id) {
                cycle = c
                cycleSummary = s
                lastCycleSummaryAt = now
            }
            // The month grid is a heavy fetch + parse. Load it every poll only
            // when the dashboard is open; otherwise leave it to CyclePane's own
            // loader and the targeted fallback just below.
            if dashboardActive { await loadMonthDays() }

            // Resolve today's entries ONCE and assign only when they actually
            // change, so a refresh never blanks the timeline. Prefer clockStatus;
            // near midnight it reports the UTC day (empty for the local today),
            // so fall back to the per-day timesheet the web uses — fetching it
            // on demand if the background poll skipped it.
            var resolved = entriesForToday(status.entries)
            if resolved.isEmpty {
                if monthDays.first(where: { $0.dateKey == todayKey }) == nil {
                    await loadMonthDays()
                }
                if let md = monthDays.first(where: { $0.dateKey == todayKey }) {
                    resolved = md.entries
                }
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
            // Activity feed + time off are dashboard-only; ActivityPane and
            // TimeOffPane load them on appear, so the background poll skips them.
            if dashboardActive {
                await loadActivity()
                await loadTimeOff()
            }
        } catch BobError.sessionExpired {
            // Okta session gone — flip to signed-out so the popover offers
            // the sign-in button instead of erroring forever.
            signedIn = false
            lastError = BobError.sessionExpired.localizedDescription
            // Start re-login on demand (not here) so the Okta login transaction
            // is fresh when the user actually enters the code — see note in
            // startAutoSignIn. Just nudge them to reconnect; the drive begins
            // when they open BetterBob and hit "Sign in automatically".
            if Prefs.shared.autoReloginOnExpiry, fullyAutomatic {
                // Hands-free: the stored secret supplies the code.
                startAutoSignIn()
            } else if Prefs.shared.autoReloginOnExpiry, canAutoSignIn {
                Notifier.awaitingCode()
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
    public var workedToday: TimeInterval {
        AttendanceLogic.workedToday(entries: entries, now: Date())
    }

    /// Date the auto-break will start, for the countdown chip.
    public var autoBreakDue: Date? {
        guard Prefs.shared.autoBreakEnabled else { return nil }
        guard case .working(let since) = clockState else { return nil }
        return since.addingTimeInterval(Prefs.shared.threshold)
    }

    /// The label to show next to the menu-bar icon — each clock state has its
    /// own choice of what (if anything) to show.
    public func menuBarText() -> String? {
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
    public var autoBreakEnds: Date? {
        guard case .onBreak = clockState, let started = autoBreakStartedAt else { return nil }
        return started.addingTimeInterval(Prefs.shared.breakLength)
    }
}
