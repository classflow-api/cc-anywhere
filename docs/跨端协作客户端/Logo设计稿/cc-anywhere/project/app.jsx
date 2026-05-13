// Main app for cc-anywhere design exploration
const { useState: useStateA, useEffect: useEffectA } = React;

// Defaults (tweakable, persisted by host)
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "mode": "dark",
  "terminal": "midnight",
  "accent": "cyan"
}/*EDITMODE-END*/;

const ACCENT_PRESETS = {
  cyan:    { light: 'oklch(0.62 0.13 215)', dark: 'oklch(0.78 0.13 200)', soft_l: 'oklch(0.92 0.06 215)', soft_d: 'oklch(0.30 0.08 200)' },
  violet:  { light: 'oklch(0.58 0.18 285)', dark: 'oklch(0.78 0.14 285)', soft_l: 'oklch(0.93 0.06 285)', soft_d: 'oklch(0.30 0.09 285)' },
  emerald: { light: 'oklch(0.62 0.15 165)', dark: 'oklch(0.78 0.16 165)', soft_l: 'oklch(0.93 0.07 165)', soft_d: 'oklch(0.30 0.09 165)' },
  amber:   { light: 'oklch(0.65 0.17 65)',  dark: 'oklch(0.82 0.16 75)',  soft_l: 'oklch(0.94 0.07 65)',  soft_d: 'oklch(0.32 0.09 65)'  },
};

function ThemedFrame({ mode, accent, children, style }) {
  const base = window.CC_TOKENS[mode];
  const a = ACCENT_PRESETS[accent] || ACCENT_PRESETS.cyan;
  const accentColor = mode === 'dark' ? a.dark : a.light;
  const accentSoft = mode === 'dark' ? a.soft_d : a.soft_l;
  const theme = {
    ...base,
    accent: accentColor,
    accentSoft,
  };
  return (
    <div style={{
      ...style,
      position: 'relative',
      ...Object.fromEntries(Object.entries(theme).map(([k,v]) => [`--${k}`, v])),
      color: 'var(--text)',
      fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", system-ui, sans-serif',
    }}>{children}</div>
  );
}

function App() {
  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const mode = tweaks.mode;
  const accent = tweaks.accent;
  const termKey = tweaks.terminal;
  const terminal = window.TERMINAL_THEMES[termKey] || window.TERMINAL_THEMES.midnight;

  // Background tone for canvas
  const canvasBg = mode === 'dark' ? '#06080d' : '#e9e6dc';

  // Set body bg for visual continuity
  useEffectA(() => {
    document.body.style.background = canvasBg;
  }, [canvasBg]);

  return (
    <>
      <DesignCanvas>
        <DCSection id="sec-mac" title="Mac 客户端" subtitle="Tab 管理 · 终端 · 设备 · 主题">
          <DCArtboard id="mac-main" label="主窗口 · refactor-engine 会话" width={1240} height={780}>
            <ThemedFrame mode={mode} accent={accent} style={{ width: '100%', height: '100%' }}>
              <MacMain theme={terminal} dark={mode === 'dark'} />
            </ThemedFrame>
          </DCArtboard>

          <DCArtboard id="mac-themes" label="偏好设置 · 终端主题" width={1240} height={780}>
            <ThemedFrame mode={mode} accent={accent} style={{ width: '100%', height: '100%' }}>
              <MacThemes
                theme={terminal} dark={mode === 'dark'}
                onPick={(k) => setTweak('terminal', k)}
              />
            </ThemedFrame>
          </DCArtboard>

          <DCArtboard id="mac-devices" label="偏好设置 · 设备管理" width={1240} height={780}>
            <ThemedFrame mode={mode} accent={accent} style={{ width: '100%', height: '100%' }}>
              <MacDevices theme={terminal} dark={mode === 'dark'} />
            </ThemedFrame>
          </DCArtboard>
        </DCSection>

        <DCSection id="sec-mobile" title="手机端 · Android" subtitle="绑定 · 会话列表 · 卡片对话 · tool_use 批准">
          <DCArtboard id="m-welcome" label="欢迎 · 开始绑定" width={406} height={816}>
            <ThemedFrame mode={mode} accent={accent} style={{ width: '100%', height: '100%', display: 'grid', placeItems: 'center' }}>
              <MobileWelcome dark={mode === 'dark'} />
            </ThemedFrame>
          </DCArtboard>

          <DCArtboard id="m-scan" label="扫码绑定" width={406} height={816}>
            <ThemedFrame mode={mode} accent={accent} style={{ width: '100%', height: '100%', display: 'grid', placeItems: 'center' }}>
              <MobileScan dark={mode === 'dark'} />
            </ThemedFrame>
          </DCArtboard>

          <DCArtboard id="m-list" label="会话列表" width={406} height={816}>
            <ThemedFrame mode={mode} accent={accent} style={{ width: '100%', height: '100%', display: 'grid', placeItems: 'center' }}>
              <MobileTabList dark={mode === 'dark'} />
            </ThemedFrame>
          </DCArtboard>

          <DCArtboard id="m-chat" label="对话流 · tool_use 批准" width={406} height={816}>
            <ThemedFrame mode={mode} accent={accent} style={{ width: '100%', height: '100%', display: 'grid', placeItems: 'center' }}>
              <MobileChat dark={mode === 'dark'} />
            </ThemedFrame>
          </DCArtboard>

          <DCArtboard id="m-settings" label="设置" width={406} height={816}>
            <ThemedFrame mode={mode} accent={accent} style={{ width: '100%', height: '100%', display: 'grid', placeItems: 'center' }}>
              <MobileSettings dark={mode === 'dark'} />
            </ThemedFrame>
          </DCArtboard>
        </DCSection>
      </DesignCanvas>

      {/* Tweaks panel */}
      <TweaksPanel title="Tweaks">
        <TweakSection label="外观">
          <TweakRadio
            label="模式"
            value={mode}
            onChange={(v) => setTweak('mode', v)}
            options={[
              { value: 'light', label: '日间' },
              { value: 'dark', label: '夜间' },
            ]}
          />
          <TweakRadio
            label="品牌色"
            value={accent}
            onChange={(v) => setTweak('accent', v)}
            options={[
              { value: 'cyan', label: '蓝青' },
              { value: 'violet', label: '紫' },
              { value: 'emerald', label: '翠' },
              { value: 'amber', label: '琥珀' },
            ]}
          />
        </TweakSection>

        <TweakSection label="终端主题">
          <TweakSelect
            label="预设"
            value={termKey}
            onChange={(v) => setTweak('terminal', v)}
            options={Object.entries(window.TERMINAL_THEMES).map(([k, v]) => ({
              value: k, label: v.name,
            }))}
          />
          <div style={{
            display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
            gap: 6, marginTop: 6,
          }}>
            {Object.entries(window.TERMINAL_THEMES).map(([k, v]) => (
              <div key={k} onClick={() => setTweak('terminal', k)} style={{
                cursor: 'pointer', borderRadius: 8, overflow: 'hidden',
                border: termKey === k ? '2px solid #fff' : '1px solid rgba(255,255,255,0.15)',
                background: v.bg, padding: '8px 6px',
                position: 'relative',
              }}>
                <div style={{
                  fontFamily: '"JetBrains Mono", ui-monospace', fontSize: 8.5,
                  color: v.fg, marginBottom: 4, fontWeight: 600,
                }}>{v.name}</div>
                <div style={{ display: 'flex', gap: 2 }}>
                  {[v.accent1, v.accent2, v.accent3, v.accent4, v.cursor].map((c, i) => (
                    <div key={i} style={{ flex: 1, height: 6, borderRadius: 1, background: c }}/>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </TweakSection>
      </TweaksPanel>
    </>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
