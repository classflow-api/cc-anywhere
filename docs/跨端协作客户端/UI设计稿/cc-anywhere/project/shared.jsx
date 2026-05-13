// Shared UI primitives for cc-anywhere
const { useState, useEffect, useRef, useMemo } = React;

// ── Animated dot grid background ────────────────────────────────
function DotGridBg({ color = 'rgba(255,255,255,0.05)', size = 22, opacity = 1, animate = true }) {
  return (
    <div style={{
      position: 'absolute', inset: 0, pointerEvents: 'none', opacity,
      backgroundImage: `radial-gradient(${color} 1px, transparent 1px)`,
      backgroundSize: `${size}px ${size}px`,
      maskImage: 'radial-gradient(ellipse at center, black 40%, transparent 90%)',
      WebkitMaskImage: 'radial-gradient(ellipse at center, black 40%, transparent 90%)',
      animation: animate ? 'cc-drift 30s linear infinite' : 'none',
    }} />
  );
}

// ── Animated aurora orbs in background ──────────────────────────
function AuroraOrbs({ tone = 'cyan' }) {
  const palettes = {
    cyan: ['oklch(0.72 0.18 200 / 0.5)', 'oklch(0.78 0.14 170 / 0.4)', 'oklch(0.65 0.16 240 / 0.4)'],
    warm: ['oklch(0.78 0.12 70 / 0.35)', 'oklch(0.72 0.14 30 / 0.3)', 'oklch(0.68 0.13 280 / 0.3)'],
  };
  const c = palettes[tone] || palettes.cyan;
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', pointerEvents: 'none' }}>
      <div style={{
        position: 'absolute', top: '-20%', left: '-10%', width: 520, height: 520,
        borderRadius: '50%', background: c[0], filter: 'blur(80px)',
        animation: 'cc-orb 18s ease-in-out infinite',
      }} />
      <div style={{
        position: 'absolute', bottom: '-20%', right: '-10%', width: 460, height: 460,
        borderRadius: '50%', background: c[1], filter: 'blur(80px)',
        animation: 'cc-orb 22s ease-in-out infinite reverse',
      }} />
      <div style={{
        position: 'absolute', top: '30%', right: '20%', width: 320, height: 320,
        borderRadius: '50%', background: c[2], filter: 'blur(80px)',
        animation: 'cc-orb 28s ease-in-out infinite',
      }} />
    </div>
  );
}

// ── Status pulse dot ─────────────────────────────────────────────
function PulseDot({ color = 'var(--success)', size = 8, pulse = true }) {
  return (
    <div style={{ position: 'relative', width: size, height: size, flexShrink: 0 }}>
      {pulse && (
        <div style={{
          position: 'absolute', inset: -2, borderRadius: '50%',
          background: color, opacity: 0.4,
          animation: 'cc-pulse 1.6s ease-out infinite',
        }} />
      )}
      <div style={{
        position: 'absolute', inset: 0, borderRadius: '50%',
        background: color,
        boxShadow: `0 0 8px ${color}`,
      }} />
    </div>
  );
}

// ── Tiny inline icon set (stroke-based, no AI-slop) ──────────────
const Icon = ({ name, size = 16, stroke = 'currentColor', strokeWidth = 1.6, fill = 'none' }) => {
  const p = {
    width: size, height: size, viewBox: '0 0 24 24', fill,
    stroke, strokeWidth, strokeLinecap: 'round', strokeLinejoin: 'round',
  };
  const paths = {
    plus: <><path d="M12 5v14M5 12h14"/></>,
    close: <><path d="M6 6l12 12M18 6l-12 12"/></>,
    chevronRight: <path d="M9 6l6 6-6 6"/>,
    chevronDown: <path d="M6 9l6 6 6-6"/>,
    folder: <path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V7z"/>,
    settings: <><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 01-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09a1.65 1.65 0 00-1-1.51 1.65 1.65 0 00-1.82.33l-.06.06A2 2 0 014.27 16.97l.06-.06a1.65 1.65 0 00.33-1.82 1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09a1.65 1.65 0 001.51-1 1.65 1.65 0 00-.33-1.82l-.06-.06A2 2 0 017.03 4.27l.06.06a1.65 1.65 0 001.82.33H9a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06A2 2 0 0119.73 7.03l-.06.06a1.65 1.65 0 00-.33 1.82V9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/></>,
    devices: <><rect x="2" y="4" width="14" height="11" rx="2"/><rect x="16" y="9" width="6" height="11" rx="1"/><path d="M9 18v2M6 20h6"/></>,
    qr: <><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3M21 14v3M14 17v4h3M17 21h4M21 17v4"/></>,
    terminal: <><path d="M4 6h16v12H4z"/><path d="M7 10l3 2-3 2M12 14h5"/></>,
    send: <path d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/>,
    image: <><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="M21 15l-5-5L5 21"/></>,
    check: <path d="M5 12l5 5L20 7"/>,
    x: <><path d="M6 6l12 12M18 6l-12 12"/></>,
    eye: <><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></>,
    palette: <><circle cx="13.5" cy="6.5" r="2.5"/><circle cx="17.5" cy="10.5" r="2.5"/><circle cx="8.5" cy="7.5" r="2.5"/><circle cx="6.5" cy="12.5" r="2.5"/><path d="M12 22a10 10 0 110-20c5.5 0 10 4 10 9 0 4-3.5 5-6 5h-2a2 2 0 00-2 2c0 1 1 2 1 3a1 1 0 01-1 1z"/></>,
    bolt: <path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z"/>,
    arrowDown: <path d="M12 5v14M19 12l-7 7-7-7"/>,
    arrowLeft: <path d="M19 12H5M12 19l-7-7 7-7"/>,
    wifi: <><path d="M5 12a10 10 0 0114 0M8.5 15.5a5 5 0 017 0"/><circle cx="12" cy="19" r="1" fill="currentColor"/></>,
    moon: <path d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z"/>,
    sun: <><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></>,
    sparkle: <path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3z"/>,
    cpu: <><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M20 9h3M20 14h3M1 9h3M1 14h3"/></>,
    camera: <><path d="M23 19a2 2 0 01-2 2H3a2 2 0 01-2-2V8a2 2 0 012-2h4l2-3h6l2 3h4a2 2 0 012 2z"/><circle cx="12" cy="13" r="4"/></>,
    refresh: <><path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.5 9a9 9 0 0114.85-3.36L23 10M1 14l4.65 4.36A9 9 0 0020.5 15"/></>,
    lock: <><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 018 0v4"/></>,
    logout: <><path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4M16 17l5-5-5-5M21 12H9"/></>,
    file: <><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path d="M14 2v6h6"/></>,
    code: <path d="M16 18l6-6-6-6M8 6l-6 6 6 6"/>,
    play: <path d="M6 4l14 8-14 8z" fill="currentColor"/>,
    pause: <><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></>,
    bell: <><path d="M18 8a6 6 0 10-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 01-3.4 0"/></>,
    download: <><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></>,
    edit: <><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></>,
    history: <><path d="M3 12a9 9 0 109-9 9.74 9.74 0 00-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/></>,
    pin: <path d="M12 17v5M9 10.5V4l-1-1h8l-1 1v6.5l3 3.5H6l3-3.5z"/>,
  };
  return <svg {...p}>{paths[name]}</svg>;
};

// ── Status bar pill ──────────────────────────────────────────────
function StatusPill({ color, icon, children, accent }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      height: 22, padding: '0 9px', borderRadius: 100,
      background: 'var(--bgInset)', border: '1px solid var(--line)',
      fontSize: 11.5, fontWeight: 500, color: 'var(--textMuted)',
      letterSpacing: 0.1, fontVariantNumeric: 'tabular-nums',
    }}>
      {color && <PulseDot color={color} size={6} pulse={!!accent} />}
      {icon}
      <span>{children}</span>
    </div>
  );
}

// ── Section heading (small caps) ────────────────────────────────
function SectionLabel({ children, style }) {
  return (
    <div style={{
      fontSize: 10.5, fontWeight: 600, letterSpacing: 1.4,
      color: 'var(--textFaint)', textTransform: 'uppercase',
      ...style,
    }}>{children}</div>
  );
}

// ── Generic glass card ──────────────────────────────────────────
function GlassCard({ children, style, padding = 16, glow }) {
  return (
    <div style={{
      position: 'relative',
      background: 'var(--panel)',
      border: '1px solid var(--line)',
      borderRadius: 14,
      backdropFilter: 'blur(20px) saturate(160%)',
      WebkitBackdropFilter: 'blur(20px) saturate(160%)',
      padding,
      boxShadow: glow
        ? '0 12px 36px -12px var(--accent), 0 0 0 1px var(--lineStrong)'
        : '0 1px 0 inset rgba(255,255,255,0.04)',
      ...style,
    }}>{children}</div>
  );
}

// ── Streaming text effect (for terminal/chat) ───────────────────
function useTypewriter(full, speedMs = 22, startDelay = 0) {
  const [out, setOut] = useState('');
  useEffect(() => {
    let i = 0;
    let stop = false;
    const tick = () => {
      if (stop) return;
      i++;
      setOut(full.slice(0, i));
      if (i < full.length) setTimeout(tick, speedMs);
    };
    const t = setTimeout(tick, startDelay);
    return () => { stop = true; clearTimeout(t); };
  }, [full, speedMs, startDelay]);
  return out;
}

// ── Looping typewriter ──────────────────────────────────────────
function useLoopType(lines, speedMs = 28, pauseMs = 1200) {
  const [i, setI] = useState(0);
  const [out, setOut] = useState('');
  useEffect(() => {
    let stop = false;
    let pos = 0;
    const tick = () => {
      if (stop) return;
      pos++;
      setOut(lines[i].slice(0, pos));
      if (pos < lines[i].length) {
        setTimeout(tick, speedMs);
      } else {
        setTimeout(() => {
          if (stop) return;
          setI(prev => (prev + 1) % lines.length);
          pos = 0;
          setOut('');
          setTimeout(tick, 200);
        }, pauseMs);
      }
    };
    const t = setTimeout(tick, 400);
    return () => { stop = true; clearTimeout(t); };
  }, [i]);
  return out;
}

// ── Blinking cursor ─────────────────────────────────────────────
function Cursor({ color = 'currentColor', height = '1em' }) {
  return (
    <span style={{
      display: 'inline-block', width: '0.55em', height,
      background: color, marginLeft: 1, verticalAlign: 'text-bottom',
      animation: 'cc-blink 1.05s steps(2) infinite',
    }} />
  );
}

Object.assign(window, {
  DotGridBg, AuroraOrbs, PulseDot, Icon, StatusPill, SectionLabel,
  GlassCard, useTypewriter, useLoopType, Cursor,
});
