cask "agent" do
  version "0.1.9"

  # GitHub Releases renames spaces in uploaded asset filenames to dots
  # (confirmed via `gh release view --json assets` after the real upload —
  # "SocyU Agent-0.1.0-arm64.dmg" landed as "SocyU.Agent-0.1.0-arm64.dmg").
  # Match that exactly, not the local dist/ filename or a %20-encoded one —
  # both of those 404.
  #
  # v0.1.1 fixes two real bugs found testing against a second machine:
  #  1. Unpaired devices had no way to reach the UI if the menu-bar tray
  #     icon didn't render (confirmed happening on macOS 26.0) — the
  #     dashboard now auto-opens on first launch while unpaired
  #     (firstLaunchDashboard.js).
  #  2. The DMG was shipping every OS/arch's ffprobe-static and
  #     onnxruntime-node binaries at once (~270MB of dead weight on a mac
  #     build) — after-pack.js now prunes to just the target platform/arch,
  #     cutting the DMG from ~452MB to ~338MB.
  #
  # v0.1.2: Kokoro TTS segment caching (media/ttsCache.js) + profile-aware
  # speech delivery strategy (media/speechDeliveryStrategy.js) — reduces
  # repeat-synthesis time and personalizes narration pacing/gesture pattern
  # from the business profile.
  #
  # v0.1.3: Sarvam Hindi TTS provider (alternate to AWS Polly), Market Lens
  # service refactor + IPC module, article-grounded trend-carousel writer,
  # draft retention, and content pipeline fixes.
  #
  # v0.1.4: maximum asar compression + explicit unpack of ffmpeg-static /
  # ffprobe-static / onnxruntime-node (previously duplicated inside app.asar
  # since only *.node matched the unpack glob). ~357MB -> ~334MB, no
  # functional change. Verified via codesign --verify --deep --strict on
  # both arches, a DMG mount/contents check, and npm run test:media before
  # this release was cut.
  #
  # v0.1.5: fixes a real production bug — resolveApiBase.js's "probe
  # localhost:8000, fall back to prod" dev convenience had no packaged-build
  # gate, so any unrelated service already listening on port 8000 on a
  # user's machine silently hijacked every API call for the life of the
  # process (reported as "Check now" throwing a raw Flask/Werkzeug 404 page
  # instead of this app's real JSON error shape). Now gated on
  # app.isPackaged. Also: tray icon sometimes invisible on a cold launch
  # (trayVisibilityFix.js watchdog), Business info tab blank on first open.
  #
  # v0.1.6: fixes the app freezing ("Not Responding", up to 30s) on launch —
  # the ffmpeg license audit ran spawnSync twice on the main thread, on
  # every launch, each with a 15s timeout. Especially bad the first time a
  # machine ever runs the bundled (unsigned, ad-hoc-signed) ffmpeg binary,
  # since macOS Gatekeeper's first-run scan adds real latency before it can
  # even execute. Now async and cached — never blocks startup, and only the
  # very first launch on a machine spawns ffmpeg for this at all.
  #
  # v0.1.7: eliminates the API-base probing bug class entirely —
  # resolveApiBase.js no longer probes localhost:8000 in ANY mode, always
  # resolves to the real API (v0.1.5's app.isPackaged gate only closed this
  # for packaged builds; a dev machine running any local backend was still
  # exposed). API errors now show a short diagnostic instead of dumping the
  # full raw response body. Fixes a real leak in the tray-visibility
  # watchdog itself: a recreated Tray's setToolTip call re-entered the
  # patched method and started an independent, uncapped second watchdog
  # chain — a persistently-broken tray environment could recreate
  # indefinitely. Kokoro TTS init is now bounded by a timeout so a stalled
  # model load can't wedge every subsequent launch. New regression tests
  # cover all of the above (test/fresh-install-regression.js,
  # test/tray-visibility-regression.js).
  #
  # v0.1.8: preserves a person's in-progress Business Details wizard while
  # refreshing the remote profile, while an untouched new wizard correctly
  # receives its saved profile instead of appearing frozen on the first step.
  #
  # v0.1.9: fixes kLSNoExecutableErr on macOS 26 (Tahoe). The C launcher
  # compiled by after-pack.js was never ad-hoc codesigned, and macOS 26 rejects
  # an unsigned main bundle executable even after quarantine is cleared.
  # Also fixes x64 builds: the x64 Electron distribution ships with unsigned
  # helpers and framework binaries — after-pack.js now signs all Frameworks
  # subcomponents bottom-up before sealing the main bundle.
  on_arm do
    sha256 "ceb1775f1981e88f4fad4e187b71b71ba53fe73d0fbce47e591eb597e01e82b8"
    url "https://duzzvklv1705w.cloudfront.net/releases/v#{version}/SocyU.Agent-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "b5cd91114870da9fe2b935ef2cb682c83b2a6a6de2403fd0087e50d698a08044"
    url "https://duzzvklv1705w.cloudfront.net/releases/v#{version}/SocyU.Agent-#{version}.dmg"
  end

  name "SocyU Agent"
  desc "SocyU on-device content agent"
  homepage "https://socyu.app"

  depends_on macos: :sonoma

  app "SocyU Agent.app"

  # Ad-hoc signed, unnotarized (no paid Apple Developer Program — see
  # sdk/socyu-agent/docs/TERMINAL_INSTALL_PLAN.md "Zero-cost constraint").
  # Homebrew has already verified this download's sha256 against the value
  # pinned above before this line runs, so clearing quarantine here is
  # backed by that independent integrity check — do not replicate this in
  # a standalone curl script without the same verify-first ordering.
  #
  # postflight_steps runs in a different DSL than the old postflight block —
  # it builds a declarative, JSON-serialisable step list (Homebrew::InstallSteps::DSL,
  # see install_steps.rb in a brew checkout), not plain Ruby. Two real
  # consequences, both confirmed by reading that source directly:
  #   1. The method is `run`, not `system_command` — `system_command` doesn't
  #      exist in this DSL at all.
  #   2. `appdir` is not a callable Ruby method here (undef_method strips
  #      almost everything from this class), so `"#{appdir}/..."` throws
  #      "undefined local variable or method 'appdir'". Path tokens are
  #      resolved later, at run time, by substring-matching literal
  #      `{{appdir}}` in the arg string (Runner#expand_template_tokens) — so
  #      it has to be written as a template token, not interpolated.
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/SocyU Agent.app"],
        sudo: false
    # `brew install --cask` never launches the app afterward (unlike a native
    # .pkg installer) — a real user hit this: they ran `brew install --cask
    # socyu-agent`, then immediately went to socyu.com's "Check connection"
    # step, and got net::ERR_CONNECTION_REFUSED on 127.0.0.1:7845/health
    # because the agent process simply wasn't running yet. Launching it here,
    # right after quarantine is cleared, closes that gap — the local health
    # server (localHealthServer.js) is listening within a couple seconds of
    # this, well before a user can tab back to the browser and click retry.
    run "/usr/bin/open",
        args: ["-a", "{{appdir}}/SocyU Agent.app"],
        sudo: false
  end

  caveats <<~EOS
    SocyU Agent is not notarized by Apple (no paid Developer Program).
    Homebrew already cleared the quarantine flag that would otherwise
    block first launch, and has launched SocyU Agent for you.
    If macOS still refuses to open it: System Settings -> Privacy &
    Security -> scroll to the blocked-app notice -> "Open Anyway".
  EOS

  zap trash: [
    "~/Library/Application Support/SocyU Agent",
    "~/Library/Caches/com.socyu.agent",
    "~/Library/Saved Application State/com.socyu.agent.savedState",
  ]
end
